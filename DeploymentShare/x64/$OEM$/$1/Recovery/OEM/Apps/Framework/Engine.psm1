<#
.SYNOPSIS
    Vendor-neutral deployment engine.

.DESCRIPTION
    OEM contract: Get-OEMProfile -Name <brand> returns an object with
    data fields and optional scriptblock hooks. See the header of the
    OEM modules (OEM/OEM.*.psm1) for the full contract.

    Hook helpers live in State.psm1:
      Invoke-ProfileHook      returns $null when the hook is missing.
      Invoke-ProfileBoolHook  returns $true when the hook is missing.

    Stage machine:
      - NONE         : no phase complete
      - SYSTEM_DONE  : SYSTEM phase converged; USER phase must still run
      - USER_DONE    : USER phase converged; terminal for normal framework
                       invocations. It does not prove SYSTEM phase
                       converged: phase ordering is permissive, so SYSTEM
                       may have failed or never run. This single marker does
                       not preserve complete per-phase history.
      - With -Force, stage-based early exits are bypassed.

    Install policy:
      - Deployment is designed for a clean Windows installation. Local
        installers are install-if-absent; they never upgrade.
      - SYSTEM phase: if the app is already present, it is recorded as
        AlreadyCurrent and the local installer is not run.
      - USER phase: winget is attempted whenever the app declares a
        WingetAppId, regardless of presence, so a stale install is
        updated. If the app has no WingetAppId, the presence
        short-circuit applies as in SYSTEM.
      - Terminal classification is presence-derived: Installed, Updated,
        or AlreadyCurrent. Version comparison distinguishes Updated from
        AlreadyCurrent.
      - Do not add an upgrade path. Local installers are install-if-absent
        only. The 0x8A15005E override is the sole case where a generic local
        installer can be invoked on a present app, and only because the state
        check cannot be trusted; the affected installers are idempotent
        re-installs, not upgrades. Dedicated installers (HPSA, Diagnostics
        Windows) perform their own early-presence check and always short-
        circuit on presence.
      - Note on non-AppX presence: the framework's phase-level presence
        short-circuit consults the profile's TestAppPresence hook when one
        is supplied. A module can define presence for an app by any means
        it chooses — a registry marker, a file, a shortcut — and the
        framework will honor that definition at phase level, in the health
        check, and in the local-installer pre-check. A hook may also
        decline specific apps by returning $null; the framework then
        continues to its identity precedence chain
        (WingetAppId -> AppxPackageName / AppName -> AlternateAppNames).
        If the hook is absent entirely, the same precedence chain applies
        without the module-defined presence step. See OEM.HP.psm1 and
        OEM.Acer.psm1 for the pattern in use today.
#>

# Fleet-wide prerequisite packages. Attempted in every USER phase via winget
# after Initialize-WinGetSession. pre.ps1 owns local provisioning; this is an
# update/verification pass. Failures are recorded as SkippedApps (via the
# -IsPrerequisite switch on Invoke-WingetInstallSafe) and do not block
# USER_DONE. The list is universal across OEMs and lives here, not in the
# per-brand profiles.
$script:DefaultGlobalPrerequisites = @(
    @{ Id = 'AnyDesk.AnyDesk'; Source = 'winget' }
    @{ Id = '7zip.7zip';       Source = 'winget' }
    @{ Id = 'RARLab.WinRAR';   Source = 'winget' }
    @{ Id = '9MVZQVXJBQ9V';    Source = 'msstore' }
    @{ Id = '9PMMSR1CGPWG';    Source = 'msstore' }
    @{ Id = '9N4WGH0Z6VHQ';    Source = 'msstore' }
    @{ Id = '9N95Q1ZZPMH4';    Source = 'msstore' }
    @{ Id = '9NCTDW2W1BH8';    Source = 'msstore' }
    @{ Id = '9N4D0MSMP0PT';    Source = 'msstore' }
    @{ Id = '9N5TDP8VCMHS';    Source = 'msstore' }
    @{ Id = '9PG2DK419DRG';    Source = 'msstore' }
)

