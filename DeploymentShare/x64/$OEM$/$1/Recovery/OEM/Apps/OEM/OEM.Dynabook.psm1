<#
.SYNOPSIS
    Dynabook OEM module.

.DESCRIPTION
    Implements the OEM contract. Family detection maps model strings to
    Portege, Tecra, Satellite, ESeries, or Unknown. OEM apps are four UWP
    packages published under 7906AAC0.*; only dynabook Support Utility is
    pinned (Start + taskbar). No winget IDs, no service gate, no custom
    installers.
#>

$script:DynabookCachedIsMobile      = $null
$script:DynabookIsMobileInitialized = $false

# --- Hardware helpers ---

function Test-DynabookIsMobile {
    if (-not $script:DynabookIsMobileInitialized) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $script:DynabookCachedIsMobile = ($cs -and $cs.PCSystemType -eq 2)
        $script:DynabookIsMobileInitialized = $true
    }
    return $script:DynabookCachedIsMobile
}

# --- System family ---

function Get-DynabookSystemFamily {
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

    $familyKeywords = @('Portege','Tecra','Satellite','E-Series','Dynabook')

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
        '(?i)\b(Portege)\b'   { return 'Portege' }
        '(?i)\b(Tecra)\b'     { return 'Tecra' }
        '(?i)\b(Satellite)\b' { return 'Satellite' }
        '(?i)\b(E-Series)\b'  { return 'ESeries' }
        default               { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-DynabookAppEligibility {
    param($App, $SystemFamily)

    # Dynabook apps install on every family including Unknown. The monolith
    # scoped apps to @($Script:SystemFamily), which always matched whatever
    # was detected. The framework equivalent is empty ProductFamilies in the
    # manifest, so this hook is effectively a pass-through. Kept for
    # consistency with other OEM modules and to allow future per-app scoping
    # without touching the profile.
    if ($App.MobileOnly -and -not (Test-DynabookIsMobile)) {
        return $false
    }

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Dynabook defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-DynabookDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-DynabookLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Dynabook'
        ManifestFile         = 'Dynabook.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Dynabook'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Dynabook_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'DynabookPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-DynabookSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-DynabookAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-DynabookDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-DynabookLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
