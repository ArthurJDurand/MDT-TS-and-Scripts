<#
.SYNOPSIS
    ASUS OEM module.

.DESCRIPTION
    Implements the OEM contract. Family detection maps ASUS model strings
    to one of: ROG, TUF, PRIME, VivoBook, VivoBookGo, ZenBook, ZenBookDuo,
    ExpertBook, ProArt, Consumer, or Unknown. Unknown family receives no
    ASUS applications. Armoury Crate is eligible only on ROG/TUF/PRIME;
    MyASUS is eligible on all known families; ASUS Keyboard Hotkeys is
    mobile-only and eligible on all known families.
#>

$script:ASUSCachedIsMobile        = $null
$script:ASUSIsMobileInitialized   = $false

# --- Hardware helpers ---

function Test-ASUSIsMobile {
    if (-not $script:ASUSIsMobileInitialized) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $script:ASUSCachedIsMobile = ($cs -and $cs.PCSystemType -eq 2)
        $script:ASUSIsMobileInitialized = $true
    }
    return $script:ASUSCachedIsMobile
}

# --- System family ---

function Get-ASUSModel {
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

    if (-not $values -or $values.Count -eq 0) { return $null }

    return $values |
        Sort-Object @{ Expression = { $_.Length }; Descending = $true },
                    @{ Expression = { $_ };       Descending = $false } |
        Select-Object -First 1
}

function Get-ASUSSystemFamily {
    $model = Get-ASUSModel
    if ([string]::IsNullOrWhiteSpace($model)) { return 'Unknown' }

    # Order matters: more specific tokens must be matched before the broad
    # Consumer pattern, and ZenBookDuo must precede ZenBook.
    switch -Regex ($model) {
        '(?i)(UX481|UX482|UX582|UX8402|ZenBook Duo)' { return 'ZenBookDuo' }
        '(?i)(VivoBook.*Go)'                         { return 'VivoBookGo' }
        '(?i)(VivoBook)'                             { return 'VivoBook' }
        '(?i)(ZenBook)'                              { return 'ZenBook' }
        '(?i)(ExpertBook)'                           { return 'ExpertBook' }
        '(?i)(ROG)'                                  { return 'ROG' }
        '(?i)(TUF)'                                  { return 'TUF' }
        '(?i)(ProArt)'                               { return 'ProArt' }
        '(?i)(PRIME)'                                { return 'PRIME' }
        '(?i)\b(?:X|B|U|E|K|L)\d{2,}'                { return 'Consumer' }
        default                                      { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-ASUSAppEligibility {
    param($App, $SystemFamily)

    # Unknown family → no ASUS-specific apps at all, regardless of model
    # keyword matches. Mirrors Get-ASUSVariant's early return in the monolith.
    # Without this gate, apps with empty ProductFamilies would install on
    # unrecognized systems whenever the model happened to hit the Consumer
    # regex or one of the specific keywords.
    #
    # Note for a future reader: empty ProductFamilies in the manifest
    # means "all recognized families", not "all families". MyASUS and
    # ASUS Keyboard Hotkeys both declare ProductFamilies: [] and are
    # therefore skipped on Unknown family because this gate fires first.
    # That is intentional, and it mirrors the monolith. The interaction
    # between the two rules is not visible from the manifest alone.
    if ($SystemFamily -eq 'Unknown') { return $false }

    if ($App.MobileOnly -and -not (Test-ASUSIsMobile)) { return $false }

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). ASUS defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-ASUSDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-ASUSLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'ASUS'
        ManifestFile         = 'ASUS.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\ASUS'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'ASUS_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'AsusPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-ASUSSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-ASUSAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-ASUSDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-ASUSLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