function Start-OEMDeployment {
    param(
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [string]$ManifestPath,
        [Parameter(Mandatory)] [string]$ScriptRoot,
        [Parameter(Mandatory)] [string]$ScriptPath,
        [switch]$Force
    )

    # Profile preflight. Enforce all six required properties from
    # OEM-CONTRACT.md §2 before any phase logic runs. A missing
    # MarkerRegistryPath, for example, would cause Get-DeploymentStage to
    # return 'NONE' silently — Test-Path $null is $false — and the
    # deployment would proceed with no marker bookkeeping. A missing
    # ResumeTaskName could let SYSTEM phase record SYSTEM_DONE without a
    # mechanism to reach USER phase.
    foreach ($property in @('Name','ManifestFile','MarkerRegistryPath','ResumeTaskName','LogDirectory','EventSourceName')) {
        if ([string]::IsNullOrWhiteSpace([string]$Profile.$property)) {
            throw "OEM profile '$($Profile.Name)' is missing required property '$property'."
        }
    }

    # pbr.ps1 selects the manifest from the OEM token. Keep the profile's
    # declared manifest in lockstep with that selected path so a profile
    # cannot pass validation while describing a different manifest.
    $selectedManifestFile = Split-Path -Path $ManifestPath -Leaf
    if ($Profile.ManifestFile -ine $selectedManifestFile) {
        throw "OEM profile '$($Profile.Name)' declares ManifestFile '$($Profile.ManifestFile)', but the deployment was invoked with '$selectedManifestFile'."
    }

    $manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

    # Structural preflight. Rejects per-app defects that would otherwise
    # produce a silent no-op for that app: an app missing its install
    # method, an app whose phase/method combination is never attempted, a
    # malformed pin, an unregistered custom installer. Not a schema
    # validator; a small set of checks for the obviously wrong. An
    # entirely empty apps array is legal and is not rejected here — see
    # MANIFEST-SCHEMA.md §1 and the Gigabyte/Proline manifests.
    if (-not $manifest.PSObject.Properties['apps']) {
        throw "Manifest is missing the required 'apps' property: $ManifestPath"
    }
    $seenAppNames = @{}
    foreach ($app in @($manifest.apps)) {
        if ([string]::IsNullOrWhiteSpace([string]$app.AppName)) {
            throw "Manifest app missing required 'AppName' in $ManifestPath"
        }
        if ($seenAppNames.ContainsKey([string]$app.AppName)) {
            throw "Manifest contains duplicate AppName '$($app.AppName)' in $ManifestPath. AppName must be unique within manifest.apps; the phase loops, the AppOutcomes scratch pad, and the success/failure buckets all key on AppName."
        }
        $seenAppNames[[string]$app.AppName] = $true
        $ip = [string]$app.InstallPhase
        if ($ip -and $ip -notin @('Any','SystemOnly','UserOnly')) {
            throw "Invalid InstallPhase '$ip' for app '$($app.AppName)' in $ManifestPath"
        }
        if ($ip -eq 'SystemOnly' -and $app.RequiresInteractive) {
            throw "Manifest app '$($app.AppName)' declares InstallPhase 'SystemOnly' with RequiresInteractive true in $ManifestPath. This combination is attempted in neither phase: SYSTEM skips interactive apps and USER skips SystemOnly apps. Change InstallPhase to 'UserOnly' or set RequiresInteractive to false."
        }
        if ($ip -eq 'SystemOnly') {
            $hasSystemMethod = `
                -not [string]::IsNullOrWhiteSpace([string]$app.CustomInstaller) -or `
                -not [string]::IsNullOrWhiteSpace([string]$app.InstallerPath) -or `
                ($app.InstallerCandidates -and @($app.InstallerCandidates).Count -gt 0)
            if (-not $hasSystemMethod) {
                throw "Manifest app '$($app.AppName)' declares InstallPhase 'SystemOnly' but has no System-capable install method in $ManifestPath. Winget runs only in USER phase, so a WingetAppId alone cannot satisfy a SystemOnly app: the app would be deferred in SYSTEM and skipped in USER, and would never install. Add a CustomInstaller, InstallerPath, or InstallerCandidates, or change InstallPhase to 'Any'."
            }
        }
        if ($app.Pinning) {
            if ([string]::IsNullOrWhiteSpace([string]$app.Pinning.Type)) {
                throw "Manifest app '$($app.AppName)' declares Pinning without Pinning.Type in $ManifestPath. Set Pinning to null, or supply Type 'AUMID' or 'Desktop'."
            }
            if ($app.Pinning.Type -notin @('AUMID','Desktop')) {
                throw "Invalid Pinning.Type '$($app.Pinning.Type)' for app '$($app.AppName)' in $ManifestPath"
            }
            if ([string]::IsNullOrWhiteSpace([string]$app.Pinning.Id)) {
                throw "Manifest app '$($app.AppName)' declares Pinning.Type '$($app.Pinning.Type)' but no Pinning.Id in $ManifestPath"
            }
            if ($app.Pinning.PSObject.Properties['PinPriority'] -and $null -ne $app.Pinning.PinPriority) {
                $pp = $app.Pinning.PinPriority
                if ($pp -isnot [int] -and $pp -isnot [long]) {
                    throw "Manifest app '$($app.AppName)' declares PinPriority '$pp' which is not an integer in $ManifestPath"
                }
                if ([long]$pp -lt 0) {
                    throw "Manifest app '$($app.AppName)' declares negative PinPriority '$pp' in $ManifestPath"
                }
            }
        }
        if ($app.CustomInstaller) {
            $customMap = $Profile.CustomInstallers
            if (-not $customMap -or -not $customMap.ContainsKey([string]$app.CustomInstaller)) {
                throw "Manifest app '$($app.AppName)' declares CustomInstaller '$($app.CustomInstaller)' which is not registered in profile CustomInstallers for '$($Profile.Name)'."
            }
            if (-not $app.PSObject.Properties['InstallerArgs']) {
                throw "Manifest app '$($app.AppName)' declares CustomInstaller '$($app.CustomInstaller)' but has no InstallerArgs. Custom installers require the field to be present (use empty string for 'no arguments') so the manifest remains the single source of truth for installer arguments."
            }
        }

        # Every app must declare at least one install method, or the phase
        # loop will fail it at install time. Better to reject the manifest
        # before any phase work begins.
        $hasMethod = `
            -not [string]::IsNullOrWhiteSpace([string]$app.WingetAppId) -or `
            -not [string]::IsNullOrWhiteSpace([string]$app.CustomInstaller) -or `
            -not [string]::IsNullOrWhiteSpace([string]$app.InstallerPath) -or `
            ($app.InstallerCandidates -and @($app.InstallerCandidates).Count -gt 0)
        if (-not $hasMethod) {
            throw "Manifest app '$($app.AppName)' declares no install method (WingetAppId, CustomInstaller, InstallerPath, or InstallerCandidates) in $ManifestPath"
        }
    }

    $context = New-DeploymentContext -Profile $Profile -Manifest $manifest
    $context.ScriptPath = $ScriptPath

    $mutexInfo = New-DeploymentMutex -Name 'Global\OEMFramework'
    if (-not $mutexInfo.Owned) {
        Write-Host 'Another OEM framework deployment is already running. Exiting.' -ForegroundColor Yellow
        if ($mutexInfo.Mutex) { try { $mutexInfo.Mutex.Dispose() } catch {} }
        return
    }

    try {
        Initialize-FrameworkLogging `
            -LogDirectory    $Profile.LogDirectory `
            -EventSourceName $Profile.EventSourceName `
            -ContextLabel    (Get-CurrentExecutionPhase)

        $modelString = Get-SystemModel
        if (-not $modelString) { $modelString = '(unknown)' }
        Write-DeploymentLog -Message "OEM=$($Profile.Name) Framework=$ScriptRoot Force=$Force Model=$modelString" -Level INFO

        $bannerOs = Get-FrameworkOSInfo
        Write-Host ''
        Write-Host ('=' * 50) -ForegroundColor Yellow
        Write-Host "$($Profile.Name) Post-Install Automation" -ForegroundColor Yellow
        Write-Host "OS Version:     $bannerOs" -ForegroundColor Cyan
        Write-Host "System Model:   $modelString" -ForegroundColor Magenta
        if ($Force) { Write-Host "Mode:           FORCE (stage-based early exits bypassed)" -ForegroundColor Magenta }
        Write-Host ('=' * 50) -ForegroundColor Yellow
        Write-Host ''

        # No New-Item: the marker key is created as a side effect of the
        # first reg.exe ADD inside Set-RegistryValueSilent. If no phase
        # ever writes, Get-DeploymentStage returns 'NONE' via its own
        # Test-Path guard, which is the correct result for "no phase has
        # converged" anyway.

        $phase = Get-CurrentExecutionPhase
        $stage = Get-DeploymentStage -MarkerPath $context.MarkerPath -ValueName $context.StageName
        Write-DeploymentLog -Message "Stage=$stage Phase=$phase" -Level INFO

        if ($env:USERNAME -match 'defaultuser0') {
            Write-DeploymentLog -Message 'defaultuser0 context intercepted; deferring to next real user logon.' -Level INFO
            $taskName = $Profile.ResumeTaskName
            if ($taskName -and $context.ScriptPath) {
                if (-not (Test-ResumeTask -TaskName $taskName -ScriptPath $context.ScriptPath)) {
                    Write-DeploymentLog -Message "Resume task '$taskName' missing or invalid; re-arming." -Level WARN
                    $rearm = Invoke-ProfileHook -Profile $Profile -HookName 'RegisterResumeTask' -Parameters @{ Name = $taskName; ScriptPath = $context.ScriptPath }
                    if ($null -eq $rearm) {
                        # Default path: no profile hook. The framework's own
                        # Register-ResumeTask returns a bool; inspect it and
                        # log on failure, matching the hook path below and
                        # matching how Invoke-SystemPhase treats the same
                        # default call. Previously the return value was
                        # discarded, so a silent registration failure in the
                        # defaultuser0 window would have left no diagnostic.
                        $defaultRearmOk = Register-ResumeTask -TaskName $taskName -ScriptPath $context.ScriptPath
                        if (-not (ConvertTo-ScalarBool $defaultRearmOk)) {
                            Write-DeploymentLog -Message "Resume task '$taskName' registration failed during defaultuser0 re-arm; task may not be registered." -Level ERROR
                        }
                    } elseif (-not (ConvertTo-ScalarBool $rearm)) {
                        # Hook supplied and returned a falsy value. The hook
                        # contract in OEM-CONTRACT.md §4 documents
                        # RegisterResumeTask as returning bool; a false return
                        # was previously silent on this branch. Log it so the
                        # operator sees the failed registration. Matches the
                        # coercion-and-check that Invoke-SystemPhase already
                        # performs on the same hook.
                        Write-DeploymentLog -Message "Resume task '$taskName' hook returned false during defaultuser0 re-arm; task may not be registered." -Level ERROR
                    }
                }
            }
            Write-CleanSummary -Context $context
            return
        }

        if (-not $Force) {
            if ($stage -eq 'USER_DONE') {
                Write-DeploymentLog -Message 'Deployment converged (USER_DONE); nothing to do.' -Level INFO
                # Defensive cleanup: a prior run may have recorded USER_DONE
                # and then been interrupted between the marker write and
                # Unregister-ResumeTask, or Unregister may have failed
                # silently. Without this re-check, the resume task fires on
                # every logon and this early exit never cleans it up. This
                # mirrors the monolith's finally-block cleanup. Idempotent
                # when the task is already gone. Deliberately placed here
                # rather than in the outer finally: the defaultuser0 branch
                # re-arms the task and returns before reaching this point,
                # and a finally-block cleanup would tear down the task the
                # defaultuser0 handler just re-armed.
                $taskName = $Profile.ResumeTaskName
                if ($taskName) { Unregister-ResumeTask -TaskName $taskName }
                Write-CleanSummary -Context $context
                return
            }
            if ($stage -eq 'SYSTEM_DONE' -and $phase -eq 'SYSTEM') {
                Write-DeploymentLog -Message 'SYSTEM phase already complete; nothing to do in SYSTEM context.' -Level INFO
                Write-CleanSummary -Context $context
                return
            }
        }
        else {
            Write-DeploymentLog -Message 'Force enabled; bypassing stage-based convergence exits.' -Level INFO
        }

        $context.IsSystem = ($phase -eq 'SYSTEM')
        $context.IsUser   = ($phase -eq 'USER')

        if ($context.IsSystem) {
            Invoke-SystemPhase -Context $context
        }
        elseif ($context.IsUser) {
            Invoke-UserPhase -Context $context
        }

        Write-CleanSummary -Context $context
    }
    finally {
        Release-DeploymentMutex -Mutex $mutexInfo.Mutex -Owned $true
        Complete-FrameworkLogging
    }
}

function Get-SystemFamilyFromProfile {
    param([Parameter(Mandatory)] [psobject]$Profile)

    $result = Invoke-ProfileHook -Profile $Profile -HookName 'GetSystemFamily'
    if ([string]::IsNullOrWhiteSpace([string]$result)) { return 'Unknown' }
    return $result
}

function Test-AppPresence {
    # Hook-aware presence check for a manifest app. Identity precedence:
    #   1. OEM TestAppPresence hook, if supplied — authoritative.
    #   2. WingetAppId, if declared — USER phase only.
    #   3. Generic AppX/AppName detection.
    #
    # The Winget package identity takes precedence over generic detection
    # because a WinGet-installed app's uninstall DisplayName can differ
    # materially from its manifest AppName (e.g. the manifest entry
    # "Microsoft .NET Windows Desktop Runtime 8" installs as
    # "Microsoft Windows Desktop Runtime - 8.0.x (x64)"). `winget list
    # --id <PackageId> --exact` maps the installed registration back to
    # the declared package identity. The check is USER-gated because
    # WinGet installation itself is USER-only and winget list from SYSTEM
    # context cannot see the interactive user's inventory.
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [psobject]$App
    )

    $hook = $Context.Profile.TestAppPresence
    if ($hook) {
        # A hook may render a verdict ($true/$false) for apps it handles,
        # or return $null to decline. $null means "not my concern" — the
        # framework then continues with its own identity precedence chain
        # rather than treating the decline as a "not present" answer.
        # This lets a module hook only the exceptional apps (HP UEFI,
        # Acer's PredatorSense/NitroSense) without bypassing the
        # WingetAppId and AlternateAppNames checks for everything else.
        #
        # The last-item check uses the same "intent is the final value on
        # the pipeline" convention as ConvertTo-ScalarBool: a hook that
        # emits diagnostic output before returning $null is treated as
        # declining. A hook whose final value is $true, $false, or any
        # non-null value is evaluated as a verdict.
        $hookResult = & $hook $App $Context
        $items = @($hookResult)
        if ($items.Count -gt 0 -and $null -ne $items[-1]) {
            return ConvertTo-ScalarBool $hookResult
        }
    }

    if ($Context.IsUser -and -not [string]::IsNullOrWhiteSpace([string]$App.WingetAppId)) {
        if (Test-WingetPackageInstalled -PackageId $App.WingetAppId) {
            return $true
        }
    }

    if (Test-ApplicationInstalled -AppName $App.AppName -AppxPackageName $App.AppxPackageName -Exact) {
        return $true
    }

    # AlternateAppNames covers cases where the uninstall DisplayName
    # differs from the manifest's logical AppName — typically because the
    # installer registers a variant form (e.g. "Microsoft Windows Desktop
    # Runtime - 8" vs "Microsoft .NET Windows Desktop Runtime 8"). Each
    # alternate is tried in order via Test-ApplicationInstalled -Exact,
    # which still permits the normal version/architecture suffix match.
    # This is the phase-independent fallback for SYSTEM phase, where
    # WinGet inventory is not accessible.
    if ($App.PSObject.Properties['AlternateAppNames'] -and $App.AlternateAppNames) {
        foreach ($altName in @($App.AlternateAppNames)) {
            if ([string]::IsNullOrWhiteSpace([string]$altName)) { continue }
            if (Test-ApplicationInstalled -AppName $altName -Exact) {
                return $true
            }
        }
    }

    return $false
}

