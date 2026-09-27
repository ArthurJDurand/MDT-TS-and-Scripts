<#
.SYNOPSIS
    Vendor-neutral logging: rolling file, transcript, Windows Event Log.

.DESCRIPTION
    Log directory and Event Log source name are supplied by the caller
    (typically the OEM profile) so this module stays brand-free.
#>

function Write-Utf8NoBomAppend {
    # Append one line to a log file as UTF-8 without a BOM.
    #
    # Windows PowerShell 5.1's `Out-File -Encoding UTF8` emits a BOM on
    # file creation, which renders as garbage in viewers that do not
    # strip it — the same three bytes (EF BB BF) appear as "п»ҝ" when
    # decoded as CP1252 and as "容쯑" when decoded as CP936, so the first
    # line of every per-app log looks corrupted under at least one
    # viewer. System.IO.File::AppendAllText with a UTF8Encoding($false)
    # instance writes UTF-8 without BOM and creates the file if absent,
    # matching the semantics we need for both the shared log and the
    # per-app log. Failure to write is swallowed, matching the prior
    # Out-File behavior wrapped in try/catch.
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = $Content + [Environment]::NewLine
    try {
        [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
    } catch {}
}

function Initialize-FrameworkLogging {
    param(
        [Parameter(Mandatory)] [string]$LogDirectory,
        [Parameter(Mandatory)] [string]$EventSourceName,
        [string]$ContextLabel = 'Deployment'
    )

    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $script:FrameworkLogDirectory = $LogDirectory
    $script:FrameworkEventSource  = $EventSourceName
    $script:FrameworkLogFile      = Join-Path $LogDirectory 'PBR_Deployment.log'

    $transcriptPath = Join-Path $LogDirectory ("Master_{0}_{1}_{2}.log" -f `
        $ContextLabel, $PID, (Get-Date -Format 'yyyyMMdd_HHmmss_ffff'))
    $script:FrameworkTranscriptPath = $transcriptPath
    try { Start-Transcript -Path $transcriptPath -Append -Force -ErrorAction SilentlyContinue | Out-Null } catch {}

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSourceName)) {
            New-EventLog -LogName Application -Source $EventSourceName -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Write-DeploymentLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO',
        [string]$AppName = ''
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $entry = "[$timestamp] [$Level] $Message"

    if ($script:FrameworkLogFile) {
        Write-Utf8NoBomAppend -Path $script:FrameworkLogFile -Content $entry
    }

    # Per-app log: when -AppName is supplied, mirror the entry to
    # <AppName>.log in the same directory so operators can inspect one
    # app's history without grepping the shared PBR_Deployment.log.
    # Filename sanitization replaces characters that are illegal in
    # Windows filenames with underscores.
    if (-not [string]::IsNullOrWhiteSpace($AppName) -and $script:FrameworkLogDirectory) {
        $safeName  = ($AppName -replace '[\\/:*?"<>|]', '_')
        $appLogPath = Join-Path $script:FrameworkLogDirectory "$safeName.log"
        Write-Utf8NoBomAppend -Path $appLogPath -Content $entry
    }

    if ($script:FrameworkEventSource) {
        try {
            $eventType = switch ($Level) {
                'ERROR' { [System.Diagnostics.EventLogEntryType]::Error }
                'WARN'  { [System.Diagnostics.EventLogEntryType]::Warning }
                default { [System.Diagnostics.EventLogEntryType]::Information }
            }
            Write-EventLog -LogName Application -Source $script:FrameworkEventSource `
                -EntryType $eventType -EventId 1000 -Message $Message -ErrorAction SilentlyContinue
        } catch {}
    }

    $color  = switch ($Level) { 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    $prefix = switch ($Level) { 'WARN' { '[WARNING] ' } 'ERROR' { '[ERROR] ' } default { '' } }
    Write-Host "  $prefix$Message" -ForegroundColor $color
}

function Write-AppDetailLog {
    # Writes a message only to the per-app log, bypassing the shared
    # PBR_Deployment.log, the Windows Event Log, and the console (and
    # therefore the transcript). Use for verbose content — winget's
    # stdout/stderr, installer output, etc. — that belongs with the app
    # but would drown out the shared log's narrative.
    param(
        [Parameter(Mandatory)] [string]$AppName,
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($AppName) -or -not $script:FrameworkLogDirectory) { return }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $entry = "[$timestamp] [$Level] $Message"
    $safeName = ($AppName -replace '[\\/:*?"<>|]', '_')
    $appLogPath = Join-Path $script:FrameworkLogDirectory "$safeName.log"
    Write-Utf8NoBomAppend -Path $appLogPath -Content $entry
}

function Format-ExitCode {
    # Normalizes an exit code string for human display.
    #
    # Accepts whatever the framework currently hands the emitter:
    #   - Signed decimal ints like -1978335189 (winget on Windows)
    #   - Positive small ints like 0, 2, 3010, 1641 (local installers)
    #   - Hex strings like 0x8A15005E (already-formatted)
    #
    # Returns lowercase hex for anything that reads as a 32-bit code
    # above the small-integer range (so winget codes round-trip as
    # 0x8a15002b, 0x8a150109, etc.), and plain decimal for small
    # codes (0, 2, 3010, 1641) so local-installer codes stay readable.
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) { return '' }
    $s = $Code.Trim()

    if ($s -match '^0x') { return $s.ToLower() }

    if ($s -match '^-?\d+$') {
        try {
            $n = [int64]$s
            if ($n -lt 0) { $n = $n + 4294967296 }
            if ($n -ge 0x80000000) { return '0x' + $n.ToString('X8').ToLower() }
            return $n.ToString()
        } catch { return $s }
    }
    return $s
}

