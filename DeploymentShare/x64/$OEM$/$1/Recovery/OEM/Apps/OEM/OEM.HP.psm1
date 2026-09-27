<#
.SYNOPSIS
    HP OEM module.

.DESCRIPTION
    Implements the OEM contract. Custom installers handle the SoftPaq
    wrapper pattern used by HP Support Assistant, HP PC Hardware
    Diagnostics Windows, and HP PC Hardware Diagnostics UEFI.

    HP PC Hardware Diagnostics UEFI is a special case for presence
    detection. The MSI does not register in AppX or in the Uninstall
    registry. Its presence is established from two signals, in order:

      1. The durable registry marker
         HKLM\SOFTWARE\OEM\HP\UEFIDiagnosticsInstalled, written by this
         module on a verified success.
      2. The installer's own log at C:\Windows\HP\installer.log. A log
         whose last "Installer returned error code" line is 0 records a
         successful installation by the installer itself. When the log
         shows success and the marker is absent (e.g. the marker write
         was interrupted on a prior run), the marker is adopted from
         the log and the app is recorded as AlreadyCurrent.

    The log is never deleted: it is diagnostic evidence and the
    installer's own record of success. The log is authoritative for
    this app because the MSI exposes no AppX or Uninstall-registry
    presence signal the framework can query. The module supplies
    TestAppPresence to define presence for this app via the marker,
    and Install-HPDiagnosticsUEFI writes the marker from the log.
    The framework's phase-level presence short-circuit consults the
    marker, not Test-ApplicationInstalled, for this app. If the hook
    is ever removed, the framework falls back to
    Test-ApplicationInstalled and the marker would no longer be
    consulted at phase level.
#>

# --- System family ---

function Get-HPSystemFamily {
    $cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $se  = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue

    $target = @(
        $cs.Model
        $cs.SystemSKUNumber
        $csp.Name
        $se.ChassisSKU
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToString().Trim() }

    $joined = $target -join ' '
    if ($joined -match '(?i)\b(OMEN|Victus)\b')                                                                { return 'Gaming' }
    # Z\d+ matches the "Z by HP" workstation line (Z2 Mini, Z4, Z6, Z8 Fury).
    if ($joined -match '(?i)\b(EliteBook|ProBook|ZBook|Z\d+|Dragonfly|ProDesk|EliteDesk|EliteOne|ProOne|Elite ?Mini|Elite ?Tower|Elite ?SFF)\b') { return 'Commercial' }
    if ($joined -match '(?i)\b(Spectre|Envy|Pavilion|Presario|HP\s+Laptop|Laptop\s+\d+|14s|15s|HP\s+2[45]\d[GR]?|OmniBook|OmniStudio|OmniDesk)\b') { return 'Consumer' }
    return 'Unknown'
}

function Test-HPAppEligibility {
    param($App, $SystemFamily)
    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }
    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). HP defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-HPDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

# --- Custom installer: HP Support Assistant ---