function Write-AppOutcomeFromContext {
    # Called from the phase loops at the end of each app's iteration.
    # Derives the terminal classification from the context's success/failure
    # buckets and merges it with any reason fields the installer paths
    # placed in $Context.AppOutcomes. For apps that reached the install
    # loop (Installed, Updated, AlreadyCurrent, Failed), emits exactly one
    # human-readable OUTCOME line to the per-app log; for Skipped and
    # Deferred apps, emits only the shared-log narrative line (per the
    # 2026-09-15 "Per-app log suppression" design in STATUS.md section 7).
    #
    # -SkipReason is optional. When supplied, it is stamped into
    # $Context.AppOutcomes for this app so the OUTCOME line names the gate
    # that stopped the app (family mismatch, conflict, prereq, deferral,
    # service gate). Installer paths do not pass it; skip sites do.
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [psobject]$App,
        [string]$SkipReason = ''
    )

    if ($SkipReason -and $Context.AppOutcomes) {
        if (-not $Context.AppOutcomes.ContainsKey($App.AppName)) {
            $Context.AppOutcomes[$App.AppName] = @{}
        }
        $Context.AppOutcomes[$App.AppName].SkipReason = $SkipReason
    }

    $classification =
        if     ($Context.InstalledApps.Contains($App.AppName))  { 'Installed' }
        elseif ($Context.UpdatedApps.Contains($App.AppName))    { 'Updated' }
        elseif ($Context.AlreadyCurrent.Contains($App.AppName)) { 'AlreadyCurrent' }
        elseif ($Context.FailedApps.Contains($App.AppName))     { 'Failed' }
        elseif ($Context.SkippedApps.Contains($App.AppName))    { 'Skipped' }
        elseif ($Context.DeferredApps.Contains($App.AppName))   { 'Deferred' }
        else                                                    { 'Unknown' }

    $r = @{}
    if ($Context.AppOutcomes -and $Context.AppOutcomes.ContainsKey($App.AppName)) {
        $r = $Context.AppOutcomes[$App.AppName]
    }

    # Human-readable narrative line. Routes to both PBR_Deployment.log and
    # the per-app log (via -AppName). Closes the logging gap where the skip
    # gates (NotEligible, ConflictPresent, PrereqMissing), the presence
    # short-circuit, and the USER-phase deferred case only produced a
    # per-app OUTCOME line — nothing in the shared log or transcript.
    # The OUTCOME line below is retained unchanged.
    $narrativeReason = ([string]$r.SkipReason) -replace '^Deferred:', ''
    $narrativeVerb = switch ($classification) {
        'Installed'      { 'Installed' }
        'Updated'        { 'Updated' }
        'AlreadyCurrent' { 'Already current' }
        'Skipped'        { 'Skipped' }
        'Deferred'       { 'Deferred' }
        'Failed'         { 'FAILED' }
        default          { 'Outcome' }
    }
    $narrativeSuffix = if ($narrativeReason) { " ($narrativeReason)" } else { '' }
    $narrativeLevel  = if ($classification -eq 'Failed') { 'WARN' } else { 'INFO' }

    # Per-app logs are reserved for apps the framework actually worked
    # on. Skipped and Deferred apps never reach Invoke-AppInstall; a
    # per-app log for them would contain nothing but the skip narrative
    # and the OUTCOME line, duplicating what the shared log already
    # carries. Route the narrative to the shared log only for those
    # classifications, and skip the OUTCOME emission entirely — the
    # narrative's skip reason is the machine-readable fact an operator
    # needs. Every app that reached the install loop (Installed,
    # Updated, AlreadyCurrent including presence short-circuits, Failed)
    # still gets both a per-app log and an OUTCOME line.
    $reachedInstallLoop = $classification -notin @('Skipped', 'Deferred')
    if ($reachedInstallLoop) {
        Write-DeploymentLog -Message "  ${narrativeVerb}: $($App.AppName)$narrativeSuffix" -Level $narrativeLevel -AppName $App.AppName
        Write-AppOutcome `
            -AppName           $App.AppName `
            -Classification    $classification `
            -TerminalReason    ([string]$r.TerminalReason) `
            -SkipReason        ([string]$r.SkipReason) `
            -InitialMethod     ([string]$r.InitialMethod) `
            -PreVersion        ([string]$r.PreVersion) `
            -PostVersion       ([string]$r.PostVersion) `
            -WinGetSource      ([string]$r.WinGetSource) `
            -WinGetExitCode    ([string]$r.WinGetExitCode) `
            -LocalInstaller    ([string]$r.LocalInstaller) `
            -LocalExitCode     ([string]$r.LocalExitCode)
    } else {
        Write-DeploymentLog -Message "  ${narrativeVerb}: $($App.AppName)$narrativeSuffix" -Level $narrativeLevel
    }
}

# Prerequisite identity map. Friendly-name/package mapping so post-install
# state checks use the actual DisplayName or AppX identity the prerequisite
# registers under, not the winget PackageId. Without this, every common
# prerequisite (AnyDesk, 7-Zip, WinRAR) is misreported as not-installed
# after a successful winget install, because the uninstall-registry display
# name differs from the winget PackageId. Store extensions carry an AppX
# identity and rely on it for detection.
$script:PrerequisiteIdentityMap = @{
    'AnyDesk.AnyDesk' = @{ Friendly = 'AnyDesk';             Appx = '' }
    '7zip.7zip'       = @{ Friendly = '7-Zip';               Appx = '' }
    'RARLab.WinRAR'   = @{ Friendly = 'WinRAR';              Appx = '' }
    '9MVZQVXJBQ9V'    = @{ Friendly = 'AV1 Video Extension'; Appx = 'Microsoft.AV1VideoExtension' }
    '9PMMSR1CGPWG'    = @{ Friendly = 'HEIF Image Extension'; Appx = 'Microsoft.HEIFImageExtension' }
    '9N4WGH0Z6VHQ'    = @{ Friendly = 'HEVC Video Extensions from Device Manufacturer'; Appx = 'Microsoft.HEVCVideoExtension' }
    '9N95Q1ZZPMH4'    = @{ Friendly = 'MPEG-2 Video Extension'; Appx = 'Microsoft.MPEG2VideoExtension' }
    '9NCTDW2W1BH8'    = @{ Friendly = 'Raw Image Extension'; Appx = 'Microsoft.RawImageExtension' }
    '9N4D0MSMP0PT'    = @{ Friendly = 'VP9 Video Extensions'; Appx = 'Microsoft.VP9VideoExtensions' }
    '9N5TDP8VCMHS'    = @{ Friendly = 'Web Media Extensions'; Appx = 'Microsoft.WebMediaExtensions' }
    '9PG2DK419DRG'    = @{ Friendly = 'WebP Image Extension'; Appx = 'Microsoft.WebpImageExtension' }
}

function Install-WingetPackage {
    # Thin wrapper around Invoke-WingetInstallSafe for prerequisites. Uses
    # -IsPrerequisite so failures go to SkippedApps and do not block USER_DONE.
    param(
        [Parameter(Mandatory)] [string]$PackageId,
        [string]$Source = '',
        [Parameter(Mandatory)] [psobject]$Context
    )

    # Resolve the prerequisite's detection identity. Unknown IDs fall back
    # to the raw PackageId, which preserves prior behaviour for any future
    # prerequisite added without a mapping entry.
    $friendly = $PackageId
    $appx     = ''
    if ($script:PrerequisiteIdentityMap.ContainsKey($PackageId)) {
        $entry    = $script:PrerequisiteIdentityMap[$PackageId]
        $friendly = $entry.Friendly
        $appx     = $entry.Appx
    }

    return Invoke-WingetInstallSafe `
        -PackageId       $PackageId `
        -PackageName     $friendly `
        -AppxPackageName $appx `
        -Source          $Source `
        -Context         $Context `
        -IsPrerequisite
}

function Invoke-GlobalPrerequisites {
    # Attempts the fleet-wide prerequisite packages via winget. Best-effort:
    # failures are routed to SkippedApps via -IsPrerequisite.
    param([Parameter(Mandatory)] [psobject]$Context)

    if ($Context.IsSystem) { return }

    # Short-circuit when Initialize-WinGetSession determined the CDN is
    # unreachable. Without this, 11 packages each burn their full winget
    # timeout on network calls that will never succeed — potentially
    # 100+ minutes of futile waiting before the OEM app loop begins.
    if ($Context.WingetSession -and $Context.WingetSession.NetworkReachable -eq $false) {
        Write-DeploymentLog -Message 'Skipping global prerequisites: winget CDN unreachable.' -Level WARN
        return
    }

    foreach ($prereq in $script:DefaultGlobalPrerequisites) {
        $null = Install-WingetPackage -PackageId $prereq.Id -Source $prereq.Source -Context $Context
        Start-Sleep -Seconds 2
    }
}

function Test-ProductFamilyMatch {
    param(
        [string]$SystemFamily,
        [string[]]$AllowedFamilies
    )

    if (-not $AllowedFamilies -or $AllowedFamilies.Count -eq 0) { return $true }
    return $SystemFamily -in $AllowedFamilies
}

function Test-PrereqsMet {
    # Resolves each prerequisite name back to its manifest entry so the
    # prerequisite's own identity (WingetAppId, AppxPackageName, or an
    # OEM-supplied TestAppPresence hook) governs the presence check. A
    # prerequisite whose manifest declares WingetAppId is checked by that
    # package identity, not by AppName. Names that do not resolve to a
    # manifest app fall back to generic AppName detection.
    param(
        [string[]]$PrerequisiteApps,
        [Parameter(Mandatory)] [psobject]$Context
    )

    if (-not $PrerequisiteApps -or $PrerequisiteApps.Count -eq 0) { return $true }

    foreach ($prereq in $PrerequisiteApps) {
        $manifestApp = @(
            $Context.Manifest.apps |
                Where-Object { $_.AppName -eq $prereq } |
                Select-Object -First 1
        )
        if ($manifestApp.Count -gt 0) {
            if (-not (Test-AppPresence -Context $Context -App $manifestApp[0])) {
                return $false
            }
        }
        else {
            if (-not (Test-ApplicationInstalled -AppName $prereq -Exact)) {
                return $false
            }
        }
    }
    return $true
}

function Test-ConflictsPresent {
    # Same manifest-resolution treatment as Test-PrereqsMet, for the same
    # reason: a conflicting app's own declared identity governs its
    # presence check, not just its logical AppName.
    param(
        [string[]]$ConflictingApps,
        [Parameter(Mandatory)] [psobject]$Context
    )

    if (-not $ConflictingApps -or $ConflictingApps.Count -eq 0) { return $false }

    foreach ($conflict in $ConflictingApps) {
        $manifestApp = @(
            $Context.Manifest.apps |
                Where-Object { $_.AppName -eq $conflict } |
                Select-Object -First 1
        )
        if ($manifestApp.Count -gt 0) {
            if (Test-AppPresence -Context $Context -App $manifestApp[0]) {
                return $true
            }
        }
        else {
            if (Test-ApplicationInstalled -AppName $conflict -Exact) {
                return $true
            }
        }
    }
    return $false
}

function Test-AppPhaseEligibility {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context
    )

    $installPhase = if ($App.InstallPhase) { [string]$App.InstallPhase } else { 'Any' }
    $interactive  = [bool]$App.RequiresInteractive

    if ($Context.IsSystem) {
        if ($installPhase -eq 'UserOnly') { return 'Skip-Phase' }
        if ($interactive)                 { return 'Skip-Phase' }
        return 'Attempt'
    }

    if ($Context.IsUser) {
        if ($installPhase -eq 'SystemOnly') { return 'Skip-Phase' }
        return 'Attempt'
    }

    return 'Skip-Phase'
}

function Test-AppEligibilityForPhase {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [string]$SystemFamily
    )

    if (-not (Test-ProductFamilyMatch -SystemFamily $SystemFamily -AllowedFamilies $App.ProductFamilies)) {
        return $false
    }

    if (-not (Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestStaticEligibility' -Parameters @{ App = $App; SystemFamily = $SystemFamily })) {
        return $false
    }

    if (-not (Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestDynamicEligibility' -Parameters @{ App = $App; Context = $Context })) {
        return $false
    }

    return $true
}

function Test-ServiceGatedReady {
    # Returns cached service readiness for the current phase. First call
    # populates $Context.ServiceReady; subsequent calls are free.
    param(
        [Parameter(Mandatory)] [psobject]$Context
    )

    if ($null -ne $Context.ServiceReady) {
        return [bool]$Context.ServiceReady
    }

    $hookResult = Invoke-ProfileHook -Profile $Context.Profile -HookName 'WaitForService' -Parameters @{ Context = $Context }
    if ($null -ne $hookResult) {
        $Context.ServiceReady = ConvertTo-ScalarBool $hookResult
        return $Context.ServiceReady
    }

    $serviceName = $Context.Profile.ServiceName
    if (-not $serviceName) {
        $Context.ServiceReady = $true
        return $true
    }

    # Coerce the profile's ServiceWaitSeconds default in code rather than
    # relying on Wait-ForNamedService's parameter default. Passing $null
    # to a typed [int] parameter binds as 0, not as the parameter default,
    # which would make the service wait exit immediately. Every current
    # module sets 180 explicitly; this guards against a future module that
    # omits the field.
    $waitTimeout = if ($Context.Profile.ServiceWaitSeconds) { [int]$Context.Profile.ServiceWaitSeconds } else { 180 }
    $Context.ServiceReady = Wait-ForNamedService `
        -Name $serviceName `
        -TimeoutSeconds $waitTimeout
    return [bool]$Context.ServiceReady
}

function Invoke-SystemPhase {
    param([Parameter(Mandatory)] [psobject]$Context)

    Write-DeploymentLog -Message 'SYSTEM phase: begin.' -Level INFO

    Invoke-ProfileHook -Profile $Context.Profile -HookName 'OnSystemPreInstall' -Parameters @{ Context = $Context } | Out-Null

    $systemFamily = Get-SystemFamilyFromProfile -Profile $Context.Profile
    $Context.SystemFamily = $systemFamily
    Write-DeploymentLog -Message "System family: $systemFamily" -Level INFO

    foreach ($app in $Context.Manifest.apps) {
        $phaseDecision = Test-AppPhaseEligibility -App $app -Context $Context
        if ($phaseDecision -eq 'Skip-Phase') {
            Add-UniqueValue -List $Context.DeferredApps -Value $app.AppName
            $deferReason = if ($app.InstallPhase -eq 'UserOnly') { 'Deferred:UserOnly' } else { 'Deferred:RequiresInteractive' }
            Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason $deferReason
            continue
        }

        if (-not (Test-AppEligibilityForPhase -App $app -Context $Context -SystemFamily $systemFamily)) {
            # If the profile already recorded this app as failed during a
            # phase-preinstall hook (marker/hardware gate), don't also list
            # it as skipped. Failure wins; one entry, one bucket.
            if (-not $Context.FailedApps.Contains($app.AppName)) {
                Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
            }
            Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'NotEligible'
            continue
        }

        if (Test-ConflictsPresent -ConflictingApps $app.ConflictingApps -Context $Context) {
            if ($app.Required) {
                Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
            } else {
                Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
            }
            Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'ConflictPresent'
            continue
        }

        # Presence short-circuit (SYSTEM). Winget never runs in SYSTEM, so an
        # already-installed app is done. Positioned after conflict checks,
        # before prerequisite and service gates: conflicts win over presence,
        # and both win over a would-be redundant install attempt.
        if (Test-AppPresence -Context $Context -App $app) {
            Add-UniqueValue -List $Context.AlreadyCurrent -Value $app.AppName
            if ($Context.AppOutcomes -and -not $Context.AppOutcomes.ContainsKey($app.AppName)) {
                $v = Get-ApplicationVersion -AppName $app.AppName -AppxPackageName $app.AppxPackageName
                if (-not $v -and $app.PSObject.Properties['AlternateAppNames'] -and $app.AlternateAppNames) {
                    foreach ($alt in @($app.AlternateAppNames)) {
                        if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                        $v = Get-ApplicationVersion -AppName $alt
                        if ($v) { break }
                    }
                }
                $Context.AppOutcomes[$app.AppName] = @{
                    TerminalReason = 'PresenceShortCircuit'
                    InitialMethod  = 'AlreadyInstalled'
                    PreVersion     = [string]$v
                    PostVersion    = [string]$v
                }
            }
            Write-AppOutcomeFromContext -Context $Context -App $app
            continue
        }

        if (-not (Test-PrereqsMet -PrerequisiteApps $app.PrerequisiteApps -Context $Context)) {
            if ($app.Required) {
                Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
            } else {
                Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
            }
            Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'PrereqMissing'
            continue
        }

        if ($app.ServiceGated) {
            if (-not (Test-ServiceGatedReady -Context $Context)) {
                Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
                Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'ServiceNotReady'
                continue
            }
        }

        $appStart = Get-Date
        Invoke-AppInstall -App $app -Context $Context | Out-Null
        $appElapsed = (Get-Date) - $appStart
        Write-DeploymentLog -Message ("Finished: {0} (elapsed {1:d\.hh\:mm\:ss})" -f $app.AppName, $appElapsed) -Level INFO -AppName $app.AppName
        Write-AppOutcomeFromContext -Context $Context -App $app
    }

    Invoke-ProfileHook -Profile $Context.Profile -HookName 'OnSystemPostInstallPreLayout' -Parameters @{ Context = $Context } | Out-Null

    $osInfo = Get-FrameworkOSInfo
    $layoutOk = Invoke-LayoutGeneration -Context $Context -SystemFamily $systemFamily -OSInfo $osInfo -Phase 'SYSTEM'
    if (-not $layoutOk) {
        Add-UniqueValue -List $Context.FailedApps -Value "$($Context.Profile.Name) Layout Injection (SYSTEM)"
    }

    Invoke-ProfileHook -Profile $Context.Profile -HookName 'OnSystemPostLayout' -Parameters @{ Context = $Context } | Out-Null

    $taskName = $Context.Profile.ResumeTaskName
    if ($taskName) {
        $taskOk = Invoke-ProfileHook -Profile $Context.Profile -HookName 'RegisterResumeTask' -Parameters @{ Name = $taskName; ScriptPath = $Context.ScriptPath }
        if ($null -eq $taskOk) {
            $taskOk = Register-ResumeTask -TaskName $taskName -ScriptPath $Context.ScriptPath
        } else {
            $taskOk = ConvertTo-ScalarBool $taskOk
        }
        if (-not $taskOk) {
            Write-DeploymentLog -Message "Resume task '$taskName' not verified; SYSTEM_DONE will not be recorded." -Level ERROR
            Add-UniqueValue -List $Context.FailedApps -Value "$($Context.Profile.Name) Resume Task"
        }
    }

    $completionReady = Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestSystemCompletionRequirements' -Parameters @{ Context = $Context }

    if (-not $completionReady -or $Context.FailedApps.Count -gt 0) {
        Write-DeploymentLog -Message 'SYSTEM phase not converged; stage unchanged.' -Level WARN
        return
    }

    if (Set-DeploymentStage -MarkerPath $Context.MarkerPath -ValueName $Context.StageName -Stage 'SYSTEM_DONE') {
        Write-DeploymentLog -Message 'SYSTEM phase complete; SYSTEM_DONE recorded.' -Level INFO
    } else {
        Write-DeploymentLog -Message 'SYSTEM_DONE write failed.' -Level ERROR
    }
}

function Invoke-UserPhase {
    param([Parameter(Mandatory)] [psobject]$Context)

    Write-DeploymentLog -Message 'USER phase: begin.' -Level INFO

    # Time sync: some winget/msstore paths need a clock within tolerance.
    try {
        Start-Service w32time -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 2
        Start-Process -FilePath 'w32tm.exe' -ArgumentList '/resync /force' `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-DeploymentLog -Message "Time sync failed: $($_.Exception.Message)" -Level WARN
    }

    # TLS 1.2 + best-effort TLS 1.3. Older Windows 10 builds do not default
    # to TLS 1.2, which breaks winget HTTPS endpoints.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    Invoke-ProfileHook -Profile $Context.Profile -HookName 'OnUserPreInstall' -Parameters @{ Context = $Context } | Out-Null

    $wingetSession = $null

    try {
        $wingetSession = Initialize-WinGetSession -Context $Context
        # Fleet-wide prerequisites (AnyDesk, 7-Zip, WinRAR, Store extensions).
        # pre.ps1 owns local provisioning; this is an update/verification pass.
        Write-DeploymentLog -Message 'Installing global prerequisites.' -Level INFO
        Invoke-GlobalPrerequisites -Context $Context

        $systemFamily = Get-SystemFamilyFromProfile -Profile $Context.Profile
        $Context.SystemFamily = $systemFamily
        Write-DeploymentLog -Message "System family: $systemFamily" -Level INFO

        foreach ($app in $Context.Manifest.apps) {
            $phaseDecision = Test-AppPhaseEligibility -App $app -Context $Context
            if ($phaseDecision -eq 'Skip-Phase') {
                # In USER phase the only reason Test-AppPhaseEligibility
                # returns Skip-Phase is SystemOnly. Match the SYSTEM-phase
                # defer-reason naming convention (Deferred:<cause>) so an
                # operator sees Deferred:SystemOnly rather than the
                # generic Deferred. Add to DeferredApps so the
                # classification logic in Write-AppOutcomeFromContext
                # resolves to Deferred (not Unknown).
                Add-UniqueValue -List $Context.DeferredApps -Value $app.AppName
                Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'Deferred:SystemOnly'
                continue
            }

            if (-not (Test-AppEligibilityForPhase -App $app -Context $Context -SystemFamily $systemFamily)) {
                # Same as SYSTEM phase: failure recorded by a preinstall hook
                # takes precedence; don't duplicate into SkippedApps.
                if (-not $Context.FailedApps.Contains($app.AppName)) {
                    Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
                }
                Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'NotEligible'
                continue
            }

            if (Test-ConflictsPresent -ConflictingApps $app.ConflictingApps -Context $Context) {
                if ($app.Required) {
                    Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
                } else {
                    Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
                }
                Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'ConflictPresent'
                continue
            }

            # Presence short-circuit (USER). Short-circuit only when the app
            # has no WingetAppId; otherwise fall through so winget can verify
            # or update. Positioned after conflict checks, before prerequisite
            # and service gates: conflicts win over presence, and both win
            # over a would-be redundant install attempt.
            $wingetApplicable = -not [string]::IsNullOrWhiteSpace($app.WingetAppId)
            if ((Test-AppPresence -Context $Context -App $app) -and (-not $wingetApplicable)) {
                Add-UniqueValue -List $Context.AlreadyCurrent -Value $app.AppName
                if ($Context.AppOutcomes -and -not $Context.AppOutcomes.ContainsKey($app.AppName)) {
                    $v = Get-ApplicationVersion -AppName $app.AppName -AppxPackageName $app.AppxPackageName
                    if (-not $v -and $app.PSObject.Properties['AlternateAppNames'] -and $app.AlternateAppNames) {
                        foreach ($alt in @($app.AlternateAppNames)) {
                            if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                            $v = Get-ApplicationVersion -AppName $alt
                            if ($v) { break }
                        }
                    }
                    $Context.AppOutcomes[$app.AppName] = @{
                        TerminalReason = 'PresenceShortCircuit'
                        InitialMethod  = 'AlreadyInstalled'
                        PreVersion     = [string]$v
                        PostVersion    = [string]$v
                    }
                }
                Invoke-SupplementalWingetIfDeclared -App $app -Context $Context
                Write-AppOutcomeFromContext -Context $Context -App $app
                continue
            }

            if (-not (Test-PrereqsMet -PrerequisiteApps $app.PrerequisiteApps -Context $Context)) {
                if ($app.Required) {
                    Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
                } else {
                    Add-UniqueValue -List $Context.SkippedApps -Value $app.AppName
                }
                Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'PrereqMissing'
                continue
            }

            if ($app.ServiceGated) {
                if (-not (Test-ServiceGatedReady -Context $Context)) {
                    Add-UniqueValue -List $Context.FailedApps -Value $app.AppName
                    Write-AppOutcomeFromContext -Context $Context -App $app -SkipReason 'ServiceNotReady'
                    continue
                }
            }

            $appStart = Get-Date
            Invoke-AppInstall -App $app -Context $Context | Out-Null
            $appElapsed = (Get-Date) - $appStart
            Write-DeploymentLog -Message ("Finished: {0} (elapsed {1:d\.hh\:mm\:ss})" -f $app.AppName, $appElapsed) -Level INFO -AppName $app.AppName
            Write-AppOutcomeFromContext -Context $Context -App $app
        }

        $osInfo = Get-FrameworkOSInfo
        $layoutOk = Invoke-LayoutGeneration -Context $Context -SystemFamily $systemFamily -OSInfo $osInfo -Phase 'USER'
        if (-not $layoutOk) {
            Add-UniqueValue -List $Context.FailedApps -Value "$($Context.Profile.Name) Layout Injection (USER)"
        }

        Invoke-ProfileHook -Profile $Context.Profile -HookName 'OnUserPostInstall' -Parameters @{ Context = $Context } | Out-Null

        $healthOk = Invoke-PostDeploymentHealthCheck -Context $Context

        if ($Context.FailedApps.Count -eq 0 -and $healthOk) {
            if (Set-DeploymentStage -MarkerPath $Context.MarkerPath -ValueName $Context.StageName -Stage 'USER_DONE') {
                Write-DeploymentLog -Message 'USER phase complete; USER_DONE recorded.' -Level INFO
                $taskName = $Context.Profile.ResumeTaskName
                if ($taskName) { Unregister-ResumeTask -TaskName $taskName }
            } else {
                Write-DeploymentLog -Message 'USER_DONE write failed.' -Level ERROR
            }
        } else {
            Write-DeploymentLog -Message 'USER phase incomplete; stage remains for retry.' -Level WARN
        }
    }
    finally {
        if ($wingetSession) {
            Restore-WinGetSession -State $wingetSession
        }
    }
}

