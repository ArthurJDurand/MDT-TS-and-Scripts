<#
.SYNOPSIS
    Extracts OEM-specific driver packages during deployment.

.DESCRIPTION
    Dynamically identifies the system model and CPU vendor, then extracts the
    matching compressed driver archive using OEM-aware pattern matching.

.NOTES
    - WinPE‑safe: uses only the registry and file system; no WMI, CIM, or Storage module.
    - Designed for MDT or similar task sequence contexts.
    - No user interaction or console output.
    - Assumes 7-Zip is available at X:\Program Files\7-Zip\7z.exe or C:\Program Files\7-Zip\7z.exe.
#>

$script:CachedManufacturer = $null

# ============================================================
# FUNCTION: Get-IntelProcessorGeneration (WinPE‑safe, full support)
# ============================================================
function Get-IntelProcessorGeneration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CPUName
    )

    $SeriesMap = @{
        '1' = 14   # Series 1 (Meteor Lake / Raptor Lake Refresh U)
        '2' = 15   # Series 2 (Lunar Lake / Arrow Lake)
        '3' = 16   # Future Series 3
    }

    $Name = ($CPUName -replace '\s+', ' ').Trim()
    $Name = $Name -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
    $Name = ($Name -replace '\s+', ' ').Trim()

    # Non‑Intel bailout
    if ($Name -match '(?i)\bAMD\b')                   { return $null }
    if ($Name -notmatch '(?i)\bIntel\b')              { return $null }

    # 1. Explicit “Nth Gen” string
    if ($Name -match '(?i)\b(?<gen>1[1-9])(?:st|nd|rd|th)?\s+Gen\b') {
        $gen = [int]$Matches['gen']
        if ($gen -ge 11) { return $gen }
    }

    # 2. Xeon processors
    if ($Name -match '(?i)\bXeon\b.*?(\d{4,5})') {
        $model = $Matches[1]
        $gen = [int]$model.Substring(0,2)
        if ($gen -ge 11) { return $gen }
        return $null
    }

    # 3. Core Ultra
    if ($Name -match '(?i)\bCore\s+Ultra\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]
    }

    # 4. New Core (Core 3/5/7/9)
    if ($Name -match '(?i)\bCore\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]
    }

    # 5. Low‑end families without VMD support
    if ($Name -match '(?i)\b(?:Pentium|Celeron|Atom|[NJ]\d{2,4})\b') {
        return $null
    }

    # 6. Classic Core i
    if ($Name -match '(?i)\bi[3579][- ](?<model>\d{4,5})[A-Z0-9]*\b') {
        $model = $Matches['model']
        $len   = $model.Length
        if ($len -eq 5) {
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
        elseif ($len -eq 4) {
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
    }

    return $null
}

# =========================================================
# FUNCTION: Get-CPUVendor (WinPE‑safe – registry)
# =========================================================
function Get-CPUVendor {
    $vendor = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue).VendorIdentifier
    if ($vendor -match 'GenuineIntel') { return "Intel" }
    if ($vendor -match 'AuthenticAMD') { return "AMD" }
    return "Unknown"
}

# =========================================================
# FUNCTION: Get-OSFamily (placeholder – adapt to your environment)
# =========================================================
function Get-OSFamily {
    # You can detect from task sequence variables or offline registry here.
    # For simplicity, we return "Win11" as a default.
    return "Win11"
}

# =========================================================
# FUNCTION: Get-Manufacturer (WinPE‑safe – registry)
# =========================================================
function Get-Manufacturer {
    if ($script:CachedManufacturer) {
        return $script:CachedManufacturer
    }

    $InvalidValues = 'Default string', 'Not Applicable', 'Not Available', 'System Manufacturer', 'To be filled by O.E.M.'
    $Values = @()

    $biosKey = 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    $props = @('SystemManufacturer', 'BaseBoardManufacturer')
    foreach ($prop in $props) {
        $val = (Get-ItemProperty $biosKey -Name $prop -ErrorAction SilentlyContinue).$prop
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $Values += $val.Trim()
        }
    }
    $Values = $Values | Where-Object { $_ -notin $InvalidValues }

    if (-not $Values) {
        $script:CachedManufacturer = 'Unknown'
        return 'Unknown'
    }

    $Manufacturer = $Values |
        Group-Object |
        Sort-Object @{Expression={$_.Count};Descending=$true}, @{Expression={$_.Name};Descending=$false} |
        Select-Object -First 1 -ExpandProperty Name

    $script:CachedManufacturer = $Manufacturer
    return $Manufacturer
}

