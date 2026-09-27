<#
.SYNOPSIS
    Gigabyte OEM module.

.DESCRIPTION
    Implements the OEM contract. Zero OEM applications: the manifest's
    apps array is empty.

    The module exists so Gigabyte hardware receives the framework's
    fleet-wide behavior — default-user hive hardening, Spotlight
    suppression, layout generation with the Outlook taskbar pin — without
    installing any vendor-specific app. Gigabyte OEM utilities are
    installed manually from the official drivers page after OOBE.

    Family detection maps model strings to AERO, AORUS, Gaming (G5/G7),
    or Unknown. No manifest app is gated on family, so the value is
    informational only and appears in the phase-start log line.

    A future revision may reinstate marker- or family-driven OEM app
    installation (parallel to the MSI CentreSelection pattern) if the
    operator's workflow changes. Local media is not staged for Gigabyte
    today.
#>

# --- System family ---

function Get-GigabyteSystemFamily {
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

    # Keyword enrichment: prefer a readable AERO/AORUS/Sabre/BRIX/Gigabyte
    # model string over a bare product ID. Then classify.
    $familyKeywords = @('AERO','AORUS','Sabre','BRIX','Gigabyte')
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
        '(?i)\b(AERO)\b'  { return 'AERO' }
        '(?i)\b(AORUS)\b' { return 'AORUS' }
        '(?i)\b(G5|G7)\b' { return 'Gaming' }
        default           { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-GigabyteAppEligibility {
    param($App, $SystemFamily)

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Gigabyte defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-GigabyteDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-GigabyteLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Gigabyte'
        ManifestFile         = 'Gigabyte.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Gigabyte'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Gigabyte_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'GigabytePBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-GigabyteSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-GigabyteAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-GigabyteDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-GigabyteLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