function Convert-OutcomeReasonToNarrative {
    # Maps the framework's internal TerminalReason / SkipReason tokens
    # into a short, human-readable phrase for the OUTCOME line. Only
    # consulted when Class is Failed.
    param(
        [string]$TerminalReason = '',
        [string]$SkipReason     = ''
    )

    $key = if ($TerminalReason) { $TerminalReason } else { $SkipReason }
    if ([string]::IsNullOrWhiteSpace($key)) { return '' }

    switch -Regex ($key) {
        '^WinGetTimeout$'                { return 'timeout' }
        '^CertificatePinMismatch$'       { return 'certificate pin mismatch' }
        '^SourceAgreementsNotAccepted$'  { return 'source agreements not accepted' }
        '^MachineScopeUnsupported$'      { return 'machine scope unsupported' }
        '^WinGetFailed:'                 { return 'winget failure' }
        '^LocalInstallFailed$'           { return 'install failed' }
        '^InstallerMissing$'             { return 'installer missing' }
        '^CustomInstallerFailed$'        { return 'custom installer failure' }
        '^CustomInstallerNotRegistered$' { return 'custom installer not registered' }
        '^ConflictPresent$'              { return 'conflict with another app' }
        '^PrereqMissing$'                { return 'prerequisite missing' }
        '^ServiceNotReady$'              { return 'service not ready' }
        default                          { return $key }
    }
}

