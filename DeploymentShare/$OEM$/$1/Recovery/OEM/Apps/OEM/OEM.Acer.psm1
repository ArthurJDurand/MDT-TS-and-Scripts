<#
.SYNOPSIS
    Acer OEM module.

.DESCRIPTION
    Implements the OEM contract. Custom installers handle PredatorSense and
    NitroSense, whose candidates span multiple package families across
    versions. Other Acer apps use the standard Install-Application path with
    a manifest-declared AUMID for pinning.

    PredatorSense and NitroSense are deliberately UserOnly. Their
    installers deploy a UWP component; provisioning it from SYSTEM
    context leaves the app broken, and a retry can uninstall it. USER
    phase installs the UWP component silently and the app works. Do not
    move these to Any or SystemOnly.
#>

$script:AcerCachedCPUName                = $null
$script:AcerCachedCPUNameInitialized     = $false
$script:AcerResolvedCandidateAumids      = @{}

# --- CPU helpers ---

function Get-AcerCPUName {
    if (-not $script:AcerCachedCPUNameInitialized) {
        $p = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
        $script:AcerCachedCPUName = if ($p) { $p.Name } else { $null }
        $script:AcerCachedCPUNameInitialized = $true
    }
    return $script:AcerCachedCPUName
}

# CPU generation parsing is delegated to the framework helpers
# Get-IntelGenerationFromName and Get-AmdGenerationFromName in
# Framework\State.psm1. Centralizing the parser means a future fix or a
# new pattern reaches every OEM module in one edit.

function Test-AcerGen3 {
    $cpu = Get-AcerCPUName
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    $amd   = Get-AmdGenerationFromName   -CPUName $cpu
    return ($intel -in @(9,10,11)) -or ($amd -in @(3,4,5))
}

function Test-AcerGen4 {
    $cpu = Get-AcerCPUName
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    $amd   = Get-AmdGenerationFromName   -CPUName $cpu
    return ($intel -eq 12) -or ($amd -eq 6)
}

function Test-AcerGen5 {
    $cpu = Get-AcerCPUName
    $intel = Get-IntelGenerationFromName -CPUName $cpu
    $amd   = Get-AmdGenerationFromName   -CPUName $cpu
    return ($intel -ge 13) -or ($amd -in @(7,8,9,30))
}

# --- System family ---

function Get-AcerSystemFamily {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue

    $candidates = @($cs.Model, $csp.Name, $bb.Product, $csp.Version) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToString().Trim() }

    $joined = $candidates -join ' '
    if ($joined -match '(?i)\b(Predator|Triton|Helios)\b')  { return 'Predator' }
    if ($joined -match '(?i)\bNitro\b')                     { return 'Nitro' }
    # Enduro must be matched before TravelMate. Enduro devices can carry a
    # model string containing both tokens (TravelMate Enduro / Enduro Urban
    # variants list TravelMate in BIOS product name). With TravelMate checked
    # first, those devices resolved to TravelMate and AcerSense — declared
    # with ProductFamilies [Standard, Enduro] — was silently skipped.
    if ($joined -match '(?i)\bEnduro\b')                    { return 'Enduro' }
    if ($joined -match '(?i)\b(TravelMate|Extensa)\b')      { return 'TravelMate' }
    if ($joined -match '(?i)\bVero\b')                      { return 'Vero' }
    if ($joined -match '(?i)\b(Swift|Aspire|Spin)\b')       { return 'Standard' }
    return 'Unknown'
}

# --- Eligibility ---