function Complete-AppInstall {
    # Called at every successful terminal path in Invoke-AppInstall. Reaching
    # this helper means the caller has declared the application operation
    # successful — either winget succeeded, the app was confirmed present
    # after a winget failure, or a custom/local installer returned success.
    # Any FailedApps entry for this application came from an intermediate
    # operation (Winget 0x8A15005E, or Winget classified as Failed before
    # the app registration became visible) and must not survive a successful
    # terminal result.
    #
    # SEMANTICS OF AlreadyCurrent AS USED HERE
    # ---------------------------------------
    # AlreadyCurrent is the framework's generic "successful presence at the
    # end of the operation" bucket. It is accurate when winget reported an
    # already-installed state, or when a local/custom installer ran and the
    # app did not change version. It is *approximate* on the "winget failed
    # but the app is present" path (Site 2 of Invoke-AppInstall): the
    # framework knows the app is present and treats the operation as
    # converged, but it has not proven the app was literally "already
    # current" in the version-comparison sense. Operators reading the
    # summary should read AlreadyCurrent as "presence-confirmed recovery"
    # on this path, not as a version-equality claim. The per-app log and
    # the winget divergence diagnostic preserve the more precise history.
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context
    )

    $Context.FailedApps.Remove($App.AppName) | Out-Null

    # Report-visibility fallback: if the caller reached this point without
    # populating any of the success buckets (which happens on the "winget
    # failed but the app became present" path), record the app so the summary
    # still reflects it. Report-only; does not affect convergence.
    if (-not $Context.InstalledApps.Contains($App.AppName) -and
        -not $Context.UpdatedApps.Contains($App.AppName) -and
        -not $Context.AlreadyCurrent.Contains($App.AppName)) {
        Write-DeploymentLog -Message "Presence-confirmed recovery for $($App.AppName): winget did not report success but the app is present. Recorded as AlreadyCurrent (reporting bucket only)." -Level INFO -AppName $App.AppName
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
        if ($Context.AppOutcomes -and $Context.AppOutcomes.ContainsKey($App.AppName)) {
            $existingReason = [string]$Context.AppOutcomes[$App.AppName].TerminalReason
            if ($existingReason -like 'WinGetFailed*') {
                $Context.AppOutcomes[$App.AppName].TerminalReason = 'PresenceConfirmedRecovery'
            }
        }
    }

    Invoke-SupplementalWingetIfDeclared -App $App -Context $Context
}

