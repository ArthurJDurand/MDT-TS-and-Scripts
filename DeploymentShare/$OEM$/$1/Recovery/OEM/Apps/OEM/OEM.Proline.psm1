<#
.SYNOPSIS
    Proline OEM module.

.DESCRIPTION
    Implements the OEM contract. Proline has no OEM applications: the
    manifest's apps array is empty. The module exists so that Proline
    hardware receives the framework's fleet-wide behavior — default-user
    hive hardening, Spotlight suppression, layout generation with the
    Outlook taskbar pin — without installing any vendor-specific app.

    Family detection returns a constant 'Proline' token. No manifest app
    is gated on family, so the value is informational only and is used
    solely for logging.

    Model keyword enrichment (Proline, Thinline, Pinnacle) is not performed
    here: with no family classifier and no app gating, an enriched model
    string would have no consumer. Get-SystemModel in State.psm1 supplies
    the raw model for logging.

    No custom installers. No service gate. No winget path for OEM apps
    (there are none).
#>

# --- System family ---

function Get-ProlineSystemFamily {
    return 'Proline'
}

# --- Eligibility ---

function Test-ProlineAppEligibility {
    param($App, $SystemFamily)

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Proline defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-ProlineDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-ProlineLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Proline'
        ManifestFile         = 'Proline.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Proline'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Proline_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'ProlinePBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-ProlineSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-ProlineAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-ProlineDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-ProlineLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
