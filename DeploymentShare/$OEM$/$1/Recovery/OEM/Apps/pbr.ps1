<#
.SYNOPSIS
    Generic OEM deployment framework entrypoint.

.DESCRIPTION
    Two-phase deployment engine. Vendor-specific behavior is supplied by an
    OEM module (OEM\OEM.<brand>.psm1) and its manifest (Manifests\<brand>.json).

    OEM selection priority:
      1. $env:OEM_NAME, if set. Used for testing and explicit override.
      2. Hardware manufacturer from Get-SystemManufacturer, matched against a
         keyword table.
      3. If $env:OEM_ALLOW_PRESENCE_FALLBACK is '1' and exactly one OEM module
         and manifest are present in this image, use it. Explicit opt-in only.
      4. Otherwise, abort with a diagnostic listing the OEMs staged in this
         image. The script does NOT silently default to any brand.

    If $env:OEM_NAME is set but the hardware manufacturer is recognized and
    differs, the script aborts. This prevents running a Dell image on an HP
    machine.

    This file contains no vendor-specific logic. All brand behavior is
    delegated through the OEM profile contract. See Framework/Engine.psm1.
#>

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }

function Get-OEMFromManufacturer {
    param(
        [string]$Manufacturer,
        [string]$Model = ''
    )

    if ([string]::IsNullOrWhiteSpace($Manufacturer)) { return $null }
    if ($Manufacturer -eq 'Unknown') { return $null }

    $m = $Manufacturer.Trim()

    # Surface detection: manufacturer is "Microsoft Corporation" on Surface
    # hardware, but the same manufacturer string appears on Hyper-V VMs.
    # The model prefix distinguishes the two. Only Surface hardware is
    # treated as a Surface deployment target; VMs fall through to the
    # presence-fallback or OEM_NAME override paths.
    # Anchor Surface detection on a word boundary rather than a start-of-string
    # match. Get-SystemModel returns the longest SMBIOS string, which on some
    # BIOS revisions is a prefixed form (e.g. "Microsoft Surface Pro 9"). A
    # start-of-string anchor would miss those; the manufacturer string alone
    # is not sufficient because Hyper-V VMs also report "Microsoft".
    if ($m -match '(?i)^Microsoft' -and $Model -match '(?i)\bSurface\b') { return 'Surface' }

    if ($m -match '(?i)^Dell')                   { return 'Dell' }
    if ($m -match '(?i)^HP\b|Hewlett-?Packard')  { return 'HP' }
    if ($m -match '(?i)^LENOVO')                 { return 'Lenovo' }
    if ($m -match '(?i)^ASUS|ASUSTeK')           { return 'ASUS' }
    if ($m -match '(?i)^Acer')                   { return 'Acer' }
    if ($m -match '(?i)^Micro-Star|^MSI')        { return 'MSI' }
    if ($m -match '(?i)^HUAWEI')                 { return 'Huawei' }
    if ($m -match '(?i)^Dynabook|^TOSHIBA')      { return 'Dynabook' }
    if ($m -match '(?i)^GIGABYTE')               { return 'Gigabyte' }
    if ($m -match '(?i)^Proline')                { return 'Proline' }

    return $null
}

function Get-AvailableOEMNames {
    param([string]$ScriptRoot)

    $oemDir      = Join-Path $ScriptRoot 'OEM'
    $manifestDir = Join-Path $ScriptRoot 'Manifests'

    if (-not (Test-Path $oemDir) -or -not (Test-Path $manifestDir)) { return @() }

    $fromModules = Get-ChildItem -Path $oemDir -Filter 'OEM.*.psm1' -File -ErrorAction SilentlyContinue |
        ForEach-Object { if ($_.BaseName -match '^OEM\.(.+)$') { $Matches[1] } }

    $fromManifests = Get-ChildItem -Path $manifestDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName }

    # Only names with both a module and a manifest are runnable.
    @($fromModules) | Where-Object { $_ -in $fromManifests } | Sort-Object -Unique
}