function Install-HPSupportAssistant {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        $WingetResult
    )

    # Presence is the authoritative success criterion. If already present, done.
    # Route through Test-AppPresence so the framework's hook-aware identity
    # precedence (WingetAppId -> AppxPackageName / AppName -> AlternateAppNames)
    # governs the check, matching the phase loop and the health check.
    Clear-ApplicationCaches
    if (Test-AppPresence -Context $Context -App $App) {
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        return $true
    }

    $supportDir = $App.InstallerPath
    $wrapper = Get-ChildItem -Path $supportDir -Filter 'sp*.exe' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $wrapper) {
        Write-DeploymentLog -Message "No SoftPaq wrapper in $supportDir" -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    $logDir = 'C:\system.sav\logs'
    $dismLog = Join-Path $logDir 'HPSAUWP_dism.log'
    $cppLog  = Join-Path $logDir 'HPSASetUpCpp.txt'
    try {
        New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null
        Remove-Item -Path $dismLog -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $cppLog  -Force -ErrorAction SilentlyContinue
    } catch {}

    # Manifest InstallerArgs is the single source of truth. Preflight
    # guarantees the field is present on custom-installer apps; empty
    # string means "no arguments."
    $softPaqArgs = [string]$App.InstallerArgs
    Write-DeploymentLog -Message "Launching SoftPaq: $($wrapper.Name) $softPaqArgs" -Level INFO -AppName $App.AppName
    $proc = $null
    Push-Location $supportDir
    try {
        $proc = Start-Process -FilePath $wrapper.FullName -ArgumentList $softPaqArgs -PassThru -WindowStyle Hidden
    }
    catch {
        Pop-Location
        Write-DeploymentLog -Message "SoftPaq launch failed: $($_.Exception.Message)" -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }
    Pop-Location

    if (-not $proc) {
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    Start-Sleep -Seconds 5

    $allExited = {
        if ($proc -and -not $proc.HasExited) { return $false }
        if (Get-Process -Name 'installHPSA' -ErrorAction SilentlyContinue) { return $false }
        return $true
    }

    $totalTimeout = if ($Context.Profile.LocalTimeoutSeconds) { [int]$Context.Profile.LocalTimeoutSeconds } else { 600 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $presenceDetected = $false
    $dismComplete = $false
    $nextPresenceCheck = [datetime]::MinValue
    Write-DeploymentLog -Message "Monitoring HPSA installation (up to $([int]($totalTimeout/60)) minutes)..." -Level INFO -AppName $App.AppName

    # Presence polling uses a 30-second interval. Each iteration that clears
    # the caches re-queries AppX (Get-AppxPackage -AllUsers) and the
    # provisioned package list (DISM), which is expensive on slow disks and
    # competes with the running installer. Package presence is a step
    # function, not a heartbeat, so a 30-second cadence adds at most 30s to
    # the detection latency while reducing enumeration calls ~6x versus the
    # prior 5-second cadence. The DISM-complete check and the allExited
    # predicate are independent terminators that fire on their own cadence.
    while ($sw.Elapsed.TotalSeconds -lt $totalTimeout) {
        if (-not $presenceDetected -and (Get-Date) -ge $nextPresenceCheck) {
            Clear-ApplicationCaches
            if (Test-ApplicationInstalled -AppName 'HP Support Assistant' -AppxPackageName 'AD2F1837.HPSupportAssistant') {
                $presenceDetected = $true
                Write-DeploymentLog -Message "HP Support Assistant package detected." -Level INFO -AppName $App.AppName
            }
            $nextPresenceCheck = (Get-Date).AddSeconds(30)
        }
        if (-not $dismComplete -and (Test-Path $dismLog)) {
            $content = Get-Content $dismLog -Raw -ErrorAction SilentlyContinue
            if ($content -match 'Ending Dism.exe session') {
                $dismComplete = $true
                Write-DeploymentLog -Message "DISM provisioning completed." -Level INFO -AppName $App.AppName
            }
        }
        if ($presenceDetected -and $dismComplete) {
            Write-DeploymentLog -Message "Both presence and DISM complete. Entering HPSA finalization wait." -Level INFO -AppName $App.AppName
            break
        }
        if (& $allExited) {
            Write-DeploymentLog -Message "All HPSA processes exited. Proceeding to final checks." -Level INFO -AppName $App.AppName
            break
        }
        Start-Sleep -Seconds 5
    }

    if (-not (& $allExited)) {
        # 2026-09-24 functional-validation gap: DESKTOP-USRKD5E (HPSA
        # working post-install) and DESKTOP-KVHFROR (HPSA broken post-
        # install) ran the identical close sequence — full 180s window,
        # framework-issued CloseMainWindow(), both processes exited within ~3
        # seconds, HPSASetUpCpp.txt exit code 0, AppX package present —
        # and both classified Installed. The window value alone is not
        # determinative. Root cause and discriminating variable both
        # unidentified; do not adjust the window or the lifecycle on
        # this evidence. See STATUS.md §6.18 for the open questions.
        #
        # HPSA finalization has been observed to run to 82 seconds past
        # the DISM-complete signal on machines where the SoftPaq performs
        # an uninstall-then-reinstall cycle over a pre-existing HPSA 9
        # registration. The trigger is not the OEM factory image —
        # deployments run on clean Windows images. Residual HPSA 9 app state
        # is ruled out as the trigger: on a clean Windows image
        # (DESKTOP-SOMOLP1, 2026-09-23) the installer's own log records
        # 'HPSA 8 or Framework not been installed before', then immediately
        # runs 'Start to uninstall HPSA 9'. Two live hypotheses remain:
        # the SoftPaq runs the uninstall step unconditionally as a defensive
        # pre-flight, or it detects the HP Support Framework services
        # (HPSysInfoCap, HPAppHelperCap) which ship via HP driver packages
        # pushed by Windows Update and are present on any HP machine
        # regardless of image. Which of the two is the trigger is not
        # established by the current evidence. Separately, the installer's post-DISM
        # finalization phase on the affected machines has been observed
        # at 82 seconds (16:58:26 to 16:59:49 on DESKTOP-1HO0TFG), which
        # exceeds the framework's fixed 60-second wait. Whether the
        # extended phase is caused by the uninstall step, by the post-
        # DISM work common to every install, or by both is not
        # established by the current evidence; the observation is that
        # the finalization phase exceeded the wait on the affected
        # machines.
        #
        # On DESKTOP-1HO0TFG (2026-09-19) the installer wrote its exit
        # code 0 at 16:59:49, one second AFTER the framework's fixed
        # 60-second wait had elapsed and CloseMainWindow() was sent at
        # 16:59:48. The AppX package was provisioned (the framework's
        # presence check saw it), but the finalization phase — service
        # registration, HSA framework configuration, preference
        # restoration — was interrupted by the close signal. The AppX
        # package was present; the app was broken, and the operator's
        # remediation was a full uninstall / reinstall cycle from the
        # SoftPaq-extracted uninstaller.
        #
        # Poll for natural exit up to 180 seconds; on machines where the
        # installer exits on its own this terminates within seconds, so the
        # longer ceiling costs nothing in the common case and gives slow
        # machines room to complete registration.
        $finalizeDeadline = (Get-Date).AddSeconds(180)
        $finalizeSw = [Diagnostics.Stopwatch]::StartNew()
        Write-DeploymentLog -Message "Waiting up to 180 seconds for HPSA to finalize before gentle close..." -Level INFO -AppName $App.AppName
        while ((Get-Date) -lt $finalizeDeadline -and -not (& $allExited)) {
            Start-Sleep -Seconds 5
        }
        if (& $allExited) {
            Write-DeploymentLog -Message "HPSA finalized naturally after $([math]::Round($finalizeSw.Elapsed.TotalSeconds, 1)) seconds." -Level INFO -AppName $App.AppName
        } else {
            Write-DeploymentLog -Message "HPSA did not finalize within 180 seconds; proceeding to gentle close." -Level WARN -AppName $App.AppName
        }
    }

    Write-DeploymentLog -Message "Pre-close state: installHPSA running=$([bool](Get-Process -Name 'installHPSA' -ErrorAction SilentlyContinue)), wrapper running=$($proc -and -not $proc.HasExited)." -Level INFO -AppName $App.AppName

    # Gentle close
    if (-not (& $allExited)) {
        Write-DeploymentLog -Message "Sending CloseMainWindow() to installHPSA.exe..." -Level INFO -AppName $App.AppName
        $installProc = Get-Process -Name 'installHPSA' -ErrorAction SilentlyContinue
        if ($installProc) {
            foreach ($p in $installProc) {
                try { $p.CloseMainWindow() | Out-Null } catch {}
                try { $null = $p.WaitForExit(5000) } catch {}
            }
        }
        Start-Sleep -Seconds 3
        $still = Get-Process -Name 'installHPSA' -ErrorAction SilentlyContinue
        Write-DeploymentLog -Message "After CloseMainWindow(): installHPSA running=$([bool]$still), wrapper running=$($proc -and -not $proc.HasExited)." -Level INFO -AppName $App.AppName
        if ($still) {
            Write-DeploymentLog -Message "installHPSA still running after gentle close. Forcefully terminating..." -Level WARN -AppName $App.AppName
            foreach ($p in $still) { try { $p.Kill() } catch {}; try { $null = $p.WaitForExit(5000) } catch {} }
        }
        if ($proc -and -not $proc.HasExited) {
            Write-DeploymentLog -Message "SoftPaq wrapper still running. Forcefully terminating..." -Level WARN -AppName $App.AppName
            try { $proc.Kill() } catch {}
            try { $null = $proc.WaitForExit(5000) } catch {}
        }
    }

    # Poll C++ log up to 60s
    $cppWaitTimeout = 60
    $deadline = (Get-Date).AddSeconds($cppWaitTimeout)
    $swLog = [Diagnostics.Stopwatch]::StartNew()
    $cppFound = $false
    Write-DeploymentLog -Message "Polling for HPSASetUpCpp.txt (up to ${cppWaitTimeout} seconds)..." -Level INFO -AppName $App.AppName
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $cppLog) {
            $cppContent = Get-Content $cppLog -Raw -ErrorAction SilentlyContinue
            if ($cppContent -match '(?i)exit\s*code\s*[:=]\s*(-?\d+|0x[0-9A-Fa-f]+)') {
                $raw = $Matches[1]
                try {
                    $code = if ($raw -match '^0x') { [Convert]::ToInt64($raw.Substring(2),16) } else { [int64]$raw }
                    $cppFound = $true
                    Write-DeploymentLog -Message "C++ log found after $([math]::Round($swLog.Elapsed.TotalSeconds, 1)) seconds. Exit code: $code" -Level INFO -AppName $App.AppName
                    if ($code -in @(1641,3010)) { $Context.RebootRequired = $true }
                } catch {
                    Write-DeploymentLog -Message "C++ log contains unparseable exit code '$raw'. Treating as log absent." -Level WARN -AppName $App.AppName
                }
                break
            }
        }
        Start-Sleep -Seconds 5
    }
    if (-not $cppFound) {
        Write-DeploymentLog -Message "C++ log not found within ${cppWaitTimeout}s. Falling back to package presence..." -Level WARN -AppName $App.AppName
    }

    Clear-ApplicationCaches
    $present = Test-AppPresence -Context $Context -App $App
    if ($present) {
        Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
        return $true
    }
    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
    return $false
}