# =========================================================
# FUNCTION: Get-Model (WinPE‑safe – registry)
# =========================================================
function Get-Model {
    param([switch]$ForceManufacturerRefresh)

    if ($ForceManufacturerRefresh) {
        $script:CachedManufacturer = $null
    }

    $InvalidValues = @(
        'Default string', 'Not Applicable', 'Not Available',
        'System Product Name', 'System Version',
        'To be filled by O.E.M.', 'Type1ProductConfigId'
    )

    $biosKey = 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    $props = @('SystemProductName', 'SystemVersion', 'BaseBoardProduct')
    $Values = @()

    foreach ($prop in $props) {
        $val = (Get-ItemProperty $biosKey -Name $prop -ErrorAction SilentlyContinue).$prop
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $Values += $val.Trim()
        }
    }
    $Values = $Values | Where-Object { $_ -notin $InvalidValues }

    if (-not $Values -or $Values.Count -eq 0) {
        return $null
    }

    if ($Values.Count -gt 1) {
        $Manufacturer = Get-Manufacturer

        if ($Manufacturer -like '*Lenovo*') {
            $lenovoPattern = '^(IdeaPad|Legion|Lenovo|LOQ|ThinkBook|ThinkCentre|ThinkPad|Yoga)[\s\d\-]'
            $Model = $Values | Where-Object { $_ -match $lenovoPattern } | Select-Object -First 1
            if ($Model) { return $Model }
        }
        elseif ($Manufacturer -like '*Acer*') {
            $acerPattern = '^(Aspire|Extensa|Predator|Nitro|Swift|TravelMate|Spin|ConceptD|Acer|Veriton|Vero|One)[\s\d\-]'
            $excludeSuffixPattern = '_(ADU|BDS|BDN|BDZ|DEV|INT|SKU)$'
            $Model = $Values | Where-Object { $_ -match $acerPattern -and -not ($_ -match $excludeSuffixPattern) } | Select-Object -First 1
            if ($Model) { return $Model }
        }
    }

    return $Values | Sort-Object @{Expression = { $_.Length }; Descending = $true }, @{Expression = { $_ }; Descending = $false } | Select-Object -First 1
}

