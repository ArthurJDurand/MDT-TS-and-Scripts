<#
.SYNOPSIS
    Dell OEM module.

.DESCRIPTION
    Implements the OEM contract documented in Framework/Engine.psm1.
    All Dell-specific behavior lives here: system family detection,
    eligibility rules (Optimizer marker, ACC marker, CPU generation,
    legacy/modern hardware), and Default User hive setup. OEM-specific
    additional taskbar pins are not defined; the framework supplies the
    universal Outlook pin via Layout.psm1's Get-FrameworkOutlookPin.

    Alienware Command Center is marker-driven. HKLM\SOFTWARE\OEM\Dell\
    ACCVersion must be 'v6' or 'v5'; absent or unrecognized means no
    ACC install. The manifest declares two entries — one per version —
    each gated in Test-DellAppEligibility on the marker. A candidate-
    fallback chain cannot be used: the two installers refuse to coexist
    (v5 exits 1603 when v6 is present, per its own log message), and v6
    installs on hardware outside Dell's v6 supported-model list, so v6
    never "fails and lets v5 try." See PROJECT-NOTE.md §4.3 for the
    rationale and STATUS.md §7 for the hardware test.

    ConflictingApps asymmetry. Both ACC entries (v6 and v5) declare
    ConflictingApps: ["Dell Optimizer"] with Required: true; Dell
    Optimizer declares ConflictingApps: ["Dell Precision Optimizer",
    "Dell Power Manager Service", "Alienware Command Center (v6)",
    "Alienware Command Center (v5)"] with Required: false. The
    asymmetry is currently unreachable: the two apps' ProductFamilies
    lists are disjoint — ACC is Alienware + GSeries, Dell Optimizer
    excludes both. No machine can have both eligible at once. The
    asymmetry is a defensive declaration only; if a future manifest
    edit gives the two apps overlapping families, the Required: true
    on the ACC side would fail convergence where the Required: false
    on the Optimizer side would silently skip. Revisit the Required
    flags at that point, not now.
#>

$script:CachedCPUName                = $null
$script:CachedCPUNameInitialized     = $false
$script:CachedOptimizerDecision      = $null
$script:OptimizerDecisionInitialized = $false
$script:CachedAccVersion             = $null
$script:AccVersionInitialized        = $false
$script:AccVersionWarned             = $false
$script:CachedIsMobile               = $null
$script:IsMobileInitialized          = $false

# --- CPU and hardware helpers ---

function Get-DellCPUName {
    if (-not $script:CachedCPUNameInitialized) {
        $p = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
        $script:CachedCPUName = if ($p) { $p.Name } else { $null }
        $script:CachedCPUNameInitialized = $true
    }
    return $script:CachedCPUName
}

# CPU generation parsing is delegated to the framework helpers
# Get-IntelGenerationFromName and Get-AmdGenerationFromName in
# Framework\State.psm1. Centralizing the parser means a future fix or a
# new pattern reaches every OEM module in one edit.

function Test-DellOptimizerSupport {
    $cpu   = Get-DellCPUName
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    $amd   = Get-AmdGenerationFromName   -CPUName $cpu
    return ($null -ne $intel -and $intel -ge 10) -or ($null -ne $amd -and $amd -ge 4)
}

function Test-DellModernHardware {
    # Modern = Intel 11th gen or newer, or AMD Ryzen 5000-series or
    # newer (including Ryzen AI, whose symbolic generation is 30).
    $cpu = Get-DellCPUName
    if (-not $cpu) { return $false }
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    if ($null -ne $intel) { return ($intel -ge 11) }
    $amd = Get-AmdGenerationFromName -CPUName $cpu
    if ($null -ne $amd) { return ($amd -ge 5) }
    return $false
}

function Get-OptimizerDecision {
    if (-not $script:OptimizerDecisionInitialized) {
        $path = 'HKLM:\SOFTWARE\OEM\Dell'
        if (Test-Path $path) {
            $prop = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            $val = $null
            if ($prop) {
                if ($prop.PSObject.Properties['OptimizerDecision']) { $val = $prop.OptimizerDecision }
                if (-not $val -and $prop.PSObject.Properties['Decision']) { $val = $prop.Decision }
            }
            $script:CachedOptimizerDecision = if ($val) { [string]$val } else { $null }
        } else {
            $script:CachedOptimizerDecision = $null
        }
        Write-DeploymentLog -Message "OptimizerDecision marker: $(if ($script:CachedOptimizerDecision) { $script:CachedOptimizerDecision } else { '(none)' })" -Level INFO
        $script:OptimizerDecisionInitialized = $true
    }
    return $script:CachedOptimizerDecision
}

function Test-DellIsMobile {
    if (-not $script:IsMobileInitialized) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $script:CachedIsMobile = ($cs -and $cs.PCSystemType -eq 2)
        $script:IsMobileInitialized = $true
    }
    return $script:CachedIsMobile
}

function Get-AccVersion {
    # Marker-driven ACC version selection. Values: 'v6', 'v5', or absent.
    # Absent marker means "do not install ACC"; the framework never guesses.
    # v6 and v5 cannot coexist (v5 refuses to install when v6 is present,
    # exit 1603), so automatic fallback between the two is not reliable.
    # secondrun.ps1 is the authoritative writer of this marker; it runs
    # after the interactive operator has decided which version the hardware
    # needs, then re-invokes pbr.ps1 -Force. See PROJECT-NOTE.md §4.3.
    if (-not $script:AccVersionInitialized) {
        $path = 'HKLM:\SOFTWARE\OEM\Dell'
        if (Test-Path $path) {
            $prop = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            $val = $null
            if ($prop -and $prop.PSObject.Properties['ACCVersion']) {
                $val = $prop.ACCVersion
            }
            $script:CachedAccVersion = if ($val) { [string]$val } else { $null }
        } else {
            $script:CachedAccVersion = $null
        }
        Write-DeploymentLog -Message "ACCVersion marker: $(if ($script:CachedAccVersion) { $script:CachedAccVersion } else { '(none)' })" -Level INFO
        $script:AccVersionInitialized = $true
    }
    return $script:CachedAccVersion
}