# --- Custom installer: HP PC Hardware Diagnostics Windows ---

function Install-HPDiagnosticsWindows {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        $WingetResult
    )

    # Route through Test-AppPresence so the framework's hook-aware identity
    # precedence governs the check. The HP profile's TestAppPresence hook
    # declines for this app, so detection falls through to the framework's
    # WingetAppId -> AppxPackageName chain, matching the phase loop.
    Clear-ApplicationCaches
    if (Test-AppPresence -Context $Context -App $App) {
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        return $true
    }

    $diagDir = $App.InstallerPath
    $wrapper = Get-ChildItem -Path $diagDir -Filter 'sp*.exe' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $wrapper) {
        Write-DeploymentLog -Message "No SoftPaq wrapper in $diagDir" -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    # Manifest InstallerArgs is the single source of truth.
    $softPaqArgs = [string]$App.InstallerArgs
    Write-DeploymentLog -Message "Launching SoftPaq: $($wrapper.Name) $softPaqArgs" -Level INFO -AppName $App.AppName
    $proc = $null
    try { $proc = Start-Process -FilePath $wrapper.FullName -ArgumentList $softPaqArgs -PassThru -WindowStyle Hidden }
    catch {
        Write-DeploymentLog -Message "SoftPaq launch failed: $($_.Exception.Message)" -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }
    if (-not $proc) {
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    $timeout = if ($Context.Profile.LocalTimeoutSeconds) { [int]$Context.Profile.LocalTimeoutSeconds } else { 600 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-DeploymentLog -Message "Monitoring Diagnostics Windows installation (up to $([int]($timeout/60)) minutes)..." -Level INFO -AppName $App.AppName

    # Poll for package presence OR wrapper exit. Terminal success is decided
    # by the post-loop presence check; the loop's only job is to stop polling
    # once one of these conditions is reached. The 10-second sleep after
    # wrapper exit gives AppX a moment to register the just-provisioned
    # package before the post-loop check runs.
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        Clear-ApplicationCaches
        # In-loop detection deliberately uses Test-ApplicationInstalled rather
        # than Test-AppPresence. This is a "has the just-provisioned package
        # landed yet?" poll, not a hook-aware presence verdict: its answer
        # only controls whether the polling loop terminates early, not the
        # terminal classification. Calling Test-AppPresence here would invoke
        # a winget query on every iteration in USER phase.
        if (Test-ApplicationInstalled -AppName 'HP PC Hardware Diagnostics Windows' -AppxPackageName 'AD2F1837.HPPCHardwareDiagnosticsWindows') {
            Write-DeploymentLog -Message "HP PC Hardware Diagnostics Windows package detected." -Level INFO -AppName $App.AppName
            break
        }
        if ($proc.HasExited) {
            Write-DeploymentLog -Message "Wrapper exited before package detection. Waiting 10 seconds for final package registration..." -Level INFO -AppName $App.AppName
            Start-Sleep -Seconds 10
            break
        }
        Start-Sleep -Seconds 10
    }

    if ($proc -and -not $proc.HasExited) {
        Write-DeploymentLog -Message "Wrapper still running after detection. Sending CloseMainWindow..." -Level INFO -AppName $App.AppName
        try { $proc.CloseMainWindow() | Out-Null } catch {}
        try { $null = $proc.WaitForExit(5000) } catch {}
        if ($proc -and -not $proc.HasExited) {
            Write-DeploymentLog -Message "Wrapper still running after CloseMainWindow. Forcefully terminating..." -Level WARN -AppName $App.AppName
            try { $proc.Kill() } catch {}
            try { $null = $proc.WaitForExit(5000) } catch {}
        } else {
            Write-DeploymentLog -Message "Wrapper exited after CloseMainWindow." -Level INFO -AppName $App.AppName
        }
    } else {
        Write-DeploymentLog -Message "Wrapper already exited before cleanup." -Level INFO -AppName $App.AppName
    }

    Clear-ApplicationCaches
    if (Test-AppPresence -Context $Context -App $App) {
        Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
        return $true
    }
    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
    return $false
}

# --- Custom installer: HP PC Hardware Diagnostics UEFI ---

function Test-HPUEFIDiagnosticsInstalled {
    $marker = Get-ItemProperty -Path 'HKLM:\SOFTWARE\OEM\HP' -Name 'UEFIDiagnosticsInstalled' -ErrorAction SilentlyContinue
    return ($marker -and $marker.UEFIDiagnosticsInstalled -eq 1)
}

function Test-HPAppPresence {
    param($App, $Context)
    if ($App.AppName -eq 'HP PC Hardware Diagnostics UEFI') {
        # The UEFI MSI does not register in AppX or Uninstall; its presence
        # for detection purposes is the durable registry marker. Reflecting
        # that here makes the framework's phase-level presence short-circuit
        # accurate and mirrors the monolith's SYSTEM-phase marker check.
        return (Test-HPUEFIDiagnosticsInstalled)
    }

    # Any other HP app: the hook declines to render a verdict. Returning
    # $null hands the app back to the framework's identity precedence
    # chain (WingetAppId -> AppxPackageName / AppName -> AlternateAppNames).
    # Falling through to Test-ApplicationInstalled here would bypass the
    # WingetAppId identity check for HP apps that declare one.
    return $null
}

function Test-HPUEFIDiagnosticsLogInstalled {
    # The UEFI diagnostics installer writes its own verdict to
    # C:\Windows\HP\installer.log on every run. A log whose last
    # "Installer returned error code" line is 0 records a successful
    # installation. That log is the durable evidence for this app:
    # the MSI does not register in AppX or the Uninstall registry, and
    # the registry marker (UEFIDiagnosticsInstalled) is written by this
    # module based on this same log. If the log says success, the app
    # was installed; no further probing is required or meaningful.
    $logPath = 'C:\Windows\HP\installer.log'
    if (-not (Test-Path -LiteralPath $logPath)) { return $false }
    $content = Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) { return $false }
    # Variable name deliberately avoids $Matches: PowerShell's automatic
    # $Matches is populated on every successful -match and would be silently
    # clobbered by any future -match inserted between this line and the
    # extraction below.
    $exitCodeMatches = [regex]::Matches($content, 'Installer returned error code\s+(0x[0-9A-Fa-f]+|\d+)')
    if ($exitCodeMatches.Count -eq 0) {
        Write-DeploymentLog -Message "UEFI installer.log present but no exit-code line found; format may have changed." -Level WARN
        return $false
    }
    $last = $exitCodeMatches[$exitCodeMatches.Count - 1].Groups[1].Value
    try {
        if ($last -match '^0x') { return ([Convert]::ToInt64($last.Substring(2), 16) -eq 0) }
        return ([int64]$last -eq 0)
    } catch { return $false }
}

