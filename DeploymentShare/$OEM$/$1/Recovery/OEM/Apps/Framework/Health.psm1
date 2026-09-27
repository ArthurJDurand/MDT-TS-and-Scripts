<#
.SYNOPSIS
    Vendor-neutral post-deployment health check.

.DESCRIPTION
    Rebuilds the expected-app set from Context.Manifest.apps using the
    same eligibility logic the install loop uses (phase eligibility,
    family/static/dynamic eligibility, conflict exclusion), then verifies
    each expected app is present via Test-AppPresence. Test-AppPresence uses
    an OEM-supplied TestAppPresence hook when one is provided; otherwise it
    uses the framework's generic application detector for both traditional
    desktop applications and AppX applications.

    The generic detector uses AppName as the logical application identity.
    Exact identity is preferred, while normal version/architecture suffixes
    on desktop DisplayName or package names are accepted. It does not fall
    back to unrestricted substring matching while running in exact mode.

    Prereq-missing apps are excluded from the expected set so a non-Required
    app with unmet prerequisites does not block convergence. Apps marked
    Required: true fail the phase before the health check runs.

    Intentionally-declined apps are also excluded: an app the framework
    intentionally declined at install time is not expected by health
    unless it is also in one of the success buckets (InstalledApps,
    UpdatedApps, AlreadyCurrent). This aligns Health with the
    custom-installer decline contract documented in OEM-CONTRACT.md §4:
    a custom installer that records its app in SkippedApps or
    DeferredApps before returning $false does not have that app
    reported as missing by health.

    The exclusion is a no-op for apps skipped by phase, family, static,
    dynamic, conflict, or prerequisite eligibility: those gates run
    before this check and already remove the app from the candidate
    set. It exists specifically for install-time declines that the
    eligibility gates do not catch.

    See STATUS.md section 6.8 for the health-check semantics and the
    documented HP UEFI presence-hook behavior.

    Detection is retried up to three times to accommodate AppX registration
    latency. Calls an optional profile hook (TestAdditionalHealth) for
    brand-specific checks.
#>

function Invoke-PostDeploymentHealthCheck {
    param([Parameter(Mandatory)] [psobject]$Context)

    Write-DeploymentLog -Message 'Health check: begin.' -Level INFO

    # Build the expected app list from the manifest using the same eligibility
    # logic that drove installation. Presence is checked via Test-AppPresence,
    # which is hook-aware.
    $systemFamily = if ($Context.SystemFamily) { $Context.SystemFamily } else { 'Unknown' }

    $expectedApps = @()
    foreach ($app in $Context.Manifest.apps) {
        # Every eligible manifest app participates in health verification.
        # Test-AppPresence uses an OEM-specific TestAppPresence hook when one
        # is supplied; otherwise it uses the framework's generic application
        # detector for AppX and traditional desktop applications.

        # Mirror the install loop's eligibility so an app that was intentionally
        # skipped at install time is not expected by the health check.
        if ((Test-AppPhaseEligibility -App $app -Context $Context) -eq 'Skip-Phase') { continue }

        if (-not (Test-AppEligibilityForPhase -App $app -Context $Context -SystemFamily $systemFamily)) { continue }

        if (Test-ConflictsPresent -ConflictingApps $app.ConflictingApps -Context $Context) { continue }

        if (-not (Test-PrereqsMet -PrerequisiteApps $app.PrerequisiteApps -Context $Context)) { continue }

        # Contract A: an app the framework intentionally declined at install
        # time is not part of the convergence target. Exclude it from the
        # expected set so the health check does not report it missing. This
        # aligns Health with the custom-installer decline contract documented
        # in OEM-CONTRACT.md §4.
        #
        # The exclusion is a no-op for apps already removed from the
        # candidate set by the eligibility, conflict, or prerequisite gates
        # above. It exists specifically for install-time declines that those
        # gates do not catch -- most notably the custom-installer path.
        #
        # The success-bucket guard matters: DeferredApps is additive across
        # phases. An app deferred from SYSTEM phase and then successfully
        # installed in USER phase remains in DeferredApps alongside its
        # success bucket. Excluding solely on DeferredApps membership would
        # wrongly drop a legitimately installed app from the expected set.
        $inSuccessBucket =
            $Context.InstalledApps.Contains($app.AppName) -or
            $Context.UpdatedApps.Contains($app.AppName) -or
            $Context.AlreadyCurrent.Contains($app.AppName)
        if (-not $inSuccessBucket) {
            if ($Context.SkippedApps.Contains($app.AppName) -or
                $Context.DeferredApps.Contains($app.AppName)) {
                continue
            }
        }

        $expectedApps += $app
    }

    if ($expectedApps.Count -gt 0) {
        $missing = @()
        for ($retry = 1; $retry -le 3; $retry++) {
            $missing = @()
            foreach ($app in $expectedApps) {
                try {
                    $present = Test-AppPresence -Context $Context -App $app
                }
                catch {
                    Write-DeploymentLog -Message "Health check could not inspect '$($app.AppName)': $($_.Exception.Message)" -Level WARN
                    $present = $false
                }
                if (-not $present) { $missing += $app.AppName }
            }
            if ($missing.Count -eq 0) { break }
            if ($retry -lt 3) {
                Write-DeploymentLog -Message "Packages not yet visible; retrying detection ($retry/3)." -Level INFO
                Start-Sleep -Seconds 10
                Clear-ApplicationCaches
            }
        }
        if ($missing.Count -gt 0) {
            Write-DeploymentLog -Message "Missing expected packages: $($missing -join ', ')" -Level WARN
            return $false
        }
    }

    if (-not (Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestAdditionalHealth' -Parameters @{ Context = $Context })) {
        Write-DeploymentLog -Message 'Additional health check failed.' -Level WARN
        return $false
    }

    Write-DeploymentLog -Message 'Health check passed.' -Level INFO
    return $true
}

Export-ModuleMember -Function Invoke-PostDeploymentHealthCheck