function Invoke-AppInstall {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context
    )

    Write-DeploymentLog -Message "Processing: $($App.AppName)" -Level INFO -AppName $App.AppName

    $wingetResult = $null

    if ($Context.IsUser -and -not [string]::IsNullOrWhiteSpace([string]$App.WingetAppId)) {
        $alternateNames = if ($App.PSObject.Properties['AlternateAppNames'] -and $App.AlternateAppNames) {
            @($App.AlternateAppNames)
        } else {
            @()
        }
        $wingetResult = Invoke-WingetInstallSafe `
            -PackageId         $App.WingetAppId `
            -PackageName       $App.AppName `
            -AppxPackageName   $App.AppxPackageName `
            -AlternateAppNames $alternateNames `
            -Source            $App.WingetSource `
            -Context           $Context
        if ($wingetResult.DeploymentSucceeded) {
            Complete-AppInstall -App $App -Context $Context
            return
        }

        # Winget was attempted and failed. If the app is already present,
        # do not fall back to a local installer as an upgrade path. The
        # 0x8A15005E override (pinned-cert mismatch, state check untrusted)
        # is deliberately allowed through: the affected installers are
        # idempotent re-installs, not upgrades.
        #
        # The main app is present, so a declared supplemental may still run.
        # Supplemental outcome is informational only and does not affect
        # convergence.
        if ($wingetResult.ExitCode -ne [int]0x8A15005E -and
            (Test-AppPresence -Context $Context -App $App)) {
            Complete-AppInstall -App $App -Context $Context
            return
        }
    }

    if ($App.CustomInstaller) {
        $customInstaller = $null
        if ($Context.Profile.CustomInstallers) {
            $customInstaller = $Context.Profile.CustomInstallers[[string]$App.CustomInstaller]
        }
        if (-not $customInstaller) {
            Write-DeploymentLog -Message "App '$($App.AppName)' declares custom installer '$($App.CustomInstaller)' but the profile did not register it." -Level ERROR -AppName $App.AppName
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
            if ($Context.AppOutcomes) {
                if (-not $Context.AppOutcomes.ContainsKey($App.AppName)) {
                    $Context.AppOutcomes[$App.AppName] = @{}
                }
                $Context.AppOutcomes[$App.AppName].TerminalReason = 'CustomInstallerNotRegistered'
                $Context.AppOutcomes[$App.AppName].InitialMethod  = 'Local'
            }
            return
        }
        Write-DeploymentLog -Message "Invoking custom installer: $($App.CustomInstaller)" -Level INFO -AppName $App.AppName
        $customOk = ConvertTo-ScalarBool (& $customInstaller $App $Context $wingetResult)
        if ($customOk) {
            if ($Context.AppOutcomes) {
                if (-not $Context.AppOutcomes.ContainsKey($App.AppName)) {
                    $Context.AppOutcomes[$App.AppName] = @{}
                }
                $Context.AppOutcomes[$App.AppName].TerminalReason = 'CustomInstallerCompleted'
                $Context.AppOutcomes[$App.AppName].InitialMethod  = 'Local'
                $Context.AppOutcomes[$App.AppName].LocalInstaller = [string]$App.CustomInstaller
            }
            Complete-AppInstall -App $App -Context $Context
            return
        }

        # The custom installer may have classified the app itself before
        # returning $false — e.g. Huawei's Install-HuaweiPCManager records
        # a SYSTEM-phase refusal as Skipped rather than Failed. Honor that
        # classification: only promote the app to FailedApps when the
        # installer did not already place it in SkippedApps or DeferredApps.
        # This is the contract documented in OEM-CONTRACT.md §4.
        $declined = $Context.SkippedApps.Contains($App.AppName) -or
                    $Context.DeferredApps.Contains($App.AppName)
        if ($declined) {
            # Remove any FailedApps entry left by a prior winget failure in
            # the same phase. The custom-installer decline contract in
            # OEM-CONTRACT.md §4 states that a declined app does not block
            # convergence; a residual winget failure would otherwise defeat
            # that classification, because Write-AppOutcomeFromContext
            # resolves FailedApps before SkippedApps.
            $Context.FailedApps.Remove($App.AppName) | Out-Null
        } else {
            Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        }
        if ($Context.AppOutcomes) {
            if (-not $Context.AppOutcomes.ContainsKey($App.AppName)) {
                $Context.AppOutcomes[$App.AppName] = @{}
            }
            $Context.AppOutcomes[$App.AppName].TerminalReason = if ($declined) { 'CustomInstallerDeclined' } else { 'CustomInstallerFailed' }
            $Context.AppOutcomes[$App.AppName].InitialMethod  = 'Local'
            $Context.AppOutcomes[$App.AppName].LocalInstaller = [string]$App.CustomInstaller
        }
        return
    }

    $hasLocalPath = -not [string]::IsNullOrWhiteSpace([string]$App.InstallerPath)
    $hasCandidates = ($App.InstallerCandidates -and @($App.InstallerCandidates).Count -gt 0)
    if ($hasLocalPath -or $hasCandidates) {
        $allowPresent = ($null -ne $wingetResult -and $wingetResult.ExitCode -eq [int]0x8A15005E)
        $lr = Invoke-LocalInstaller `
            -InstallerPath       $App.InstallerPath `
            -InstallerFilter     $App.InstallerFilter `
            -InstallerArgs       $App.InstallerArgs `
            -InstallerCandidates $App.InstallerCandidates `
            -AppxPackageName     $App.AppxPackageName `
            -AppName             $App.AppName `
            -App                 $App `
            -Context             $Context `
            -Interactive:$App.RequiresInteractive `
            -AllowPresentReinstall:$allowPresent
        # The local installer owns its own post-install presence
        # verification: it returns Success = $true only after
        # Test-AppPresence (or Test-ApplicationInstalled) confirms the
        # app is present. A re-check here would be redundant on the
        # happy path and dangerous on the unhappy path — for an AppX
        # provision that fails machine-wide verification (the D5 case),
        # a per-user registration can satisfy Test-AppPresence and mask
        # the failure. Consume the local installer's result as-is.
        if ($lr.Success) {
            Complete-AppInstall -App $App -Context $Context
        }
        return
    }

    if ($Context.IsSystem) {
        # Reached when the app was phase-eligible in SYSTEM but has no
        # System-capable install method (e.g. a WingetAppId-only entry
        # with InstallPhase: Any). Deferred to USER, where winget runs.
        # SkipReason is set so the narrative and any future OUTCOME
        # consumer name the cause rather than emitting a bare Deferred.
        Add-UniqueValue -List $Context.DeferredApps -Value $App.AppName
        if ($Context.AppOutcomes) {
            if (-not $Context.AppOutcomes.ContainsKey($App.AppName)) {
                $Context.AppOutcomes[$App.AppName] = @{}
            }
            $Context.AppOutcomes[$App.AppName].SkipReason = 'Deferred:SystemPhase'
        }
        return
    }
    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
}

