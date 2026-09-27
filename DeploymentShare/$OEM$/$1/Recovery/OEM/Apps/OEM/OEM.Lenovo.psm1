<#
.SYNOPSIS
    Lenovo OEM module.

.DESCRIPTION
    Implements the OEM contract. Family detection maps Lenovo model strings
    to Commercial (ThinkPad/ThinkCentre/ThinkStation/ThinkBook), Gaming
    (Legion/LOQ/IdeaPad Gaming), Consumer (IdeaPad/Yoga/Flex/V15), or
    Unknown. Vantage is eligible on every family including Unknown; Hotkeys
    is eligible only on known families and only on mobile systems.
#>

$script:LenovoCachedIsMobile      = $null
$script:LenovoIsMobileInitialized = $false

# --- Hardware helpers ---

function Test-LenovoIsMobile {
    if (-not $script:LenovoIsMobileInitialized) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $script:LenovoCachedIsMobile = ($cs -and $cs.PCSystemType -eq 2)
        $script:LenovoIsMobileInitialized = $true
    }
    return $script:LenovoCachedIsMobile
}

# --- System family ---

function Get-LenovoSystemFamily {
    # Two-stage detection mirroring the monolith:
    #   1. Get-Model        — keyword-enrich SMBIOS strings (IdeaPad, Legion,
    #                          ThinkPad, etc.) to prefer a readable model name
    #                          over a bare product ID.
    #   2. Get-ProductFamily — map the enriched model to one of Commercial,
    #                          Gaming, Consumer, or Unknown.
    # Both are folded here so the framework sees a single hook.
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

    $familyKeywords = @(
        'IdeaPad','Legion','LOQ','ThinkBook','ThinkCentre',
        'ThinkPad','ThinkStation','Yoga','Flex','V15'
    )

    $model = $null
    foreach ($candidate in $values) {
        foreach ($keyword in $familyKeywords) {
            if ($candidate -match [regex]::Escape($keyword)) {
                $model = $candidate
                break
            }
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

    # Unknown → Unknown (Vantage still installed because its manifest
    # declares ProductFamilies including "Unknown"; Hotkeys excludes
    # "Unknown" and is skipped).
    switch -Regex ($model) {
        '(?i)(ThinkPad|ThinkCentre|ThinkStation|ThinkBook)' { return 'Commercial' }
        '(?i)(Legion|LOQ|IdeaPad.*Gaming)'                  { return 'Gaming' }
        '(?i)(IdeaPad|Yoga|Flex|V15)'                       { return 'Consumer' }
        default                                             { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-LenovoAppEligibility {
    param($App, $SystemFamily)

    # MobileOnly gate: applies to Hotkeys (laptop-only utility). Vantage
    # does not set MobileOnly and installs on desktops too.
    if ($App.MobileOnly -and -not (Test-LenovoIsMobile)) { return $false }

    # ProductFamilies gate: Vantage declares all four families including
    # Unknown, so it installs on unrecognized Lenovo hardware. Hotkeys
    # declares only the three known families, so it is excluded on
    # Unknown — matching the monolith's "Unknown family does NOT install
    # or require Hotkeys" invariant.
    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Lenovo defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-LenovoDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-LenovoLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Lenovo'
        ManifestFile         = 'Lenovo.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Lenovo'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Lenovo_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'LenovoPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-LenovoSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-LenovoAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-LenovoDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-LenovoLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
