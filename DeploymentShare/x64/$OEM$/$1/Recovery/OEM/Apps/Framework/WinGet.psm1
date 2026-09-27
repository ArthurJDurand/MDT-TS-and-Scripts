<#
.SYNOPSIS
    Vendor-neutral WinGet install engine.

.DESCRIPTION
    Contract:
      - USER phase only (SYSTEM callers must gate before invoking).
      - Machine scope first, source-independent.
      - `winget install` only, never `upgrade`.
      - Transient exit codes retry same scope (up to 3 attempts).
      - -2145091577 triggers one default-scope retry.
      - 0x8A15002B is success only if state check confirms installed.
      - 0x8A15005E forces Failed regardless of state (sole override).
      - Per-invocation timeout supplied by the caller (Profile.WinGetTimeoutSeconds).
      - Terminal classification is state-derived except for the 0x8A15005E override.
      - Certificate-pinning bypass baseline captured and restored. The bypass
        exists because some deployment environments (SSL inspection appliances,
        corporate proxies) present certificates that break the Microsoft Store's
        pinned certificate chain, causing otherwise-valid installs to fail with
        0x8A15005E. The bypass is enabled at USER-phase start and disabled at
        phase end (or on any exit path), so the machine's baseline admin setting
        is never permanently altered.
      - Readiness poll runs once per phase (Initialize-WinGetSession).
      - Presence checks (pre/post) use Test-WingetInstalledState, which
        prefers the exact WinGet package identity when a WingetAppId is
        available (queried via `winget list --id <PackageId> --exact`),
        then falls back to exact AppName/AppxPackageName detection, then
        each AlternateAppNames entry with exact matching, before
        declining. WinGet operates on the package identity directly and
        therefore does not call the OEM's TestAppPresence hook; see
        ARCHITECTURE.md §7 for the full identity chain and its rationale.
#>

# ---------------------------------------------------------------------------
# WinGet exit-code classification
#
# Evidence handling, in order:
#
#   1. Structured state      — pre-install presence and version, read via
#                              Test-WingetInstalledState and
#                              Get-ApplicationVersion.
#   2. Known classifications — the exit-code sets declared below drive
#                              retry, scope fallback, and the sole
#                              certificate-mismatch override.
#   3. stdout/stderr         — captured for the per-app log; not consulted
#                              for classification.
#   4. Post-install state    — authoritative terminal classification: the
#                              framework classifies by whether the app is
#                              present after the attempt, except when
#                              0x8A15005E makes the state check
#                              untrustworthy (override forces Failed).
#
# Every code the engine acts on is declared here so a reader can see, at a
# glance, how each exit code will be handled. Codes not listed here fall
# through to post-install state verification: if the app is present, it
# classifies by state; if absent, it becomes a Failed classification.
# ---------------------------------------------------------------------------

$script:WingetSuccessCodes = @(
    0,                   # success
    1641,                # ERROR_SUCCESS_REBOOT_INITIATED
    3010,                # ERROR_SUCCESS_REBOOT_REQUIRED
    [int]0x8A150109      # APPINSTALLER_CLI_ERROR_INSTALL_REBOOT_REQUIRED_TO_FINISH
)

$script:WingetRetryCodes = @(
    # Network transport failures — retry same scope.
    [int]0x80072EE7,   # WININET_E_NAME_NOT_RESOLVED (DNS)
    [int]0x80072EFD,   # WININET_E_CANNOT_CONNECT
    [int]0x80072EFE,   # WININET_E_CONNECTION_ABORTED
    [int]0x801901F7,   # HTTP_E_STATUS_SERVER_ERROR (500)
    [int]0x80190194,   # HTTP_E_STATUS_NOT_FOUND (404)
    # WinGet service and install-activity failures — retry same scope.
    [int]0x8A15006D,   # APPINSTALLER_CLI_ERROR_SERVICE_UNAVAILABLE
    [int]0x8A150102,   # APPINSTALLER_CLI_ERROR_INSTALL_IN_PROGRESS
    [int]0x8A150101,   # APPINSTALLER_CLI_ERROR_INSTALL_PACKAGE_IN_USE
    [int]0x8A150103,   # APPINSTALLER_CLI_ERROR_INSTALL_FILE_IN_USE
    [int]0x8A150106,   # APPINSTALLER_CLI_ERROR_INSTALL_INSUFFICIENT_MEMORY
    [int]0x8A150107,   # APPINSTALLER_CLI_ERROR_INSTALL_NO_NETWORK
    [int]0x8A150008,   # APPINSTALLER_CLI_ERROR_DOWNLOAD_FAILED
    [int]0x8A15003B,   # APPINSTALLER_CLI_ERROR_RESTAPI_INTERNAL_ERROR
    [int]0x8A150040,   # APPINSTALLER_CLI_ERROR_STREAM_READ_FAILURE
    [int]0x8A150045,   # APPINSTALLER_CLI_ERROR_SOURCE_OPEN_FAILED
    [int]0x8A15004B    # APPINSTALLER_CLI_ERROR_FAILED_TO_OPEN_ALL_SOURCES
)