function Resolve-OEMSelection {
    param([string]$ScriptRoot)

    $manufacturer = Get-SystemManufacturer
    $modelForOEM  = Get-SystemModel
    $hardwareOEM  = Get-OEMFromManufacturer -Manufacturer $manufacturer -Model $modelForOEM
    $envOEM       = if ($env:OEM_NAME) { $env:OEM_NAME.Trim() } else { $null }
    $available    = @(Get-AvailableOEMNames -ScriptRoot $ScriptRoot)

    # 1. Explicit env override wins
    if ($envOEM) {
        if ($hardwareOEM -and $envOEM -ine $hardwareOEM) {
            throw "OEM_NAME is '$envOEM' but hardware manufacturer is '$manufacturer' (detected as '$hardwareOEM'). Refusing to run: the image does not match the hardware."
        }
        if (-not $hardwareOEM) {
            Write-Host "OEM_NAME override: '$envOEM'. Manufacturer '$manufacturer' is not recognized." -ForegroundColor Yellow
        }
        return $envOEM
    }

    # 2. Hardware detection
    if ($hardwareOEM) {
        Write-Host "OEM detected from hardware: $hardwareOEM (manufacturer: '$manufacturer')" -ForegroundColor Cyan
        return $hardwareOEM
    }

    # 3. Optional presence fallback (explicit opt-in only)
    $allowFallback = ($env:OEM_ALLOW_PRESENCE_FALLBACK -eq '1')
    if ($allowFallback) {
        if ($available.Count -eq 1) {
            Write-Host "OEM presence fallback: using '$($available[0])' (only OEM staged in this image; manufacturer '$manufacturer' is not recognized)." -ForegroundColor Yellow
            return $available[0]
        }
        if ($available.Count -gt 1) {
            Write-Host "OEM presence fallback requested but multiple OEMs are staged ($($available -join ', ')); cannot disambiguate." -ForegroundColor Yellow
        }
        if ($available.Count -eq 0) {
            Write-Host "OEM presence fallback requested but no OEM module/manifest pairs were found." -ForegroundColor Yellow
        }
    }

    # 4. Abort with diagnostic
    $presentList = if ($available.Count -gt 0) { $available -join ', ' } else { '(none)' }
    throw @"
Could not determine OEM.
  Manufacturer    : '$manufacturer'
  Detected as     : (unrecognized)
  OEMs staged here: $presentList
  OEM_NAME        : (not set)
  Presence fallback: $(if ($allowFallback) { 'allowed but unusable' } else { 'not allowed' })

To resolve:
  - If this is a fleet image with all OEMs present, verify Win32_ComputerSystem.Manufacturer returns a recognizable value, or set OEM_NAME explicitly.
  - If this is a per-OEM image and you want it to run regardless of manufacturer string, set OEM_ALLOW_PRESENCE_FALLBACK=1 and ensure exactly one OEM module/manifest pair is present.
  - To force a specific OEM, set OEM_NAME to one of: Dell, HP, Lenovo, ASUS, Acer, MSI, Huawei, Dynabook, Gigabyte, Proline, Surface.
"@
}

$frameworkPath = Join-Path $ScriptRoot 'Framework'
if (-not (Test-Path $frameworkPath)) {
    throw "Framework directory not found: $frameworkPath"
}

Get-ChildItem -Path $frameworkPath -Filter '*.psm1' -File |
    Sort-Object Name |
    ForEach-Object { Import-Module $_.FullName -Force -ErrorAction Stop -DisableNameChecking }

$oemName     = Resolve-OEMSelection -ScriptRoot $ScriptRoot
$oemModule   = Join-Path $ScriptRoot "OEM\OEM.$oemName.psm1"
$oemManifest = Join-Path $ScriptRoot "Manifests\$oemName.json"

if (-not (Test-Path $oemModule)) {
    throw "OEM module not found: $oemModule. Add OEM\OEM.$oemName.psm1 to this image."
}
if (-not (Test-Path $oemManifest)) {
    throw "OEM manifest not found: $oemManifest. Add Manifests\$oemName.json to this image."
}

Import-Module $oemModule -Force -ErrorAction Stop

$oemProfile = Get-OEMProfile -Name $oemName
if (-not $oemProfile) {
    throw "OEM profile unavailable for '$oemName'."
}

Start-OEMDeployment `
    -Profile      $oemProfile `
    -ManifestPath $oemManifest `
    -ScriptRoot   $ScriptRoot `
    -ScriptPath   $PSCommandPath `
    -Force:$Force