function Write-AppOutcome {
    # Emits one human-readable OUTCOME line to the per-app log at the
    # terminal end of an app's processing in a phase.
    #
    # Line format:
    #   OUTCOME: <AppName> — <Class> (<parts>)
    #
    # Where <parts> is a comma-separated list of the details that
    # matter, in this order:
    #
    #   <version-part>       Installed/AlreadyCurrent: the version.
    #                        Updated: "old -> new".
    #                        Failed: omitted.
    #
    #   via <method-part>    local installer <file> | custom installer <name>
    #                        winget | msstore winget | presence short-circuit
    #                        | already present
    #
    #   reboot required / reboot initiated
    #                        Shown when the exit code is a Windows or
    #                        winget reboot-required signal.
    #
    #   exit <code>          Shown only when the code is not a
    #                        well-known benign value. On a rescue path
    #                        where winget was attempted and a local
    #                        installer subsequently ran, the codes are
    #                        labeled "winget exit <code>" and "local
    #                        exit <code>" so the operator can attribute
    #                        each to its origin.
    #
    #   <reason>             Failed only. Short human phrase derived
    #                        from TerminalReason / SkipReason.
    #
    # No key=value. No scope/source trailer. The winget source is
    # carried in the method part; the retry trace is in the narrative
    # lines above.
    param(
        [Parameter(Mandatory)] [string]$AppName,
        [Parameter(Mandatory)] [string]$Classification,
        [string]$TerminalReason    = '',
        [string]$SkipReason        = '',
        [string]$InitialMethod     = '',
        [string]$PreVersion        = '',
        [string]$PostVersion       = '',
        [string]$WinGetSource      = '',
        [string]$WinGetExitCode    = '',
        [string]$LocalInstaller    = '',
        [string]$LocalExitCode     = ''
    )

    if ([string]::IsNullOrWhiteSpace($AppName) -or -not $script:FrameworkLogDirectory) { return }

    # --- Class label
    $classLabel = switch ($Classification) {
        'Installed'      { 'Installed' }
        'Updated'        { 'Updated' }
        'AlreadyCurrent' { 'Already current' }
        'Failed'         { 'Failed' }
        default          { [string]$Classification }
    }

    $isFailure = ($Classification -eq 'Failed')

    # --- Version part
    $versionPart = ''
    if ($Classification -eq 'Updated' -and $PreVersion -and $PostVersion -and ($PreVersion -ne $PostVersion)) {
        $versionPart = "$PreVersion -> $PostVersion"
    }
    elseif ($Classification -in @('Installed','AlreadyCurrent') -and $PostVersion) {
        $versionPart = $PostVersion
    }
    elseif ($Classification -eq 'Updated' -and $PostVersion) {
        $versionPart = $PostVersion
    }
    elseif ($isFailure -and $PreVersion) {
        # Failure on an app that was present: note the version we saw,
        # so the operator knows which state the failure interrupted.
        $versionPart = "was $PreVersion"
    }

    # --- Method part
    $methodPart = ''
    switch ($InitialMethod) {
        'WinGet' {
            $methodPart = if ($WinGetSource -eq 'msstore') { 'msstore winget' } else { 'winget' }
        }
        'Local' {
            $isCustom = ($TerminalReason -match '^CustomInstaller')
            if ($LocalInstaller) {
                if ($isCustom) { $methodPart = "custom installer $LocalInstaller" }
                else           { $methodPart = "local installer $LocalInstaller" }
            } else {
                $methodPart = if ($isCustom) { 'custom installer' } else { 'local installer' }
            }
        }
        'AlreadyInstalled' {
            if ($TerminalReason -eq 'PresenceShortCircuit') { $methodPart = 'presence short-circuit' }
            else                                             { $methodPart = 'already present' }
        }
        default {
            if ($TerminalReason -eq 'PresenceShortCircuit') { $methodPart = 'presence short-circuit' }
        }
    }

    # --- Exit-code handling with source provenance.
    #
    # A code is shown when it is present, non-zero, not a reboot-required
    # signal (surfaced separately in the reboot part), and not a
    # well-known benign winget success (0x8A15002B is what every
    # succeeded-but-already-current winget call returns).
    #
    # When only one source's code is shown, the method part already
    # identifies the source ("via winget" or "via local installer X"), so
    # the code is emitted as plain "exit <code>".
    #
    # When both sources produced a diagnostic code — the rescue path
    # where winget failed and a local installer ran — the codes are
    # labeled "winget exit <code>" and "local exit <code>" so the reader
    # can attribute each to its origin without ambiguity. The rescue
    # path is precisely the case where the method part alone cannot
    # disambiguate: method shows "local installer X" but the diagnostic
    # winget code still needs to be visible.
    $rebootPart = ''
    $exitPart   = ''

    $wgNorm = Format-ExitCode $WinGetExitCode
    $lcNorm = Format-ExitCode $LocalExitCode

    $rebootCodes = @('3010','1641','0x8a150109')
    $benignWingetSuccess = @('0','0x8a15002b')

    if ($wgNorm -in $rebootCodes) {
        $rebootPart = if ($wgNorm -eq '1641') { 'reboot initiated' } else { 'reboot required' }
    }
    elseif ($lcNorm -in @('3010','1641')) {
        $rebootPart = if ($lcNorm -eq '1641') { 'reboot initiated' } else { 'reboot required' }
    }

    $wgInteresting = ($wgNorm -and $wgNorm -ne '0' -and $wgNorm -notin $rebootCodes -and $wgNorm -notin $benignWingetSuccess)
    $lcInteresting = ($lcNorm -and $lcNorm -ne '0' -and $lcNorm -notin @('3010','1641'))

    if ($wgInteresting -and $lcInteresting) {
        $exitPart = "winget exit $wgNorm, local exit $lcNorm"
    }
    elseif ($wgInteresting) {
        $exitPart = if ($InitialMethod -eq 'WinGet') { "exit $wgNorm" } else { "winget exit $wgNorm" }
    }
    elseif ($lcInteresting) {
        $exitPart = if ($InitialMethod -eq 'Local') { "exit $lcNorm" } else { "local exit $lcNorm" }
    }

    # --- Reason part (Failed only)
    $reasonPart = ''
    if ($isFailure) {
        $reasonPart = Convert-OutcomeReasonToNarrative -TerminalReason $TerminalReason -SkipReason $SkipReason
    }

    # --- Assemble
    $parts = @()
    if ($versionPart) { $parts += $versionPart }
    if ($methodPart)  { $parts += "via $methodPart" }
    if ($rebootPart)  { $parts += $rebootPart }
    if ($exitPart)    { $parts += $exitPart }
    if ($reasonPart)  { $parts += $reasonPart }

    $detail = if ($parts.Count -gt 0) { ' (' + ($parts -join ', ') + ')' } else { '' }
    $line   = "OUTCOME: $AppName — $classLabel$detail"

    $timestamp  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $entry      = "[$timestamp] [INFO] $line"
    $safeName   = ($AppName -replace '[\\/:*?"<>|]', '_')
    $appLogPath = Join-Path $script:FrameworkLogDirectory "$safeName.log"
    Write-Utf8NoBomAppend -Path $appLogPath -Content $entry
}

function Complete-FrameworkLogging {
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    Compress-FrameworkLogs
}

function Compress-FrameworkLogs {
    if (-not $script:FrameworkLogDirectory) { return }
    if (-not (Test-Path $script:FrameworkLogDirectory)) { return }

    $cutoff = (Get-Date).AddHours(-1)
    $logs = Get-ChildItem -Path $script:FrameworkLogDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $script:FrameworkTranscriptPath -and
            $_.LastWriteTime -lt $cutoff
        }

    if ($logs.Count -le 10) { return }

    $archive = Join-Path $script:FrameworkLogDirectory ("Archive_{0}.zip" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        Compress-Archive -Path $logs.FullName -DestinationPath $archive -Force -ErrorAction Stop
        $logs | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-DeploymentLog -Message "Archived old logs to $archive" -Level INFO
    } catch {
        Write-DeploymentLog -Message "Failed to archive logs: $($_.Exception.Message)" -Level WARN
    }
}

Export-ModuleMember -Function Initialize-FrameworkLogging, Write-DeploymentLog, Write-AppDetailLog, Write-AppOutcome, Complete-FrameworkLogging, Compress-FrameworkLogs