# Empirical: machine-scope incompatibility signal. Triggers a scope
# transition to default scope (no --scope argument); the normal
# transient-retry policy then applies within that scope, matching the
# retry behavior of the initial machine-scope attempt. Not a
# Microsoft-documented code; classified from controlled testing.
$script:MachineScopeIncompatCode = -2145091577

# APPINSTALLER_CLI_ERROR_PINNED_CERTIFICATE_MISMATCH. Non-transient.
# The sole exit code that overrides state-derived classification (forces
# Failed regardless of post-install state), because the state check cannot
# be trusted when the certificate chain itself is the failure.
$script:PinnedCertMismatchCode = [int]0x8A15005E

# Codes with dedicated handling branches in Invoke-WingetInstallSafe, listed
# here so the classification surface is complete:
#   0x8A15002B  APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
#               Success only if post-install state confirms presence.
#   0x8A150046  APPINSTALLER_CLI_ERROR_SOURCE_AGREEMENTS_NOT_ACCEPTED
#               Explicit failure; no retry, no scope change.

function ConvertTo-WindowsArgument {
    # Quote a single argument per Windows command-line parsing rules.
    param([string]$Arg)
    if ($null -eq $Arg) { return '""' }
    if ($Arg.Length -gt 0 -and $Arg -notmatch '[\s"]') { return $Arg }
    # Escape backslashes before quotes, then trailing backslashes.
    $escaped = [regex]::Replace($Arg, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Join-WindowsArguments {
    param([string[]]$Arguments)
    if (-not $Arguments -or $Arguments.Count -eq 0) { return '' }
    return ($Arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
}

function Get-WingetExePath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $installer = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($installer) {
        $exe = Join-Path $installer.InstallLocation 'winget.exe'
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

function Get-WingetBypassSetting {
    $exe = Get-WingetExePath
    if (-not $exe -or -not (Test-Path $exe)) { return $null }

    try {
        # `settings export` writes JSON to stdout. `-o` belongs to `winget export`
        # (package list) and is invalid here. Discard stderr so warnings cannot
        # contaminate the JSON stream.
        $output = & $exe settings export 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) { return $null }

        $json = ($output -join "`n")
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop
        if (-not $settings.adminSettings) { return $null }

        $prop = $settings.adminSettings.PSObject.Properties['BypassCertificatePinningForMicrosoftStore']
        if (-not $prop) { return $null }
        return [bool]$prop.Value
    }
    catch { return $null }
}

function Invoke-WingetAdminCommand {
    param(
        [Parameter(Mandatory)] [string[]]$Arguments,
        [int]$TimeoutSeconds = 60
    )

    try {
        $exe = Get-WingetExePath
        if (-not $exe -or -not (Test-Path $exe)) { return $false }

        $quoted = Join-WindowsArguments -Arguments $Arguments
        $proc = Start-Process -FilePath $exe -ArgumentList $quoted -PassThru -WindowStyle Hidden -ErrorAction Stop
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch {}
            # See Invoke-WingetProcess for the reason $null = is required.
            try { $null = $proc.WaitForExit(5000) } catch {}
            return $false
        }
        return ($proc.ExitCode -eq 0)
    }
    catch { return $false }
}

function Invoke-WingetProcess {
    param(
        [Parameter(Mandatory)] [string[]]$Arguments,
        [int]$TimeoutSeconds = 900
    )

    $exe = Get-WingetExePath
    if (-not $exe -or -not (Test-Path $exe)) {
        return @{ ExitCode = $null; TimedOut = $false; NotFound = $true; StdOut = $null; StdErr = 'winget.exe not found' }
    }

    $quoted = Join-WindowsArguments -Arguments $Arguments

    # Use System.Diagnostics.Process directly. Windows PowerShell 5.1's
    # Start-Process -PassThru, when combined with -RedirectStandardOutput or
    # -RedirectStandardError, returns a Process object whose ExitCode is not
    # reliably populated after WaitForExit. stdout and stderr are captured
    # fine, but the exit code is lost, which makes every winget call appear
    # to fail silently with a null exit code. Creating the Process object
    # directly and using Start() gives reliable ExitCode, stdout, and stderr.
    #
    # UseShellExecute = $false is required for stream redirection. This does
    # NOT block WindowsApps App Execution Alias activation on Windows 10/11;
    # the alias activates normally under this mode.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe
    $psi.Arguments              = $quoted
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    # Read stdout/stderr as UTF-8 explicitly. Winget emits UTF-8 on every
    # platform, but ProcessStartInfo defaults to the system's active
    # codepage when StandardOutputEncoding is unset. On a CJK-codepage
    # machine (CP949, CP936, CP932, CP950), winget's braille spinner
    # frames and any non-ASCII message text get decoded into garbage
    # characters — the '풉칱칡...' pattern observed on the ThinkCentre
    # 2026-09-19 run is the CP949 mapping of the spinner bytes. On a
    # single-byte codepage (CP850, CP437), the same bytes produce '┬⌐'
    # and similar. Both are the same defect: mis-decoded UTF-8. Setting
    # StandardOutputEncoding to UTF-8 eliminates it at the source.
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        $proc.Start() | Out-Null
    }
    catch {
        return @{ ExitCode = $null; TimedOut = $false; NotFound = $false; StdOut = $null; StdErr = $_.Exception.Message }
    }

    # Read both streams asynchronously while waiting. If we waited first and
    # then read, a process that fills its stdout pipe buffer would deadlock.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

    if (-not $exited) {
        try { $proc.Kill() } catch {}
        # Assign to $null: WaitForExit(int) returns [bool] and would emit it
        # to the pipeline, causing this function to return @($bool, $hashtable)
        # instead of just the hashtable. The caller binds to [hashtable] and
        # throws on an Object[] argument, aborting the whole phase.
        try { $null = $proc.WaitForExit(5000) } catch {}
        # Capture whatever the process emitted before it was killed. The
        # async read tasks were started before the wait; once the process
        # has exited, both complete with the buffered content. Diagnostic
        # only — the caller still classifies by post-timeout state — but a
        # winget call that hangs after emitting a warning or partial
        # progress should not lose that context.
        $stdoutAfterKill = $null
        $stderrAfterKill = $null
        try { $stdoutAfterKill = $stdoutTask.Result } catch {}
        try { $stderrAfterKill = $stderrTask.Result } catch {}
        return @{ ExitCode = $null; TimedOut = $true; NotFound = $false; StdOut = $stdoutAfterKill; StdErr = $stderrAfterKill }
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result

    return @{
        ExitCode = $proc.ExitCode
        TimedOut = $false
        NotFound = $false
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Get-WingetLastSegment {
    # Winget writes its progress spinner with bare \r (carriage return, no
    # line feed); each frame overwrites the previous one on a terminal.
    # Captured stdout/stderr preserves the raw \r characters, so a single
    # "line" from a split on \r?\n may contain every spinner frame
    # concatenated with the terminal message. Return only the terminal
    # message — the last non-empty segment after splitting on \r. When a
    # line contains no \r, the entire line is returned unchanged. Returns
    # the empty string when the input is only spinner frames.
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $segments = @($Line -split "`r" | Where-Object { $_.Trim() })
    if ($segments.Count -eq 0) { return '' }
    return $segments[-1].Trim()
}

function Write-WingetProcessOutput {
    # Logs captured stdout/stderr from a winget invocation, with split
    # routing:
    #   - Verbose stdout/stderr lines  -> per-app log only (Write-AppDetailLog)
    #   - One-line outcome summary     -> both logs (Write-DeploymentLog -AppName)
    #
    # This keeps PBR_Deployment.log readable (one line per winget call) while
    # the per-app log carries the full detail needed to diagnose a failure
    # without re-running winget by hand.
    param(
        [Parameter(Mandatory)] [hashtable]$Result,
        [string]$Context = '',
        [string]$AppName = ''
    )

    $prefix = if ($Context) { "${Context}: " } else { '' }

    if ($Result.NotFound) {
        if ($AppName) { Write-AppDetailLog -AppName $AppName -Message "${prefix}winget.exe not found or launch failed" -Level 'ERROR' }
        return
    }
    if ($Result.TimedOut) {
        # Log whatever the process emitted before it was killed. The caller
        # emits the timeout WARN and drives terminal classification by
        # post-timeout state; this block only preserves the diagnostic
        # output for the per-app log.
        if ($AppName) {
            if ($Result.StdErr -and $Result.StdErr.Trim()) {
                foreach ($rawLine in ($Result.StdErr -split "`r?`n")) {
                    $line = Get-WingetLastSegment -Line $rawLine
                    if (-not $line) { continue }
                    Write-AppDetailLog -AppName $AppName -Message "${prefix}stderr (pre-timeout): $line" -Level 'WARN'
                }
            }
            if ($Result.StdOut -and $Result.StdOut.Trim()) {
                foreach ($rawLine in ($Result.StdOut -split "`r?`n")) {
                    $line = Get-WingetLastSegment -Line $rawLine
                    if (-not $line) { continue }
                    Write-AppDetailLog -AppName $AppName -Message "${prefix}stdout (pre-timeout): $line" -Level 'INFO'
                }
            }
        }
        return
    }

    $hasStderr = $Result.StdErr -and $Result.StdErr.Trim()
    $hasStdout = $Result.StdOut -and $Result.StdOut.Trim()

    # Verbose detail -> app log only. Winget's progress spinner is
    # stripped by Get-WingetLastSegment so the per-app log carries only
    # the terminal message from each captured line.
    if ($AppName) {
        if ($hasStderr) {
            foreach ($rawLine in ($Result.StdErr -split "`r?`n")) {
                $line = Get-WingetLastSegment -Line $rawLine
                if (-not $line) { continue }
                Write-AppDetailLog -AppName $AppName -Message "${prefix}stderr: $line" -Level 'WARN'
            }
        }
        if ($hasStdout) {
            foreach ($rawLine in ($Result.StdOut -split "`r?`n")) {
                $line = Get-WingetLastSegment -Line $rawLine
                if (-not $line) { continue }
                Write-AppDetailLog -AppName $AppName -Message "${prefix}stdout: $line" -Level 'INFO'
            }
        }
    }

    # One-line summary -> shared log + app log (via -AppName).
    # Preference order for the summary text:
    #   1. Last non-empty stderr line (usually the human-readable reason)
    #   2. Last non-empty stdout line (winget's own closing statement)
    #   3. Fallback: exit code only
    $summary = $null
    if ($hasStderr) {
        $lastErr = ($Result.StdErr -split "`r?`n" |
            ForEach-Object { Get-WingetLastSegment -Line $_ } |
            Where-Object { $_ } |
            Select-Object -Last 1)
        if ($lastErr) { $summary = "stderr: $lastErr" }
    }
    if (-not $summary -and $hasStdout) {
        $lastOut = ($Result.StdOut -split "`r?`n" |
            ForEach-Object { Get-WingetLastSegment -Line $_ } |
            Where-Object { $_ } |
            Select-Object -Last 1)
        if ($lastOut) { $summary = "stdout: $lastOut" }
    }
    if (-not $summary) { $summary = 'exit code only; no output captured' }

    # Known-benign codes for the one-line summary. 1641/3010 are the
    # standard Windows reboot codes. 0x8A15002B (UPDATE_NOT_APPLICABLE)
    # is winget's standard "no newer version" response when the package
    # is present. 0x8A150109 (INSTALL_REBOOT_REQUIRED_TO_FINISH) is the
    # winget reboot-required success signal. Both are state-verified to
    # a non-Failed classification.
    #
    # Two adjacent codes are deliberately NOT benign, despite state
    # recovery salvaging the deployment:
    #   0x8A150044 (RESTAPI_ENDPOINT_NOT_FOUND) — the source endpoint
    #     itself is unreachable. The msstore source is behaving
    #     abnormally; the framework's state fallback keeps convergence
    #     green, but the operator should see a WARN.
    #   0x8A150014 (NO_APPLICATIONS_FOUND) — winget could not resolve
    #     the requested package ID against the source. May indicate a
    #     stale ID, a source outage, or a regional/entitlement issue;
    #     all are worth visible attention even when state saves the day.
    # Genuine failures remain WARN.
    $summaryLevel = if ($Result.ExitCode -in @(0, 1641, 3010, [int]0x8A15002B, [int]0x8A150109)) { 'INFO' } else { 'WARN' }
    Write-DeploymentLog -Message "${prefix}winget result: $summary" -Level $summaryLevel -AppName $AppName
}

function Write-PinnedCertDiagnostic {
    param(
        [string]$Friendly,
        [psobject]$Context
    )
    $enabledByPbr  = $false
    $baselineValue = 'unknown'
    if ($Context -and $Context.WingetSession) {
        $enabledByPbr  = [bool]$Context.WingetSession.BypassEnabled
        $baselineValue = if ($null -eq $Context.WingetSession.BypassBaseline) { 'unknown' } else { $Context.WingetSession.BypassBaseline }
    }
    $bypassActive = $enabledByPbr -or ($baselineValue -eq $true)
    Write-DeploymentLog -Message "Certificate pinning mismatch (0x8A15005E) for $Friendly; bypass active=$bypassActive (enabled-by-PBR=$enabledByPbr; baseline=$baselineValue)." -Level ERROR
}

function Initialize-WinGetSession {
    param([Parameter(Mandatory)] [psobject]$Context)

    $state = [pscustomobject]@{
        BypassEnabled    = $false
        BypassBaseline   = $null
        NetworkReachable = $null   # $null = unknown; $true/$false = probed
    }

    if ($Context.IsSystem) {
        # SYSTEM phase never invokes winget; nothing to prepare.
        $Context.WingetSession = $state
        return $state
    }

    $baseline = Get-WingetBypassSetting
    $state.BypassBaseline = $baseline

    if ($null -eq $baseline) {
        Write-DeploymentLog -Message 'Could not determine existing WinGet bypass state; leaving administrator setting unchanged.' -Level WARN
    }
    elseif ($baseline -eq $true) {
        Write-DeploymentLog -Message 'WinGet certificate-pinning bypass already enabled; leaving baseline unchanged.' -Level INFO
    }
    else {
        if (Invoke-WingetAdminCommand -Arguments @('settings','--enable','BypassCertificatePinningForMicrosoftStore')) {
            Write-DeploymentLog -Message 'Temporarily enabled WinGet certificate-pinning bypass.' -Level INFO
            $state.BypassEnabled = $true
        }
        else {
            Write-DeploymentLog -Message 'Could not enable WinGet bypass.' -Level WARN
        }
    }

    # Fail-fast on obviously offline hosts. Without this, an offline machine
    # burns the full 180s readiness window before the install loop starts and
    # fails anyway. The check is best-effort; a false negative just means we
    # fall through to the full poll.
    $networkReachable = $null
    try {
        $networkReachable = [bool](Test-NetConnection `
            -ComputerName 'cdn.winget.microsoft.com' `
            -Port 443 `
            -InformationLevel Quiet `
            -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue)
    } catch { }

    $state.NetworkReachable = $networkReachable
    if ($networkReachable -eq $false) {
        Write-DeploymentLog -Message 'No network reachability to winget CDN; skipping 180s readiness poll.' -Level WARN
        $Context.WingetSession = $state
        return $state
    }

    # Readiness poll: winget can take a moment to be ready at first logon,
    # particularly on slow disks or when AppX is still settling. Poll
    # `winget source list` for up to 180s before giving up.
    $ready = $false
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if (Invoke-WingetAdminCommand -Arguments @('source','list') -TimeoutSeconds 30) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 5
    }
    if (-not $ready) {
        Write-DeploymentLog -Message 'WinGet readiness poll timed out after 180s; attempting AppX re-registration repair.' -Level WARN
        # Both monoliths carried this repair because winget can get wedged at
        # logon (stale AppX registration, corrupt source cache). Re-registering
        # the DesktopAppInstaller package re-establishes the winget CLI without
        # requiring a reboot. Failure here is non-fatal; we still proceed and
        # let the install loop observe whether winget works.
        try {
            Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue | Out-Null
            }
        } catch { }
    }

    $Context.WingetSession = $state
    return $state
}

function Restore-WinGetSession {
    param([Parameter(Mandatory)] [psobject]$State)

    if (-not $State.BypassEnabled) { return }

    if (Invoke-WingetAdminCommand -Arguments @('settings','--disable','BypassCertificatePinningForMicrosoftStore')) {
        Write-DeploymentLog -Message 'WinGet certificate-pinning bypass disabled (baseline).' -Level INFO
    }
    else {
        Write-DeploymentLog -Message 'Could not disable WinGet bypass; bypass may remain enabled.' -Level WARN
    }
}

# Install contract: machine-first, source-independent, evidence-driven,
# state-verified.
#
#   - machine-first: attempt --scope machine first regardless of source.
#   - source-independent: winget and msstore follow the same scope policy.
#   - evidence-driven: fallback and retry decisions come from classified
#     evidence, not from failed attempts alone.
#   - state-verified: terminal classification comes from pre/post install
#     state, not from winget's exit code (with the sole 0x8A15005E
#     override).
function Test-WingetPackageInstalled {
    param(
        [Parameter(Mandatory)] [string]$PackageId
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) {
        return $false
    }

    # Route through Invoke-WingetProcess so a hung winget.exe cannot
    # block the caller indefinitely. The 30-second timeout is generous
    # for a single --id --exact query; a real hang is a winget-state
    # problem that the caller should not wait on.
    $result = Invoke-WingetProcess `
        -Arguments @('list','--id',$PackageId,'--exact','--disable-interactivity') `
        -TimeoutSeconds 30

    if ($result.NotFound -or $result.TimedOut) {
        return $false
    }

    $escapedId = [regex]::Escape($PackageId)
    $combined = @()
    if ($result.StdOut) { $combined += ($result.StdOut -split "`r?`n") }
    if ($result.StdErr) { $combined += ($result.StdErr -split "`r?`n") }

    foreach ($line in $combined) {
        if ($line -match "(?i)(?<!\S)$escapedId(?!\S)") {
            return $true
        }
    }

    return $false
}

function Test-WingetInstalledState {
    param(
        [Parameter(Mandatory)] [string]$PackageId,
        [string]$PackageName = '',
        [string]$AppxPackageName = '',
        [string[]]$AlternateAppNames = @()
    )

    # When a WinGet package identity is declared, it is the preferred
    # authoritative state check. AppName/AppX remain fallback identities.
    if (-not [string]::IsNullOrWhiteSpace($PackageId)) {
        if (Test-WingetPackageInstalled -PackageId $PackageId) {
            return $true
        }
    }

    # Exact fallback. This function's answer drives terminal classification
    # inside Invoke-WingetInstallSafe, so fuzzy matching here risks a
    # false-positive rescue: a substring match against a similarly named
    # registration would silently classify the operation as successful
    # while the target app is absent. The failure asymmetry favors
    # strictness -- a false negative (app present but DisplayName does
    # not exactly match) produces a visible FailedApps entry; a false
    # positive produces a silent success. See PHILOSOPHY.md section 5.
    if (Test-ApplicationInstalled `
            -AppName $PackageName `
            -AppxPackageName $AppxPackageName `
            -Exact) {
        return $true
    }

    # AlternateAppNames is the manifest's declared bridge for installers
    # whose uninstall DisplayName legitimately differs from the logical
    # AppName (e.g. "Microsoft .NET Windows Desktop Runtime 8" installs
    # as "Microsoft Windows Desktop Runtime - 8.0.x (x64)"). The
    # framework already consults alternates in Test-AppPresence and in
    # version resolution; this function honors the same contract so a
    # declared alternate rescues a legitimate variant without reopening
    # the fuzzy-match risk.
    foreach ($alt in $AlternateAppNames) {
        if ([string]::IsNullOrWhiteSpace($alt)) { continue }
        if (Test-ApplicationInstalled -AppName $alt -Exact) {
            return $true
        }
    }

    return $false
}

function Invoke-WingetInstallSafe {
    param(
        [Parameter(Mandatory)] [string]$PackageId,
        [string]$PackageName = '',
        [string]$AppxPackageName = '',
        [string[]]$AlternateAppNames = @(),
        [string]$Source = '',
        [Parameter(Mandatory)] [psobject]$Context,
        [switch]$IsPrerequisite
    )

    if ($Context.IsSystem) {
        Write-DeploymentLog -Message "WinGet skipped in SYSTEM context for $PackageId." -Level INFO
        return [pscustomobject]@{
            Attempted = $false; DeploymentSucceeded = $false; Classification = 'NotAttempted'
            ExitCode = $null; FinalScope = ''; Source = $Source
            PreInstalled = $false; PostInstalled = $false
            PreVersion = $null; PostVersion = $null
            TimedOut = $false; NotFound = $false
        }
    }

    $friendly = if ($PackageName) { $PackageName } else { $PackageId }

    if ($Source -eq 'msstore') { $effectiveSource = 'msstore' }
    elseif ($Source -eq 'winget') { $effectiveSource = 'winget' }
    else { $effectiveSource = if ($PackageId -match '^9[A-Za-z0-9]{11,}$') { 'msstore' } else { 'winget' } }

    Write-DeploymentLog -Message "Attempting WinGet: $friendly (source=$effectiveSource)" -Level INFO -AppName $friendly

    $preInstalled = Test-WingetInstalledState `
        -PackageId         $PackageId `
        -PackageName       $PackageName `
        -AppxPackageName   $AppxPackageName `
        -AlternateAppNames $AlternateAppNames

    # The WinGet package identity (PackageId) is what established presence
    # above. Version, however, is resolved against the physical uninstall
    # DisplayName, which can differ materially from the manifest's logical
    # AppName (e.g. AppName='Microsoft .NET Windows Desktop Runtime 8',
    # DisplayName='Microsoft Windows Desktop Runtime - 8.0.31 (x64)').
    # AlternateAppNames is the manifest's declared bridge for this gap.
    # Try the primary AppName first, then each alternate, before giving up.
    $preVersion = if ($preInstalled) {
        $v = Get-ApplicationVersion -AppName $PackageName -AppxPackageName $AppxPackageName
        if (-not $v -and $AlternateAppNames) {
            foreach ($alt in $AlternateAppNames) {
                if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                $v = Get-ApplicationVersion -AppName $alt
                if ($v) { break }
            }
        }
        $v
    }
    else {
        $null
    }

    $timeout = if ($Context.Profile.WinGetTimeoutSeconds) { [int]$Context.Profile.WinGetTimeoutSeconds } else { 600 }

    $attempt = {
        param([string[]]$ScopeArgs)
        $wingetArgs = @(
            'install','--id',$PackageId,'--silent',
            '--accept-package-agreements','--accept-source-agreements',
            '-e','--source',$effectiveSource
        )
        if ($ScopeArgs) { $wingetArgs += $ScopeArgs }
        return Invoke-WingetProcess -Arguments $wingetArgs -TimeoutSeconds $timeout
    }

    $maxRetries = 3
    $finalOutcome = $null
    $finalExitCode = $null
    $finalTimedOut = $false
    $finalNotFound = $false
    $scopeUsed = 'machine'
    $bypassRecoveryAttempted = $false

    for ($i = 1; $i -le $maxRetries; $i++) {
        $result = & $attempt -ScopeArgs @('--scope','machine')

        Write-WingetProcessOutput -Result $result -Context "machine scope attempt $i/$maxRetries" -AppName $PackageName

        if ($result.TimedOut) {
            Write-DeploymentLog -Message "WinGet timed out after ${timeout}s for $friendly; classifying by post-timeout state." -Level WARN -AppName $PackageName
            Clear-ApplicationCaches
            $finalExitCode = $null
            $finalTimedOut = $true
            $stateAfterTimeout = if (Test-WingetInstalledState `
                    -PackageId         $PackageId `
                    -PackageName       $PackageName `
                    -AppxPackageName   $AppxPackageName `
                    -AlternateAppNames $AlternateAppNames) {
                'present'
            }
            else {
                'absent'
            }
            Write-DeploymentLog -Message "WinGet post-timeout state for ${friendly}: $stateAfterTimeout." -Level INFO -AppName $PackageName
            $finalOutcome = if ($stateAfterTimeout -eq 'present') { 'Success' } else { 'Failure' }
            break
        }
        if ($result.NotFound) {
            $finalNotFound = $true
            $finalOutcome = 'Failure'
            $finalExitCode = $null
            break
        }

        $exit = $result.ExitCode

        if ($exit -in $script:WingetSuccessCodes) { $finalOutcome = 'Success'; $finalExitCode = $exit; break }

        if ($exit -eq [int]0x8A15002B) {
            Clear-ApplicationCaches
            if (Test-WingetInstalledState `
                    -PackageId         $PackageId `
                    -PackageName       $PackageName `
                    -AppxPackageName   $AppxPackageName `
                    -AlternateAppNames $AlternateAppNames) {
                $finalOutcome = 'AlreadyCurrent'
                $finalExitCode = $exit
            }
            else {
                $finalOutcome = 'Failure'
                $finalExitCode = $exit
            }
            break
        }

        if ($exit -eq [int]0x8A150046) {
            Write-DeploymentLog -Message "WinGet source agreements were not accepted for $friendly." -Level WARN
            $finalOutcome = 'Failure'; $finalExitCode = $exit
            break
        }

        if ($exit -eq $script:PinnedCertMismatchCode) {
            Write-PinnedCertDiagnostic -Friendly $friendly -Context $Context

            # If the session bypass is not confirmed active, one-shot re-enable
            # and retry the same scope. If it IS confirmed active, retrying
            # with unchanged state is a no-op; fail immediately and let the
            # caller fall back to a local installer.
            $bypassActive = $false
            $baselineKnownDisabled = $false
            if ($Context.WingetSession) {
                $bypassActive = [bool]$Context.WingetSession.BypassEnabled -or
                                ($Context.WingetSession.BypassBaseline -eq $true)
                $baselineKnownDisabled = ($Context.WingetSession.BypassBaseline -eq $false)
            }

            # Only attempt the recovery enable when the baseline is known
            # to have been disabled. If the baseline is unknown ($null), we
            # must not alter administrator configuration: enabling here and
            # then disabling in Restore-WinGetSession would flip a true
            # baseline to false.
            if (-not $bypassActive -and $baselineKnownDisabled -and -not $bypassRecoveryAttempted) {
                $bypassRecoveryAttempted = $true
                if (Invoke-WingetAdminCommand -Arguments @('settings','--enable','BypassCertificatePinningForMicrosoftStore')) {
                    Write-DeploymentLog -Message "WinGet bypass enabled after 0x8A15005E; retrying $friendly." -Level WARN
                    if ($Context.WingetSession) { $Context.WingetSession.BypassEnabled = $true }
                    # Extend the loop budget by one before the `continue`. Without
                    # this, a pinned-cert mismatch that fires on the final retry
                    # slot (i == maxRetries) would increment past the loop bound
                    # and exit without ever exercising the recovery — the WARN
                    # log line would claim a retry that never happened. The
                    # $bypassRecoveryAttempted guard ensures this extension
                    # happens at most once per invocation, so the loop cannot
                    # be extended indefinitely.
                    $maxRetries++
                    continue
                }
                Write-DeploymentLog -Message "WinGet bypass could not be enabled after 0x8A15005E; not retrying." -Level ERROR
            }

            $finalOutcome = 'Failure'; $finalExitCode = $exit
            break
        }

        if ($i -lt $maxRetries -and $exit -in $script:WingetRetryCodes) {
            Write-DeploymentLog -Message "Transient WinGet error $exit - retrying same machine scope ($i/$maxRetries)..." -Level WARN
            Start-Sleep -Seconds (5 * $i)
            continue
        }

        if ($exit -eq $script:MachineScopeIncompatCode) {
            Write-DeploymentLog -Message "Machine-scope incompatibility ($exit) detected; retrying without explicit scope." -Level WARN
            $scopeUsed = 'default'

            for ($j = 1; $j -le $maxRetries; $j++) {
                $result2 = & $attempt -ScopeArgs @()

                Write-WingetProcessOutput -Result $result2 -Context "default scope attempt $j/$maxRetries" -AppName $PackageName

                if ($result2.TimedOut) {
                    Write-DeploymentLog -Message "WinGet timed out after ${timeout}s for $friendly; classifying by post-timeout state." -Level WARN -AppName $PackageName
                    Clear-ApplicationCaches
                    $finalExitCode = $null
                    $finalTimedOut = $true
                    $stateAfterTimeout = if (Test-WingetInstalledState `
                            -PackageId         $PackageId `
                            -PackageName       $PackageName `
                            -AppxPackageName   $AppxPackageName `
                            -AlternateAppNames $AlternateAppNames) {
                        'present'
                    }
                    else {
                        'absent'
                    }
                    Write-DeploymentLog -Message "WinGet post-timeout state for ${friendly}: $stateAfterTimeout." -Level INFO -AppName $PackageName
                    $finalOutcome = if ($stateAfterTimeout -eq 'present') { 'Success' } else { 'Failure' }
                    break
                }
                if ($result2.NotFound) {
                    $finalNotFound = $true
                    $finalOutcome = 'Failure'
                    $finalExitCode = $null
                    break
                }

                $exit2 = $result2.ExitCode
                if ($exit2 -in $script:WingetSuccessCodes) { $finalOutcome = 'Success'; $finalExitCode = $exit2; break }

                if ($exit2 -eq [int]0x8A15002B) {
                    Clear-ApplicationCaches
                    if (Test-WingetInstalledState `
                            -PackageId         $PackageId `
                            -PackageName       $PackageName `
                            -AppxPackageName   $AppxPackageName `
                            -AlternateAppNames $AlternateAppNames) {
                        $finalOutcome = 'AlreadyCurrent'
                        $finalExitCode = $exit2
                    }
                    else {
                        $finalOutcome = 'Failure'
                        $finalExitCode = $exit2
                    }
                    break
                }

                if ($exit2 -eq [int]0x8A150046) { $finalOutcome = 'Failure'; $finalExitCode = $exit2; break }
                if ($exit2 -eq $script:PinnedCertMismatchCode) {
                    Write-PinnedCertDiagnostic -Friendly $friendly -Context $Context
                    $finalOutcome = 'Failure'; $finalExitCode = $exit2
                    break
                }

                if ($j -lt $maxRetries -and $exit2 -in $script:WingetRetryCodes) {
                    Start-Sleep -Seconds (5 * $j)
                    continue
                }

                $finalOutcome = 'Failure'; $finalExitCode = $exit2
                break
            }
            break
        }

        $finalOutcome = 'Failure'; $finalExitCode = $exit
        break
    }

    Clear-ApplicationCaches

    $postInstalled = Test-WingetInstalledState `
        -PackageId         $PackageId `
        -PackageName       $PackageName `
        -AppxPackageName   $AppxPackageName `
        -AlternateAppNames $AlternateAppNames

    $postVersion = if ($postInstalled) {
        $v = Get-ApplicationVersion -AppName $PackageName -AppxPackageName $AppxPackageName
        if (-not $v -and $AlternateAppNames) {
            foreach ($alt in $AlternateAppNames) {
                if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                $v = Get-ApplicationVersion -AppName $alt
                if ($v) { break }
            }
        }
        $v
    }
    else {
        $null
    }

    if ($finalExitCode -in @(1641,3010,[int]0x8A150109)) { $Context.RebootRequired = $true }

    $classification = Get-DeploymentClassification `
        -PreInstalled  $preInstalled `
        -PreVersion    $preVersion `
        -PostInstalled $postInstalled `
        -PostVersion   $postVersion

    if ($finalExitCode -eq $script:PinnedCertMismatchCode -and $classification -ne 'Failed') {
        Write-DeploymentLog -Message "Override: 0x8A15005E; state-derived '$classification' forced to 'Failed'." -Level WARN
        $classification = 'Failed'
    }

    # Diagnostic: log when winget's own verdict disagrees with the state check.
    # $finalOutcome tracks what winget reported (Success/AlreadyCurrent/Failure);
    # $classification is derived from the actual pre/post install state.
    # Divergence is expected and informative — state always wins.
    $winGetClaimedSuccess = ($finalOutcome -eq 'Success' -or $finalOutcome -eq 'AlreadyCurrent')
    $stateShowsSuccess    = ($classification -ne 'Failed')
    if ($winGetClaimedSuccess -ne $stateShowsSuccess) {
        Write-DeploymentLog -Message "WinGet/state divergence for ${friendly}: wingetOutcome=$finalOutcome exit=$finalExitCode scope=$scopeUsed state=$classification." -Level INFO
    }

    $deploymentSucceeded = ($classification -ne 'Failed')

    switch ($classification) {
        'Installed'      { Add-UniqueValue -List $Context.InstalledApps  -Value $PackageName }
        'Updated'        { Add-UniqueValue -List $Context.UpdatedApps    -Value $PackageName }
        'AlreadyCurrent' { Add-UniqueValue -List $Context.AlreadyCurrent -Value $PackageName }
        'Failed'         {
            if ($IsPrerequisite) {
                # Prerequisites are owned by pre.ps1. A failed update/verification
                # pass must not block convergence. Route to SkippedApps instead.
                Add-UniqueValue -List $Context.SkippedApps -Value $PackageName
            } else {
                Add-UniqueValue -List $Context.FailedApps -Value $PackageName
            }
        }
    }

    # Publish reason fields for the phase loop's OUTCOME line.
    if ($Context.AppOutcomes) {
        $terminalReason = switch -Regex ($classification) {
            '^Installed'      { 'WinGetInstalled' }
            '^Updated'        { 'WinGetUpdated' }
            '^AlreadyCurrent' { 'WinGetAlreadyCurrent' }
            '^Failed' {
                if ($finalTimedOut)                                      { 'WinGetTimeout' }
                elseif ($finalExitCode -eq [int]0x8A15005E)              { 'CertificatePinMismatch' }
                elseif ($finalExitCode -eq [int]0x8A150046)              { 'SourceAgreementsNotAccepted' }
                elseif ($finalExitCode -eq $script:MachineScopeIncompatCode) { 'MachineScopeUnsupported' }
                else                                                     { "WinGetFailed:$finalExitCode" }
            }
            default           { 'WinGetUnknown' }
        }

        $Context.AppOutcomes[$PackageName] = @{
            TerminalReason    = $terminalReason
            InitialMethod     = 'WinGet'
            PreVersion        = [string]$preVersion
            PostVersion       = [string]$postVersion
            WinGetSource      = $effectiveSource
            WinGetExitCode    = [string]$finalExitCode
        }
    }

    return [pscustomobject]@{
        Attempted           = $true
        DeploymentSucceeded = $deploymentSucceeded
        Classification      = $classification
        ExitCode            = $finalExitCode
        FinalScope          = $scopeUsed
        Source              = $effectiveSource
        PreInstalled        = $preInstalled
        PostInstalled       = $postInstalled
        PreVersion          = $preVersion
        PostVersion         = $postVersion
        TimedOut            = $finalTimedOut
        NotFound            = $finalNotFound
    }
}

Export-ModuleMember -Function `
    Get-WingetExePath, `
    Get-WingetBypassSetting, `
    Invoke-WingetAdminCommand, `
    Invoke-WingetProcess, `
    Initialize-WinGetSession, `
    Restore-WinGetSession, `
    Invoke-WingetInstallSafe, `
    Test-WingetPackageInstalled, `
    Write-PinnedCertDiagnostic, `
    Write-WingetProcessOutput