function Install-HPDiagnosticsUEFI {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        $WingetResult
    )

    # Presence signal 1: the registry marker written by this module on a
    # prior verified success.
    if (Test-HPUEFIDiagnosticsInstalled) {
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        return $true
    }

    # Presence signal 2: the installer's own log. A log whose last
    # "Installer returned error code" line is 0 records a successful
    # installation by the installer itself. The UEFI MSI exposes no
    # AppX or Uninstall-registry presence signal the framework can
    # query, so the log is the module's only queryable installation
    # evidence independent of our marker. If the log says success,
    # promote it to a marker and short-circuit.
    if (Test-HPUEFIDiagnosticsLogInstalled) {
        Write-DeploymentLog -Message 'UEFI diagnostics installer log records a prior successful installation; adopting it as presence and writing the marker.' -Level INFO -AppName $App.AppName
        $markerWritten = Set-RegistryValueSilent -Path 'HKLM:\SOFTWARE\OEM\HP' -Name 'UEFIDiagnosticsInstalled' -Value 1 -Type 'DWord'
        if (-not $markerWritten) {
            Write-DeploymentLog -Message 'UEFI diagnostics log shows success, but the installation marker could not be verified.' -Level ERROR -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        return $true
    }

    $msi = $App.InstallerPath
    if (-not (Test-Path $msi)) {
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    $timeout = if ($Context.Profile.LocalTimeoutSeconds) { [int]$Context.Profile.LocalTimeoutSeconds } else { 600 }

    if (-not (Wait-ForMSI -TimeoutSeconds $timeout)) {
        Write-DeploymentLog -Message 'MSI engine mutex did not release in time.' -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    $exitCode = 1
    $timedOut = $false
    try {
        # Manifest InstallerArgs is the single source of truth.
        $msiArgs = [string]$App.InstallerArgs
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList "/i `"$msi`" $msiArgs" `
            -PassThru -WindowStyle Hidden
        if (-not $proc.WaitForExit($timeout * 1000)) {
            try { $proc.Kill() } catch {}
            try { $null = $proc.WaitForExit(5000) } catch {}
            $timedOut = $true
            Write-DeploymentLog -Message "UEFI MSI did not finish after ${timeout}s; process killed. Evaluating log evidence anyway." -Level WARN -AppName $App.AppName
        }
        else {
            $exitCode = $proc.ExitCode
        }
    }
    catch {
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    if (-not $timedOut -and $exitCode -in @(1641,3010)) { $Context.RebootRequired = $true }

    # Poll for the log to record a success code, up to 60s.
    $deadline = (Get-Date).AddSeconds(60)
    $logSuccess = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-HPUEFIDiagnosticsLogInstalled) { $logSuccess = $true; break }
        Start-Sleep -Seconds 5
    }

    if ($logSuccess) {
        $markerWritten = Set-RegistryValueSilent -Path 'HKLM:\SOFTWARE\OEM\HP' -Name 'UEFIDiagnosticsInstalled' -Value 1 -Type 'DWord'
        if (-not $markerWritten) {
            Write-DeploymentLog -Message 'UEFI diagnostics log shows success, but the installation marker could not be verified.' -Level ERROR -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }
        Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
        return $true
    }
    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
    return $false
}

# --- Profile ---

function Invoke-HPLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'HP'
        ManifestFile         = 'HP.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\HP'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'HP_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'HPPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-HPSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-HPAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        TestAppPresence                  = { param($App, $Context) Test-HPAppPresence -App $App -Context $Context }
        OnSystemPreInstall               = { param($Context) Invoke-HPDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-HPLiveUserSpotlightSuppression }

        CustomInstallers = @{
            'Install-HPSupportAssistant'   = { param($App, $Context, $WingetResult) Install-HPSupportAssistant   -App $App -Context $Context -WingetResult $WingetResult }
            'Install-HPDiagnosticsWindows' = { param($App, $Context, $WingetResult) Install-HPDiagnosticsWindows -App $App -Context $Context -WingetResult $WingetResult }
            'Install-HPDiagnosticsUEFI'    = { param($App, $Context, $WingetResult) Install-HPDiagnosticsUEFI    -App $App -Context $Context -WingetResult $WingetResult }
        }
    }
}

Export-ModuleMember -Function Get-OEMProfile
