<#
.SYNOPSIS
    Huawei OEM module.

.DESCRIPTION
    Implements the OEM contract. One OEM application: PC Manager. PC Manager
    has no AppX package and no winget ID — it installs from a local
    interactive .exe and creates an all-users Start Menu shortcut. Presence
    is defined by that shortcut, not by AppX/Uninstall. All Huawei apps are
    UserOnly; SYSTEM phase does no app work.
#>

# --- PC Manager identity ---

function Get-HuaweiPCManagerShortcutPath {
    # The PC Manager installer places its shortcut in the all-users Start
    # Menu. This is the sole presence signal for the app.
    return [Environment]::ExpandEnvironmentVariables(
        '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Huawei\PC Manager.lnk')
}

# --- System family ---

function Get-HuaweiSystemFamily {
    $invalid = @(
        'Default string','Not Applicable','Not Available',
        'System Product Name','System Version',
        'To be filled by O.E.M.','Type1ProductConfigId'
    )

    $values = @(
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Name
        (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Version
    ) | ForEach-Object { if ($_ -ne $null) { $_.ToString().Trim() } else { $null } } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Where-Object { $_ -notin $invalid }

    if (-not $values -or $values.Count -eq 0) { return 'Unknown' }

    # Keyword enrichment: prefer a readable MateBook/MateStation/MatePad/Mate/Huawei
    # model string over a bare product ID. Then classify.
    $familyKeywords = @('MateBook','MateStation','MatePad','Mate','Huawei')
    $model = $null
    foreach ($candidate in $values) {
        foreach ($keyword in $familyKeywords) {
            if ($candidate -match [regex]::Escape($keyword)) { $model = $candidate; break }
        }
        if ($model) { break }
    }
    if (-not $model) {
        $model = $values |
            Sort-Object @{ Expression = { $_.Length }; Descending = $true },
                        @{ Expression = { $_ };       Descending = $false } |
            Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($model)) { return 'Unknown' }

    switch -Regex ($model) {
        '(?i)\b(MateBook)\b'    { return 'MateBook' }
        '(?i)\b(MateStation)\b' { return 'MateStation' }
        '(?i)\b(MatePad)\b'     { return 'MatePad' }
        default                 { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-HuaweiAppEligibility {
    param($App, $SystemFamily)

    # No MobileOnly gate. PC Manager runs on Huawei's desktop line
    # (MateStation) as well as its laptops; the monolith's mobile gate
    # was a unification artifact carried across during porting, not a
    # Huawei product requirement. If a future Huawei app genuinely needs
    # mobile-only scoping, re-introduce the gate at that time.
    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Presence hook ---

function Test-HuaweiAppPresence {
    param($App, $Context)

    if ($App.AppName -eq 'PC Manager') {
        # The PC Manager installer does not register in AppX or Uninstall.
        # Its presence is the all-users Start Menu shortcut.
        return (Test-Path (Get-HuaweiPCManagerShortcutPath))
    }

    # Any other Huawei app: the hook declines to render a verdict. Returning
    # $null hands the app back to the framework's identity precedence chain
    # (WingetAppId -> AppxPackageName / AppName -> AlternateAppNames).
    # Falling through to Test-ApplicationInstalled here would bypass the
    # WingetAppId identity check for Huawei apps that declare one, and
    # would diverge from the HP and Acer modules' decline semantics.
    return $null
}

# --- Custom installer: PC Manager ---

function Get-HuaweiPCManagerInstallerProcess {
    # Returns any running PC Manager installer process. Used to avoid
    # launching a second instance when a previous installer was left running
    # after a prior run's timeout.
    #
    # $_.Path throws under $ErrorActionPreference='Stop' when MainModule
    # cannot be read (protected processes, exited-but-not-reaped). Guard the
    # property access inside the filter so one unreadable process does not
    # terminate the whole pipeline.
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $procPath = $null
            try { $procPath = $_.Path } catch { return $false }
            $procPath -and
            $procPath -like "*\PCManager\*" -and
            $procPath -like "*.exe"
        }
}

function Install-HuaweiPCManager {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        $WingetResult
    )

    # PC Manager is interactive. The manifest declares InstallPhase: "UserOnly",
    # so the framework should never call this from SYSTEM phase. Guard
    # defensively in case a future manifest misconfiguration slips through.
    if ($Context.IsSystem) {
        Write-DeploymentLog -Message "PC Manager: refused to install in SYSTEM context." -Level WARN -AppName $App.AppName
        Add-UniqueValue -List $Context.SkippedApps -Value $App.AppName
        return $false
    }

    $shortcutPath = Get-HuaweiPCManagerShortcutPath

    # Presence is the authoritative success criterion. If already present, done.
    if (Test-Path $shortcutPath) {
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        return $true
    }

    # If a previous run timed out and left the installer running, do not
    # launch a second instance. Poll the existing one instead.
    $proc = Get-HuaweiPCManagerInstallerProcess | Select-Object -First 1
    $attached = $false

    if ($proc) {
        Write-DeploymentLog -Message "PC Manager: an installer is already running (PID $($proc.Id)); attaching to it." -Level INFO -AppName $App.AppName
        $attached = $true
    } else {
        # Locate the newest .exe under the installer folder. Fall back to
        # Get-InstallationPackage's priority list if no bare .exe is present.
        $package = $null
        if (Test-Path $App.InstallerPath) {
            $package = Get-ChildItem -Path $App.InstallerPath -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $package) {
                $package = Get-InstallationPackage -Path $App.InstallerPath
            }
        }

        if (-not $package) {
            Write-DeploymentLog -Message "PC Manager: no installer found under $($App.InstallerPath)" -Level ERROR -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }

        Write-DeploymentLog -Message "PC Manager: launching interactive installer $($package.Name)" -Level INFO -AppName $App.AppName

        try {
            # Interactive installer. -WindowStyle Normal is required: PC Manager
            # provides no silent switches and requires user interaction.
            $proc = Start-Process -FilePath $package.FullName -PassThru -WindowStyle Normal
        } catch {
            Write-DeploymentLog -Message "PC Manager: launch failed: $($_.Exception.Message)" -Level ERROR -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }

        if (-not $proc) {
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }
    }

    # Poll for the shortcut. Framework default LocalTimeoutSeconds is 600.
    $timeout = if ($Context.Profile.LocalTimeoutSeconds) { [int]$Context.Profile.LocalTimeoutSeconds } else { 600 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $actionLabel = if ($attached) { 'attached installer' } else { 'installer' }
    Write-DeploymentLog -Message "Monitoring PC Manager $actionLabel (up to $([int]($timeout/60)) minutes; user interaction may be required)..." -Level INFO -AppName $App.AppName

    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        if (Test-Path $shortcutPath) {
            Clear-ApplicationCaches
            Write-DeploymentLog -Message "PC Manager shortcut detected." -Level INFO -AppName $App.AppName
            Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
            return $true
        }

        # A process we launched that has exited, or an attached process that
        # is no longer running, is treated as "installer finished" — check the
        # shortcut one more time after a short grace period.
        $stillRunning = $false
        if ($proc) {
            try { $stillRunning = -not $proc.HasExited } catch { $stillRunning = $false }
        }
        if (-not $stillRunning) {
            Start-Sleep -Seconds 10
            Clear-ApplicationCaches
            if (Test-Path $shortcutPath) {
                Write-DeploymentLog -Message "PC Manager shortcut detected after $actionLabel exit." -Level INFO -AppName $App.AppName
                Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
                return $true
            }
            Write-DeploymentLog -Message "PC Manager: installer exited without producing the shortcut." -Level WARN -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            return $false
        }

        Start-Sleep -Seconds 10
    }

    # Timeout. Leave the installer running if we launched it or attached to it;
    # it may still be waiting for user interaction. Mark the app failed so the
    # phase does not converge and the resume task retries on the next logon.
    # If the user completes interactively in the meantime, the next run will
    # find the shortcut and mark AlreadyCurrent.
    Clear-ApplicationCaches
    if (Test-Path $shortcutPath) {
        Write-DeploymentLog -Message "PC Manager shortcut detected at timeout boundary." -Level INFO -AppName $App.AppName
        Add-UniqueValue -List $Context.InstalledApps -Value $App.AppName
        return $true
    }

    Write-DeploymentLog -Message "PC Manager: $actionLabel did not complete within $timeout s; installer left running for user interaction. App marked failed; retry on next logon." -Level WARN -AppName $App.AppName
    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
    return $false
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Huawei defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-HuaweiDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-HuaweiLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Huawei'
        ManifestFile         = 'Huawei.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Huawei'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Huawei_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'HuaweiPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600    # PC Manager is interactive; 10 min per attempt
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-HuaweiSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-HuaweiAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        TestAppPresence                  = { param($App, $Context) Test-HuaweiAppPresence -App $App -Context $Context }
        OnSystemPreInstall               = { param($Context) Invoke-HuaweiDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-HuaweiLiveUserSpotlightSuppression }

        CustomInstallers = @{
            'Install-HuaweiPCManager' = { param($App, $Context, $WingetResult) Install-HuaweiPCManager -App $App -Context $Context -WingetResult $WingetResult }
        }
    }
}

Export-ModuleMember -Function Get-OEMProfile
