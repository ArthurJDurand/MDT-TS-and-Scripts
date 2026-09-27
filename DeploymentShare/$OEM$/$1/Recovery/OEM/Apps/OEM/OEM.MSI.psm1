<#
.SYNOPSIS
    MSI OEM module.

.DESCRIPTION
    Marker-driven deployment. HKLM\SOFTWARE\OEM\MSI\MSICenterSelection decides
    which one centre app (plus Dragon Center companions) is installed. No
    family-based routing; Get-MSIAppEligibility reads the marker and the
    three-state hardware class. Phase-preinstall hooks translate marker
    violations and hardware incompatibilities into FailedApps entries, so
    SYSTEM_DONE / USER_DONE are blocked when the marker is invalid or the
    hardware cannot run the selected app.
#>

$script:MSIMarkerPath     = 'HKLM:\SOFTWARE\OEM\MSI'
$script:MSIMarkerName     = 'MSICenterSelection'
$script:MSIValidSelections = @('MSICenter','MSICenterPro','CreatorCenter','MSICenterS','DragonCenter')
$script:MSIModernOnlyApps  = @('MSI Center','MSI Center Pro','MSI Center S')
$script:MSILegacyOnlyApps  = @('Creator Center','Dragon Center')
$script:MSIDragonCompanions = @('MSI Driver App Center','MSI Help Desk')

$script:MSICachedCPUName           = $null
$script:MSICachedCPUNameInitialized = $false

# --- Hardware helpers ---

function Get-MSICPUName {
    if (-not $script:MSICachedCPUNameInitialized) {
        $p = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
        $script:MSICachedCPUName = if ($p) { $p.Name } else { $null }
        $script:MSICachedCPUNameInitialized = $true
    }
    return $script:MSICachedCPUName
}

# CPU generation parsing is delegated to the framework helpers
# Get-IntelGenerationFromName and Get-AmdGenerationFromName in
# Framework\State.psm1. Centralizing the parser means a future fix or a
# new pattern reaches every OEM module in one edit.

function Get-MSIHardwareClass {
    $cpu   = Get-MSICPUName
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    $amd   = Get-AmdGenerationFromName   -CPUName $cpu

    if ($null -ne $intel) {
        if ($intel -ge 11) { return 'Modern' }
        return 'Legacy'
    }
    if ($null -ne $amd) {
        if ($amd -ge 5) { return 'Modern' }
        return 'Legacy'
    }
    return 'Unknown'
}

# --- System family ---

function Get-MSISystemFamily {
    # MSI has no family-based routing. Every app is selected by marker, so
    # the framework's ProductFamily check is bypassed by empty ProductFamilies
    # in the manifest. This hook returns a constant token for logging and to
    # satisfy the framework contract.
    return 'Unknown'
}

# --- Marker read helper ---

function Get-MSISelection {
    $prop = Get-ItemProperty -Path $script:MSIMarkerPath -Name $script:MSIMarkerName -ErrorAction SilentlyContinue
    if (-not $prop) { return $null }
    return [string]$prop.$($script:MSIMarkerName)
}

# --- Eligibility ---

function Test-MSIAppEligibilitySelectedNames {
    # Single source of truth for the marker → selected-apps mapping.
    # Test-MSIAppEligibility and Register-MSIPhasePreChecks both call this
    # so the two call sites cannot drift.
    param([string]$Marker)
    switch ($Marker) {
        'MSICenter'     { return @('MSI Center') }
        'MSICenterPro'  { return @('MSI Center Pro') }
        'MSICenterS'    { return @('MSI Center S') }
        'CreatorCenter' { return @('Creator Center') }
        'DragonCenter'  { return @('Dragon Center','MSI Driver App Center','MSI Help Desk') }
        default         { return @() }
    }
}

function Test-MSIAppEligibility {
    param($App, $SystemFamily)

    $marker = Get-MSISelection
    if ([string]::IsNullOrWhiteSpace($marker)) { return $false }              # not selected
    if ($marker -notin $script:MSIValidSelections) { return $false }         # invalid; failure handled by preinstall hooks

    # Determine which apps the marker selects. Delegated to a single helper
    # so the mapping cannot drift between eligibility and the phase
    # pre-checks that also need it.
    $selected = Test-MSIAppEligibilitySelectedNames -Marker $marker

    if ($App.AppName -notin $selected) { return $false }

    $hwClass = Get-MSIHardwareClass

    if ($App.AppName -in $script:MSIModernOnlyApps) {
        return ($hwClass -eq 'Modern')
    }
    if ($App.AppName -in $script:MSILegacyOnlyApps) {
        return ($hwClass -eq 'Legacy')
    }
    if ($App.AppName -in $script:MSIDragonCompanions) {
        # Companions inherit Dragon Center's eligibility; Dragon Center is
        # legacy-only, so companions are too.
        return ($hwClass -eq 'Legacy')
    }

    return $true
}

# --- Phase-preinstall: translate marker/hardware violations to failures ---

function Register-MSIPhasePreChecks {
    param($Context)

    $marker = Get-MSISelection

    if ([string]::IsNullOrWhiteSpace($marker)) {
        # No marker: no apps, no failure. Matches the monolith's behaviour:
        # missing/empty marker → no centre apps installed.
        return
    }

    if ($marker -notin $script:MSIValidSelections) {
        Write-DeploymentLog -Message "Invalid MSICenterSelection marker: '$marker'." -Level ERROR
        Add-UniqueValue -List $Context.FailedApps -Value "MSI Center selection marker: $marker"
        return
    }

    $hwClass = Get-MSIHardwareClass
    Write-DeploymentLog -Message "MSI marker='$marker' hardwareClass='$hwClass'" -Level INFO

    if ($marker -in @('MSICenter','MSICenterPro','MSICenterS') -and $hwClass -ne 'Modern') {
        Write-DeploymentLog -Message "$marker requires modern hardware (Intel 11th Gen+ or AMD Ryzen 5000+)." -Level ERROR
        foreach ($appName in (Test-MSIAppEligibilitySelectedNames -Marker $marker)) {
            Add-UniqueValue -List $Context.FailedApps -Value $appName
        }
        return
    }

    if ($marker -in @('CreatorCenter','DragonCenter') -and $hwClass -ne 'Legacy') {
        Write-DeploymentLog -Message "$marker is legacy-only and cannot run on modern or unknown hardware." -Level ERROR
        foreach ($appName in (Test-MSIAppEligibilitySelectedNames -Marker $marker)) {
            Add-UniqueValue -List $Context.FailedApps -Value $appName
        }
        return
    }
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). MSI defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive ---

function Invoke-MSIDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-MSILiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'MSI'
        ManifestFile         = 'MSI.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\MSI'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'MSI_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'MSIPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-MSISystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-MSIAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context)
                                                Invoke-MSIDefaultUserHiveSetup -Context $Context
                                                Register-MSIPhasePreChecks     -Context $Context
                                            }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context)
                                                Invoke-MSILiveUserSpotlightSuppression
                                                Register-MSIPhasePreChecks -Context $Context
                                            }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