function Invoke-SupplementalWingetIfDeclared {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context
    )

    if (-not $Context.IsUser) { return }
    if ([string]::IsNullOrWhiteSpace([string]$App.SupplementalWingetAppID)) { return }

    # Manifest contract (enforced at runtime pending a formal validator):
    # a supplemental must declare at least one identity suitable for
    # post-install detection. The winget PackageId alone is not a reliable
    # identity and produces false classifications.
    if (-not $App.SupplementalAppxPackageName -and -not $App.SupplementalAppName) {
        Write-DeploymentLog -Message "Supplemental on '$($App.AppName)' declares SupplementalWingetAppID but no SupplementalAppxPackageName or SupplementalAppName; refusing to install (manifest contract violation)." -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.SkippedApps -Value "$($App.AppName) Supplemental"
        return
    }

    $suppSource  = if ($App.SupplementalWingetSource)    { [string]$App.SupplementalWingetSource }    else { '' }
    $suppAppx    = if ($App.SupplementalAppxPackageName) { [string]$App.SupplementalAppxPackageName } else { '' }
    $suppFriendly = if ($App.SupplementalAppName)        { [string]$App.SupplementalAppName }         else { [string]$App.SupplementalWingetAppID }
    $supp = Invoke-WingetInstallSafe `
        -PackageId       $App.SupplementalWingetAppID `
        -PackageName     $suppFriendly `
        -AppxPackageName $suppAppx `
        -Source          $suppSource `
        -Context         $Context `
        -IsPrerequisite
    # A failed supplemental is already routed to SkippedApps by
    # Invoke-WingetInstallSafe via -IsPrerequisite, under $suppFriendly.
    # Do not add a second entry here; the framework would then show two
    # skip entries for one failure. Informational only either way; the
    # supplemental never blocks convergence.
    if ($supp.DeploymentSucceeded) {
        Write-DeploymentLog -Message "Supplemental installed: $suppFriendly (for $($App.AppName))." -Level INFO -AppName $App.AppName
    }
}