# --- System family ---

# Family tokens returned by Get-DellSystemFamily: Alienware, Latitude,
# OptiPlex, Precision, XPS, Inspiron, Vostro, GSeries, DellProEssential,
# DellProPremium, DellBase, Unknown. DellBase is the fallback for a
# candidate string starting with "Dell " that matched no named family;
# Unknown means no candidate matched any pattern. Three manifest entries
# declare DellBase in ProductFamilies (Dell SupportAssist,
# DellInc.DellSupportAssistforPCs, Dell Optimizer), so those apps install
# on hardware that resolves to this fallback.
function Get-DellSystemFamily {
    $candidates = @(
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Name
        (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Version
    ) | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToString().Trim() } |
        Select-Object -Unique

    foreach ($candidate in $candidates) {
        if ($candidate -match '(?i)^Alienware')                     { return 'Alienware' }
        if ($candidate -match '(?i)^Latitude')                      { return 'Latitude' }
        if ($candidate -match '(?i)^OptiPlex')                      { return 'OptiPlex' }
        if ($candidate -match '(?i)^Precision')                     { return 'Precision' }
        if ($candidate -match '(?i)^XPS')                           { return 'XPS' }
        if ($candidate -match '(?i)^Inspiron')                      { return 'Inspiron' }
        if ($candidate -match '(?i)^Vostro')                        { return 'Vostro' }
        # G-series: accept both the bare form ("G15 5520", as returned by
        # Win32_ComputerSystemProduct.Name on some BIOS revisions) and the
        # Dell-prefixed form ("Dell G15 5520", as returned by
        # Win32_ComputerSystem.Model on most G-series hardware). Anchoring
        # to (?:^|Dell ) keeps baseboard IDs like "0XXXG5" from matching.
        if ($candidate -match '(?i)^(?:Dell\s+)?G\d{1,4}\b')        { return 'GSeries' }
        if ($candidate -match '(?i)^Dell Pro\s+\d+\s+Essential\b')  { return 'DellProEssential' }
        if ($candidate -match '(?i)^Dell Pro\s+Essential\b')        { return 'DellProEssential' }
        if ($candidate -match '(?i)^Dell Pro\s+\d+\s+(?:Plus|Max)\b') { return 'DellProPremium' }
        if ($candidate -match '(?i)^Dell Pro\s+(?:Plus|Max)\b')     { return 'DellProPremium' }
        if ($candidate -match '(?i)^Dell Pro')                      { return 'DellProPremium' }
        if ($candidate -match '(?i)^Dell \d+ Plus')                 { return 'DellProPremium' }
        if ($candidate -match '(?i)^Dell (?!Pro)')                  { return 'DellBase' }
    }
    return 'Unknown'
}

# --- Eligibility ---

function Test-DellAppEligibility {
    param($App, $SystemFamily)

    if ($App.MobileOnly -and -not (Test-DellIsMobile)) { return $false }

    # ACC marker gate: only the entry matching the marker is eligible.
    # Absent marker → both entries return $false (no ACC install).
    # Unrecognized marker value → both entries return $false with a WARN.
    if ($App.AppName -in @('Alienware Command Center (v6)', 'Alienware Command Center (v5)')) {
        $accVersion = Get-AccVersion
        if ([string]::IsNullOrWhiteSpace($accVersion)) { return $false }
        if ($accVersion -notin @('v6','v5')) {
            if (-not $script:AccVersionWarned) {
                Write-DeploymentLog -Message "Unrecognized ACCVersion marker '$accVersion' (expected 'v6' or 'v5'); both ACC entries skipped." -Level WARN
                $script:AccVersionWarned = $true
            }
            return $false
        }
        $selectedEntry = "Alienware Command Center ($accVersion)"
        if ($App.AppName -ne $selectedEntry) { return $false }
    }

    $optimizerSupported = Test-DellOptimizerSupport
    $decision = Get-OptimizerDecision

    if ($App.RequireOptimizerSupport -and -not $optimizerSupported) { return $false }
    if ($App.SkipIfDellOptimizerSupported -and $optimizerSupported -and $decision -ne 'Unsupported') { return $false }

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    if ($App.AppName -eq 'Dell Power Manager Service' -and (Test-DellModernHardware)) { return $false }

    if ($App.AppName -eq 'Dell Precision Optimizer') {
        if ($SystemFamily -ne 'Precision') { return $false }
        if (Test-DellModernHardware) { return $false }
    }

    if ($App.AppName -eq 'Dell Optimizer' -and $decision -in @('Unsupported','Deferred')) { return $false }

    return $true
}

# --- Default User hive and CloudContent policy ---

function Invoke-DellDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-DellLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Dell defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Dell'
        ManifestFile         = 'Dell.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Dell'
        StageName            = 'DeploymentStage'
        ServiceName          = 'SupportAssistAgent'
        ResumeTaskName       = 'Dell_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'DellPBR'
        WinGetTimeoutSeconds = 900
        LocalTimeoutSeconds  = 900
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-DellSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-DellAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-DellDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-DellLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