# =========================================================
# FUNCTION: Get-SourceDriverPath (WinPE‑safe)
# =========================================================
function Get-SourceDriverPath {
    # Primary network path
    $PrimaryPath = "\\SERVER\Shared\DriverPacks"
    if (Test-Path $PrimaryPath) {
        return $PrimaryPath
    }

    # Fallback: search all local drives for a "DriverPacks" folder
    foreach ($drive in Get-PSDrive -PSProvider FileSystem | Sort-Object Name) {
        $candidate = Join-Path $drive.Root "DriverPacks"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

# =========================================================
# Helper: Get Windows drive (WinPE‑safe)
# =========================================================
function Get-WindowsImagePath {
    $tsDrive = $null
    try {
        $ts = New-Object -ComObject Microsoft.SMS.TSEnvironment
        $tsDrive = $ts.Value('OSDTargetSystemDrive')
    } catch {}

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($tsDrive) {
        $null = $candidates.Add(($tsDrive.TrimEnd('\') + '\'))
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem | Sort-Object Name) {
        $null = $candidates.Add($drive.Root)
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $normalized = ($candidate.TrimEnd('\') + '\').ToUpperInvariant()
        if ($seen.ContainsKey($normalized)) { continue }
        $seen[$normalized] = $true
        if ($normalized -eq 'X:\') { continue }

        if (Test-Path (Join-Path $candidate 'Windows\System32\Config\SOFTWARE')) {
            return ($candidate.TrimEnd('\') + '\')
        }
    }
    return $null
}

# =========================================================
# Normalization helpers (unchanged from original)
# =========================================================
function Normalize-ModelString {
    param([string]$s)
    if (-not $s) { return $null }
    return ($s -replace '\s+', ' ').Trim()
}

function Get-TruncatedModel {
    param([string]$Model, [bool]$IsHP)
    if (-not $Model) { return $null }

    $ModelNorm = Normalize-ModelString $Model

    if ($IsHP -and $ModelNorm -match '^(HP\s+\w+\s+\d+)') {
        $baseModel = $Matches[1]
        if ($ModelNorm -match 'G\d+') {
            $gen = $Matches[0]
            return "$baseModel $gen"
        }
        return $baseModel
    }

    $suffixes = @(
        'Notebook PC','Notebook','Desktop','Tower','All-in-One','All in One',
        'Convertible','Tablet','Workstation','Microtower','Small Form Factor',
        'SFF','Mini','Mobile','Chassis','Laptop'
    )

    $words = $ModelNorm -split ' '
    if ($words.Count -le 3) { return $ModelNorm }

    foreach ($suf in $suffixes | Sort-Object Length -Descending) {
        if ($ModelNorm -match ("(?i)\b" + [regex]::Escape($suf) + "$")) {
            $candidate = $ModelNorm -replace ("(?i)\s*" + [regex]::Escape($suf) + "$"), ''
            $candidate = Normalize-ModelString $candidate
            if ($candidate -and ($candidate -split ' ').Count -ge 3) { return $candidate }
        }
    }

    return $ModelNorm
}

function Get-GenVariants {
    param([int]$Gen)
    if (-not $Gen) { return @() }
    $variants = @(
        "${Gen}th Gen Intel",
        "${Gen}th Gen",
        "Gen ${Gen}",
        "Gen${Gen}",
        "${Gen} Gen Intel",
        "${Gen} Gen",
        "Intel ${Gen}th Gen"
    )
    return ($variants | ForEach-Object { $_.Trim() } | Select-Object -Unique)
}

function Get-HPSimplifiedModel {
    param([string]$Model)
    if (-not $Model) { return $null }
    if ($Model -match '^(HP\s+(\w+)\s+(\d+))') {
        $base = $Matches[1]
        if ($Model -match '\b(G\d+)\b') {
            $gen = $Matches[1]
            return "$base $gen"
        }
        return $base
    }
    return $Model
}

# =========================================================
# MAIN EXECUTION
# =========================================================

# Locate Windows drive
$WindowsRoot = Get-WindowsImagePath
if (-not $WindowsRoot) { exit }

# Locate source driver storage
$SourceDriverPath = Get-SourceDriverPath
if (-not $SourceDriverPath) { exit }

# Gather hardware info – all registry‑based
$CPUName = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue).ProcessorNameString
$Gen = Get-IntelProcessorGeneration -CPUName $CPUName
$CPUVendor = Get-CPUVendor
$OSFamily = Get-OSFamily

$Model = Normalize-ModelString (Get-Model)
$Manufacturer = Get-Manufacturer
$IsHP = $Manufacturer -match 'HP|Hewlett-Packard'
$IsLenovo = $Manufacturer -match 'Lenovo'

$HPSimplifiedModel = if ($IsHP) { Get-HPSimplifiedModel -Model $Model } else { $null }
$ShortModel = Get-TruncatedModel -Model $Model -IsHP:$IsHP

# Build search patterns (priority order)
$patterns = @()

if ($Gen) {
    foreach ($gv in (Get-GenVariants $Gen)) {
        if ($IsHP) {
            $patterns += "*$Model*$gv*"
            $patterns += "*$Model* $gv*"
            if ($HPSimplifiedModel) {
                $patterns += "*$HPSimplifiedModel*$gv*"
                $patterns += "*$HPSimplifiedModel* $gv*"
            }
        }
        else {
            $patterns += "*$Model*$gv*"
            $patterns += "*$Model* $gv*"
        }
    }
}

if ($IsHP) {
    $patterns += "*$Model*"
    if ($HPSimplifiedModel) {
        $patterns += "*$HPSimplifiedModel*"
    }
} else {
    $patterns += "*$Model*"
}

if ($ShortModel -and $ShortModel -ne $Model) {
    $patterns += "*$ShortModel*"
}

# Remove duplicates while preserving order
$seen = @{}
$orderedPatterns = @()
foreach ($p in $patterns) {
    if (-not $seen.ContainsKey($p)) {
        $orderedPatterns += $p
        $seen[$p] = $true
    }
}

# Dynamic search path
$SearchBasePath = Join-Path $SourceDriverPath "$OSFamily\$CPUVendor"
if (-not (Test-Path $SearchBasePath)) {
    $SearchBasePath = Join-Path $SourceDriverPath "$OSFamily"
}

# Locate matching archive
$Archives = Get-ChildItem -Path $SearchBasePath -Filter "*.7z" -File -Recurse -ErrorAction SilentlyContinue
$MatchingDriverPack = $null

foreach ($pat in $orderedPatterns) {
    $Candidates = $Archives | Where-Object { $_.Name -like $pat }
    if ($Candidates -and $Candidates.Count -gt 0) {
        $MatchingDriverPack = $Candidates | Sort-Object @{Expression={ $_.Name.Length }; Descending=$true}, @{Expression={ $_.Length }; Descending=$true} | Select-Object -First 1
        if ($MatchingDriverPack) { break }
    }
}

# Extraction target
$DestinationDriverPath = Join-Path -Path $WindowsRoot -ChildPath "Recovery\OEM\Drivers"

if ($MatchingDriverPack -and $DestinationDriverPath) {
    if (-not (Test-Path $DestinationDriverPath)) {
        New-Item -Path $DestinationDriverPath -ItemType Directory -Force | Out-Null
    }

    $SevenZipCandidates = @(
        "X:\Program Files\7-Zip\7z.exe",
        "C:\Program Files\7-Zip\7z.exe"
    )
    $SevenZip = $SevenZipCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($SevenZip) {
        $maxAttempts = 3
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            & $SevenZip x -o"$DestinationDriverPath" "$($MatchingDriverPack.FullName)" -y
            if ($LASTEXITCODE -eq 0) { break }
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2 }
        }
    }
}

# SCRIPT COMPLETION