function Test-AcerAppEligibility {
    param($App, $SystemFamily)

    # Unknown family → no Acer-specific apps at all, regardless of CPU
    # generation. Mirrors Get-AcerVariant's early return in the monolith.
    # Without this gate, apps with empty ProductFamilies (Quick Access,
    # Care Center, Registration) would install on unrecognized systems
    # whenever the CPU happened to match Gen3/Gen4.
    if ($SystemFamily -eq 'Unknown') { return $false }

    if ($App.ProductFamilies -and $App.ProductFamilies.Count -gt 0 -and $SystemFamily -notin $App.ProductFamilies) {
        return $false
    }

    # Generation scoping is per-app, not uniform:
    #   PredatorSense / NitroSense  — Gen3, Gen4, and Gen5 (all supported
    #                                  generations for those products)
    #   AcerSense / TravelMateSense — Gen5 only. These are newer products
    #                                  with no Gen3/Gen4 equivalent; a Gen3
    #                                  or Gen4 machine would install a
    #                                  non-functional app if admitted.
    #   Acer Control Center and the remaining apps — Gen3 and Gen4 only,
    #                                  superseded on Gen5 by AcerSense /
    #                                  TravelMateSense.
    # Confirm the AcerSense / TravelMateSense Gen5-only scope during the
    # first Acer hardware-validation round.
    switch ($App.AppName) {
        'PredatorSense'         { return (Test-AcerGen5) -or (Test-AcerGen3) -or (Test-AcerGen4) }
        'NitroSense'            { return (Test-AcerGen5) -or (Test-AcerGen4) -or (Test-AcerGen3) }
        'AcerSense'             { return Test-AcerGen5 }
        'TravelMateSense'       { return Test-AcerGen5 }
        'Acer Control Center'   { return (Test-AcerGen3) -or (Test-AcerGen4) }
        'Acer Quick Access'     { return (Test-AcerGen3) -or (Test-AcerGen4) }
        'Acer Care Center'      { return (Test-AcerGen3) -or (Test-AcerGen4) }
        'Acer Registration'     { return (Test-AcerGen3) -or (Test-AcerGen4) }
    }

    return $true
}

# --- Candidate lists ---

function Get-AcerPredatorSenseCandidates {
    param([string]$BasePath)
    $candidates = @()
    if (Test-AcerGen5) {
        $v5 = Join-Path $BasePath 'v5'
        if (Test-Path $v5) {
            $candidates += @{
                Version = 'v5'
                Path    = $v5
                AUMID   = 'ULICTekInc.PredatorSenseforNotebook_nt9dgb7efx6bt!PredatorSense'
            }
        }
    }
    $v3 = Join-Path $BasePath 'v3'
    if (Test-Path $v3) {
        $candidates += @{
            Version = 'v3'
            Path    = $v3
            AUMID   = 'AcerIncorporated.PredatorSenseV30_48frkmn4z8aw4!CentenialConvert'
        }
    }
    return $candidates
}

function Get-AcerNitroSenseCandidates {
    param([string]$BasePath)
    $candidates = @()
    if (Test-AcerGen5) {
        $v5 = Join-Path $BasePath 'v5'
        if (Test-Path $v5) {
            $candidates += @{
                Version = 'v5'
                Path    = $v5
                AUMID   = 'ULICTekInc.NitroSenseforNotebook_nt9dgb7efx6bt!NitroSense'
            }
        }
    }
    if ((Test-AcerGen4) -or (Test-AcerGen5)) {
        $v4 = Join-Path $BasePath 'v4'
        if (Test-Path $v4) {
            $candidates += @{
                Version = 'v4'
                Path    = $v4
                AUMID   = 'ULICTekInc.NitroSenseforNotebook_nt9dgb7efx6bt!NitroSense'
            }
        }
    }
    $v3 = Join-Path $BasePath 'v3'
    if (Test-Path $v3) {
        $candidates += @{
            Version = 'v3'
            Path    = $v3
            AUMID   = 'AcerIncorporated.NitroSenseV31_48frkmn4z8aw4!App'
        }
    }
    return $candidates
}

function Get-AcerInstalledCandidate {
    param($App)
    $candidates = switch ($App.AppName) {
        'PredatorSense' { Get-AcerPredatorSenseCandidates -BasePath $App.InstallerPath }
        'NitroSense'    { Get-AcerNitroSenseCandidates    -BasePath $App.InstallerPath }
        default         { @() }
    }
    foreach ($c in $candidates) {
        $pkgFamily = ($c.AUMID -split '!')[0]
        if (Test-ApplicationInstalled -AppName $pkgFamily -AppxPackageName $pkgFamily) {
            return $c
        }
    }
    return $null
}

# --- Presence hook ---

function Test-AcerAppPresence {
    param($App, $Context)

    switch ($App.AppName) {
        'PredatorSense' {
            return ($null -ne (Get-AcerInstalledCandidate -App $App))
        }
        'NitroSense' {
            return ($null -ne (Get-AcerInstalledCandidate -App $App))
        }
    }

    # Any other Acer app: the hook declines to render a verdict. Returning
    # $null hands the app back to the framework's identity precedence
    # chain (WingetAppId -> AppxPackageName / AppName -> AlternateAppNames).
    # Acer Control Center, Acer Care Center, and VeroSense all declare a
    # WingetAppId; falling through to Test-ApplicationInstalled here would
    # bypass that identity check during USER phase.
    return $null
}

