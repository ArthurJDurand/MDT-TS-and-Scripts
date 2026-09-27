<#
.SYNOPSIS
    Microsoft Surface OEM module.

.DESCRIPTION
    Implements the OEM contract. Two OEM applications, both Store-sourced
    AppX packages:
      - Microsoft.SurfaceHub          Start + Taskbar pin
      - Microsoft.SurfaceDiagnostics  Start pin only

    The Surface app (package identity Microsoft.SurfaceHub; Store ID
    9WZDNCRFJB8P) is the companion app for all Surface devices and requires
    Windows 10 version 18362.0 (1903) or higher. SurfaceDiagnostics requires
    Windows 10 version 14393.0 (1607) or higher. Each app is gated at its
    own floor in Test-SurfaceAppEligibility; on older builds the app is
    silently ineligible rather than failed.

    Note: the marker registry path is HKLM\SOFTWARE\OEM\Microsoft. The OEM
    token is 'Surface' so the module and manifest filenames remain
    descriptive; the marker path preserves the historic registry layout
    that operators may already have deployed on Surface hardware.
#>

# Minimum build floors, per app.
# SurfaceHub: Microsoft Download Center lists 18362 (Windows 10 1903).
# SurfaceDiagnostics: Store listing lists 14393 (Windows 10 1607).
# Each app is gated at its own floor. A machine that meets 14393 but
# not 18362 installs Diagnostics and skips SurfaceHub — which is the
# correct behavior, because SurfaceHub genuinely requires the higher
# build.
$script:SurfaceDiagnosticsMinimumBuild = 14393
$script:SurfaceHubMinimumBuild = 18362

# --- System family ---

function Get-SurfaceSystemFamily {
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
        'Surface Pro','Surface Laptop','Surface Studio',
        'Surface Book','Surface Go','Surface Hub','Surface'
    )

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
        '(?i)\b(Surface Pro)\b'    { return 'Surface Pro' }
        '(?i)\b(Surface Laptop)\b' { return 'Surface Laptop' }
        '(?i)\b(Surface Studio)\b' { return 'Surface Studio' }
        '(?i)\b(Surface Book)\b'   { return 'Surface Book' }
        '(?i)\b(Surface Go)\b'     { return 'Surface Go' }
        '(?i)\b(Surface Hub)\b'    { return 'Surface Hub' }
        default                    { return 'Unknown' }
    }
}

# --- Eligibility ---

function Test-SurfaceAppEligibility {
    param($App, $SystemFamily)

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    # Surface app (package identity Microsoft.SurfaceHub; Store ID
    # 9WZDNCRFJB8P) requires Windows 10 version 18362.0 (1903) or higher
    # per Microsoft's published system requirements. SurfaceDiagnostics
    # requires Windows 10 version 14393.0 (1607) or higher per its Store
    # listing. Each app carries its own floor. On older builds the app is
    # silently ineligible rather than failed — matches the monolith's
    # conditional-add behavior.
    if ($App.AppName -in @('Microsoft.SurfaceHub','Microsoft.SurfaceDiagnostics')) {
        $build = $null
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($os -and $os.BuildNumber) { $build = [int]$os.BuildNumber }
        } catch {}
        if ($null -eq $build) {
            Write-DeploymentLog -Message 'Could not determine OS build number; allowing Surface app attempt.' -Level WARN
        }
        else {
            $appFloor = if ($App.AppName -eq 'Microsoft.SurfaceHub') {
                $script:SurfaceHubMinimumBuild
            } else {
                $script:SurfaceDiagnosticsMinimumBuild
            }
            if ($build -lt $appFloor) {
                Write-DeploymentLog -Message "$($App.AppName) requires OS build >= $appFloor; current build is $build. Marking ineligible." -Level INFO
                return $false
            }
        }
    }

    return $true
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Surface defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-SurfaceDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-SurfaceLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Surface'
        ManifestFile         = 'Surface.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Microsoft'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Microsoft_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'SurfacePBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-SurfaceSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-SurfaceAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        OnSystemPreInstall               = { param($Context) Invoke-SurfaceDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-SurfaceLiveUserSpotlightSuppression }

        CustomInstallers = @{}
    }
}

Export-ModuleMember -Function Get-OEMProfile