function Wait-ForNamedService {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [int]$TimeoutSeconds = 180
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-DeploymentLog -Message "Service '$Name' not found." -Level WARN
        return $false
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Start-Sleep -Seconds 10
            return $true
        }
        Start-Sleep -Seconds 5
    }
    Write-DeploymentLog -Message "Service '$Name' not running after ${TimeoutSeconds}s." -Level WARN
    return $false
}

function Get-FrameworkOSInfo {
    try {
        $os = ((Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption | Out-String).Trim()
        if ($os -match 'Windows 11') { return 'Windows 11' }
        if ($os -match 'Windows 10') { return 'Windows 10' }
        return 'Unknown'
    } catch { return 'Unknown' }
}

function Write-CleanSummary {
    param([Parameter(Mandatory)] [psobject]$Context)

    Write-Host ''
    Write-Host ('-' * 60) -ForegroundColor Cyan
    Write-Host "INSTALLATION SUMMARY - $($Context.OEMName)" -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor Cyan

    if ($Context.InstalledApps.Count -gt 0) {
        Write-Host "`nINSTALLED ($($Context.InstalledApps.Count)):" -ForegroundColor Green
        foreach ($a in ($Context.InstalledApps | Sort-Object)) { Write-Host "  [+] $a" -ForegroundColor Green }
    }
    if ($Context.UpdatedApps.Count -gt 0) {
        Write-Host "`nUPDATED ($($Context.UpdatedApps.Count)):" -ForegroundColor Green
        foreach ($a in ($Context.UpdatedApps | Sort-Object)) { Write-Host "  [^] $a" -ForegroundColor Green }
    }
    if ($Context.AlreadyCurrent.Count -gt 0) {
        Write-Host "`nALREADY CURRENT ($($Context.AlreadyCurrent.Count)):" -ForegroundColor DarkGreen
        foreach ($a in ($Context.AlreadyCurrent | Sort-Object)) { Write-Host "  [OK] $a" -ForegroundColor DarkGreen }
    }
    if ($Context.FailedApps.Count -gt 0) {
        Write-Host "`nFAILED ($($Context.FailedApps.Count)):" -ForegroundColor Red
        foreach ($a in ($Context.FailedApps | Sort-Object)) { Write-Host "  [FAIL] $a" -ForegroundColor Red }
    }
    if ($Context.SkippedApps.Count -gt 0) {
        Write-Host "`nSKIPPED: $($Context.SkippedApps.Count) application(s) skipped (see deployment log for details)." -ForegroundColor Gray
    }
    if ($Context.DeferredApps.Count -gt 0) {
        Write-Host "`nDEFERRED TO USER: $($Context.DeferredApps.Count)" -ForegroundColor Gray
    }

    $totalProcessed = $Context.InstalledApps.Count +
                      $Context.UpdatedApps.Count +
                      $Context.AlreadyCurrent.Count +
                      $Context.SkippedApps.Count +
                      $Context.DeferredApps.Count +
                      $Context.FailedApps.Count

    Write-Host ''
    Write-Host ('-' * 60) -ForegroundColor Cyan
    Write-Host 'SUMMARY STATISTICS' -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor Cyan
    Write-Host ("  Total processed:  {0}" -f $totalProcessed) -ForegroundColor White
    Write-Host ("  Newly installed:  {0}" -f $Context.InstalledApps.Count) -ForegroundColor Green
    Write-Host ("  Updated:          {0}" -f $Context.UpdatedApps.Count) -ForegroundColor Green
    Write-Host ("  Already current:  {0}" -f $Context.AlreadyCurrent.Count) -ForegroundColor DarkGreen
    Write-Host ("  Skipped:          {0}" -f $Context.SkippedApps.Count) -ForegroundColor Yellow
    Write-Host ("  Deferred to USER: {0}" -f $Context.DeferredApps.Count) -ForegroundColor Yellow
    Write-Host ("  Failed:           {0}" -f $Context.FailedApps.Count) -ForegroundColor Red
    if ($Context.RebootRequired) {
        Write-Host ''
        Write-Host '  [*] A REBOOT IS REQUIRED to complete installation.' -ForegroundColor Yellow
    }
    Write-Host ('-' * 60) -ForegroundColor Cyan
    Write-Host ''
}

Export-ModuleMember -Function `
    Start-OEMDeployment, `
    Get-SystemFamilyFromProfile, `
    Test-AppPresence, `
    Test-ProductFamilyMatch, `
    Test-PrereqsMet, `
    Test-ConflictsPresent, `
    Test-AppPhaseEligibility, `
    Test-AppEligibilityForPhase, `
    Test-ServiceGatedReady, `
    Install-WingetPackage, `
    Invoke-GlobalPrerequisites, `
    Invoke-SystemPhase, `
    Invoke-UserPhase, `
    Invoke-AppInstall, `
    Complete-AppInstall, `
    Invoke-SupplementalWingetIfDeclared, `
    Wait-ForNamedService, `
    Get-FrameworkOSInfo, `
    Write-CleanSummary, `
    Write-AppOutcomeFromContext