# --- Pin AUMID resolution hook ---

function Resolve-AcerPinAumid {
    param($App, $Context, $FallbackAumid)

    # 1. If this run installed a specific candidate, use that AUMID
    if ($script:AcerResolvedCandidateAumids.ContainsKey($App.AppName)) {
        $remembered = $script:AcerResolvedCandidateAumids[$App.AppName]
        $pkgFamily = ($remembered -split '!')[0]
        $resolved = Resolve-AumidForPin -AppxPackageName $pkgFamily -FallbackAUMID $remembered
        return $resolved
    }

    # 2. If any candidate is installed, resolve its AUMID dynamically
    $installed = Get-AcerInstalledCandidate -App $App
    if ($installed) {
        $pkgFamily = ($installed.AUMID -split '!')[0]
        return Resolve-AumidForPin -AppxPackageName $pkgFamily -FallbackAUMID $installed.AUMID
    }

    # 3. Dynamic resolution against the primary AppxPackageName
    $dynamic = Resolve-AumidForPin -AppxPackageName $App.AppxPackageName -FallbackAUMID $FallbackAumid
    if ($dynamic -and $dynamic -ne $FallbackAumid) { return $dynamic }

    # 4. AUMIDs.txt breadcrumb in the installer directory
    if ($App.InstallerPath -and (Test-Path $App.InstallerPath)) {
        $aumidFile = Get-ChildItem -Path $App.InstallerPath -Filter 'AUMIDs.txt' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object { ($_.FullName.Split('\').Count) } |
            Select-Object -First 1
        if ($aumidFile) {
            # Get-Content -First 1 on an empty file emits nothing, so the
            # raw value can be $null; calling .Trim() on $null throws.
            # Guard the raw value before trimming.
            $rawContent = Get-Content $aumidFile.FullName -First 1 -ErrorAction SilentlyContinue
            if ($rawContent) {
                $content = $rawContent.Trim()
                if ($content -and $content.Contains('!')) {
                    Write-DeploymentLog -Message "AUMID read from $($aumidFile.FullName): $content" -Level INFO -AppName $App.AppName
                    return $content
                }
            }
        }
    }

    # 5. Static fallback. Match the framework's own contract in
    # Resolve-AumidForPin: a bare package family name is not a usable
    # AUMID and returning it would produce a silently broken pin. Only
    # accept a declared fallback that is already a full AUMID (contains
    # '!'); otherwise decline so the framework's resolver takes over.
    if (-not [string]::IsNullOrWhiteSpace($FallbackAumid) -and $FallbackAumid.Contains('!')) {
        return $FallbackAumid
    }
    return $null
}

# --- Custom installers ---

function Install-AcerCandidateApp {
    param(
        [Parameter(Mandatory)] [psobject]$App,
        [Parameter(Mandatory)] [psobject]$Context,
        $WingetResult,
        [Parameter(Mandatory)] [scriptblock]$CandidateFactory
    )

    $candidates = & $CandidateFactory $App.InstallerPath
    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-DeploymentLog -Message "$($App.AppName): no candidates found under $($App.InstallerPath)" -Level ERROR -AppName $App.AppName
        Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
        return $false
    }

    foreach ($candidate in $candidates) {
        $pkgFamily = ($candidate.AUMID -split '!')[0]

        if (Test-ApplicationInstalled -AppName $pkgFamily -AppxPackageName $pkgFamily) {
            Write-DeploymentLog -Message "$($App.AppName) $($candidate.Version) already present" -Level INFO -AppName $App.AppName
            # Transactional candidate fallback: clear any FailedApps entry left
            # by a prior candidate (e.g. v5 failed, v3 succeeded).
            $Context.FailedApps.Remove($App.AppName) | Out-Null
            Add-UniqueValue -List $Context.AlreadyCurrent -Value $App.AppName
            $script:AcerResolvedCandidateAumids[$App.AppName] = $candidate.AUMID
            return $true
        }

        Write-DeploymentLog -Message "$($App.AppName): trying candidate $($candidate.Version) at $($candidate.Path)" -Level INFO -AppName $App.AppName

        # Manifest InstallerArgs is the single source of truth.
        $candidateArgs = [string]$App.InstallerArgs

        # Deliberately does not pass -App $App. The presence check here is
        # per-candidate (via -AppxPackageName $pkgFamily), not app-level;
        # passing -App would route through the module's TestAppPresence
        # hook, which resolves any installed candidate and would skip the
        # candidate loop. The candidate loop itself is the resolution
        # mechanism.
        $lr = Invoke-LocalInstaller `
            -InstallerPath       $candidate.Path `
            -InstallerFilter     '' `
            -InstallerArgs       $candidateArgs `
            -InstallerCandidates @() `
            -AppxPackageName     $pkgFamily `
            -AppName             $App.AppName `
            -Context             $Context

        if ($lr.Success) {
            # Transactional candidate fallback: clear any FailedApps entry left
            # by a prior candidate (e.g. v5 failed, v3 succeeded).
            $Context.FailedApps.Remove($App.AppName) | Out-Null
            $script:AcerResolvedCandidateAumids[$App.AppName] = $candidate.AUMID
            return $true
        }
    }

    Add-UniqueValue -List $Context.FailedApps -Value $App.AppName
    return $false
}

function Install-AcerPredatorSense {
    param($App, $Context, $WingetResult)
    return Install-AcerCandidateApp -App $App -Context $Context -WingetResult $WingetResult `
        -CandidateFactory { param($Base) Get-AcerPredatorSenseCandidates -BasePath $Base }
}

function Install-AcerNitroSense {
    param($App, $Context, $WingetResult)
    return Install-AcerCandidateApp -App $App -Context $Context -WingetResult $WingetResult `
        -CandidateFactory { param($Base) Get-AcerNitroSenseCandidates -BasePath $Base }
}

# --- Additional taskbar pins: framework-owned ---
# The universal Outlook pin is supplied by the framework
# (Layout.psm1 -> Get-FrameworkOutlookPin). Acer defines no
# OEM-specific additional taskbar pins beyond the framework's set.

# --- Default User hive and CloudContent policy ---

function Invoke-AcerDefaultUserHiveSetup {
    param($Context)
    Invoke-DefaultUserHiveHardening
}

function Invoke-AcerLiveUserSpotlightSuppression {
    Invoke-LiveUserSpotlightSuppression
}

# --- Profile ---

function Get-OEMProfile {
    param([Parameter(Mandatory)] [string]$Name)

    return [pscustomobject]@{
        Name                 = 'Acer'
        ManifestFile         = 'Acer.json'
        MarkerRegistryPath   = 'HKLM:\SOFTWARE\OEM\Acer'
        StageName            = 'DeploymentStage'
        ServiceName          = ''
        ResumeTaskName       = 'Acer_PBR_Resume'
        LogDirectory         = 'C:\ProgramData\OEM\Logs'
        EventSourceName      = 'AcerPBR'
        WinGetTimeoutSeconds = 600
        LocalTimeoutSeconds  = 600
        ServiceWaitSeconds   = 180

        GetSystemFamily                  = { Get-AcerSystemFamily }
        TestStaticEligibility            = { param($App, $SystemFamily) Test-AcerAppEligibility -App $App -SystemFamily $SystemFamily }
        TestDynamicEligibility           = $null
        TestAppPresence                  = { param($App, $Context) Test-AcerAppPresence -App $App -Context $Context }
        ResolvePinAumid                  = { param($App, $Context, $Fallback) Resolve-AcerPinAumid -App $App -Context $Context -FallbackAumid $Fallback }
        OnSystemPreInstall               = { param($Context) Invoke-AcerDefaultUserHiveSetup -Context $Context }
        OnSystemPostInstallPreLayout     = $null
        OnSystemPostLayout               = $null
        OnUserPostInstall                = $null
        TestSystemCompletionRequirements = $null
        RegisterResumeTask               = $null
        GetAdditionalTaskbarPins         = $null
        WaitForService                   = $null
        TestAdditionalHealth             = $null
        OnUserPreInstall                 = { param($Context) Invoke-AcerLiveUserSpotlightSuppression }

        CustomInstallers = @{
            'Install-AcerPredatorSense' = { param($App, $Context, $WingetResult) Install-AcerPredatorSense -App $App -Context $Context -WingetResult $WingetResult }
            'Install-AcerNitroSense'    = { param($App, $Context, $WingetResult) Install-AcerNitroSense    -App $App -Context $Context -WingetResult $WingetResult }
        }
    }
}

Export-ModuleMember -Function Get-OEMProfile
