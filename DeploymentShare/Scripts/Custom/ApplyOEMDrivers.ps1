<#
.SYNOPSIS
    Applies OEM, WLAN, and storage drivers to an offline Windows image during MDT deployment.

.DESCRIPTION
    Dynamically applies drivers based on system model, using intelligent folder matching
    and architecture-specific storage driver selection. Prevents BSOD on newer Intel
    systems by applying the correct VMD storage drivers for 11th Gen+ processors.

.CRITICAL REQUIREMENTS
    - Must run in a WinPE environment during an MDT task sequence
    - Windows OS drive must be labeled "Windows" or be the drive containing Windows\System32\Config\SOFTWARE
    - Drivers must be pre-extracted to Recovery\OEM\Drivers\
    - Intel VMD storage drivers are required for 11th Gen+ Intel systems

.OPERATIONAL NOTES
    - WinPE‑safe – uses only registry and file system; no WMI, CIM, or Storage module
    - Silent operation (no console output except errors)
    - Automatic retry logic for DISM operations (3 attempts)
    - Supports Dell, HP, Lenovo, Acer, and other model variations
#>

$script:CachedManufacturer = $null

# =========================================================
# FUNCTION: Get-ProcessorArchitecture
# =========================================================
function Get-ProcessorArchitecture {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$CPUName)

    try {
        $Name = ($CPUName -replace '\s+', ' ').Trim()

        # AMD Detection
        if ($Name -match '(?i)\bAMD\b') {
            if ($Name -match '(?i)Ryzen[\s-]*(\d)\s*(\d{4})[A-Z]*') {
                $Series = $Matches[2].Substring(0, 1) + "xxx"
                return @{
                    Brand = "AMD"
                    Series = "Ryzen $($Matches[1]) $Series"
                    Generation = $Matches[2].Substring(0, 1)
                    SimpleName = "AMD Ryzen $($Matches[1])"
                }
            }
            elseif ($Name -match '(?i)Ryzen[\s-]*([3579])[\s-]*(\d{4})[A-Z]*') {
                return @{
                    Brand = "AMD"
                    Series = "Ryzen $($Matches[1]) $($Matches[2])"
                    Generation = $Matches[2].Substring(0, 1)
                    SimpleName = "AMD Ryzen $($Matches[1])"
                }
            }
            elseif ($Name -match '(?i)Ryzen[\s-]*([3579])') {
                return @{
                    Brand = "AMD"
                    Series = "Ryzen $($Matches[1])"
                    Generation = $null
                    SimpleName = "AMD Ryzen $($Matches[1])"
                }
            }
            else {
                return @{
                    Brand = "AMD"
                    Series = "AMD"
                    Generation = $null
                    SimpleName = "AMD"
                }
            }
        }

        # Intel Detection
        if ($Name -match '(?i)\bIntel\b') {
            $Gen = Get-IntelProcessorGeneration -CPUName $CPUName

            # For Core N-series, use series detection instead of generation
            if ($Name -match '(?i)\b(N\d{3}[A-Z]*)\b') {
                return @{
                    Brand = "Intel"
                    Series = $Matches[1]
                    Generation = $null
                    SimpleName = "Intel $($Matches[1])"
                }
            }

            if ($Gen) {
                $SeriesString = $Gen.ToString() + "th Gen"
                $SimpleNameString = "Intel " + $Gen.ToString() + "th Gen"
            } else {
                $SeriesString = "Intel"
                $SimpleNameString = "Intel"
            }

            return @{
                Brand = "Intel"
                Series = $SeriesString
                Generation = $Gen
                SimpleName = $SimpleNameString
            }
        }

        return @{
            Brand = "Unknown"
            Series = "Unknown"
            Generation = $null
            SimpleName = "Unknown"
        }
    } catch {
        return @{
            Brand = "Unknown"
            Series = "Unknown"
            Generation = $null
            SimpleName = "Unknown"
        }
    }
}

# ============================================================
# FUNCTION: Get-IntelProcessorGeneration (WinPE‑safe, full Xeon/Core Ultra support)
# ============================================================
function Get-IntelProcessorGeneration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CPUName
    )

    # Series → generation mapping table (future‑proof; only update this)
    $SeriesMap = @{
        '1' = 14   # Series 1 (Meteor Lake / Raptor Lake Refresh U)
        '2' = 15   # Series 2 (Lunar Lake / Arrow Lake)
        '3' = 16   # Future Series 3
    }

    # Normalise the input (remove trademarks, extra spaces, etc.)
    $Name = ($CPUName -replace '\s+', ' ').Trim()
    $Name = $Name -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
    $Name = ($Name -replace '\s+', ' ').Trim()

    # --- 1. Non‑Intel early bailout ---
    if ($Name -match '(?i)\bAMD\b')                   { return $null }
    if ($Name -notmatch '(?i)\bIntel\b')              { return $null }

    # --- 2. Explicit “Nth Gen” string (highest confidence) ---
    if ($Name -match '(?i)\b(?<gen>1[1-9])(?:st|nd|rd|th)?\s+Gen\b') {
        $gen = [int]$Matches['gen']
        if ($gen -ge 11) { return $gen }
    }

    # --- 3. Xeon processors (W/E series, Gold, etc.) ---
    if ($Name -match '(?i)\bXeon\b.*?(\d{4,5})') {
        $model = $Matches[1]
        $gen = [int]$model.Substring(0,2)
        if ($gen -ge 11) { return $gen }
        return $null   # Xeon, but too old for VMD
    }

    # --- 4. Core Ultra (Series mapping) ---
    if ($Name -match '(?i)\bCore\s+Ultra\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]  # $null if not mapped
    }

    # --- 5. New Core (Core 3 / 5 / 7 / 9, no ‘i’) ---
    if ($Name -match '(?i)\bCore\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]
    }

    # --- 6. Low‑end families that don't support VMD (exclude before Classic Core) ---
    if ($Name -match '(?i)\b(?:Pentium|Celeron|Atom|[NJ]\d{2,4})\b') {
        return $null
    }

    # --- 7. Classic Core i (i3 / i5 / i7 / i9) ---
    if ($Name -match '(?i)\bi[3579][- ](?<model>\d{4,5})[A-Z0-9]*\b') {
        $model = $Matches['model']
        $len   = $model.Length

        if ($len -eq 5) {
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
        elseif ($len -eq 4) {
            # Mobile 11th Gen+ (no artificial upper limit)
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
    }

    return $null
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
# FUNCTION: Find-BestDriverFolder
# =========================================================
function Find-BestDriverFolder {
    param(
        [string]$Model,
        [string]$DriversRoot,
        [string]$Manufacturer,
        [hashtable]$ProcessorInfo
    )

    try {
        $IsHP = $Manufacturer -match 'HP|Hewlett-Packard'
        $IsLenovo = $Manufacturer -match 'Lenovo'

        $Model = ($Model -replace '\s+', ' ').Trim()
        $candidateFolders = @()

        # Tier 1: Model + Architecture details
        if ($ProcessorInfo.Brand -eq "Intel" -and $ProcessorInfo.Generation) {
            $candidateFolders += "$Model $($ProcessorInfo.Series) Intel"
            $candidateFolders += "$Model $($ProcessorInfo.Series)"
        }
        elseif ($ProcessorInfo.Brand -eq "AMD" -and $ProcessorInfo.SimpleName -ne "AMD") {
            $candidateFolders += "$Model $($ProcessorInfo.SimpleName)"
        }

        # Tier 2: Exact model match
        $candidateFolders += $Model

        # Tier 3: HP "Notebook PC" variations
        if ($IsHP) {
            if ($Model -notmatch 'Notebook PC' -and $Model -match '^\w+ \w+ \d+ [A-Z]\d+$') {
                $candidateFolders += "$Model Notebook PC"
                if ($ProcessorInfo.Brand -eq "Intel" -and $ProcessorInfo.Generation) {
                    $candidateFolders += "$Model Notebook PC $($ProcessorInfo.Series) Intel"
                }
            }
            elseif ($Model -match 'Notebook PC') {
                $shortModel = $Model -replace ' Notebook PC', ''
                $candidateFolders += $shortModel
                if ($ProcessorInfo.Brand -eq "Intel" -and $ProcessorInfo.Generation) {
                    $candidateFolders += "$shortModel $($ProcessorInfo.Series) Intel"
                }
            }
        }

        # Tier 4: Lenovo base model matching
        if ($IsLenovo) {
            $baseModel = Get-LenovoBaseModel -Model $Model
            if ($baseModel -and $baseModel -ne $Model) {
                $candidateFolders += $baseModel
                if ($ProcessorInfo.Brand -eq "Intel" -and $ProcessorInfo.Generation) {
                    $candidateFolders += "$baseModel $($ProcessorInfo.Series) Intel"
                }
            }
        }

        # Remove duplicates and try each candidate
        $candidateFolders = $candidateFolders | Sort-Object -Unique

        foreach ($folderName in $candidateFolders) {
            $folderPath = Join-Path -Path $DriversRoot -ChildPath $folderName
            if (Test-Path $folderPath) {
                return $folderPath
            }
        }

        return $null
    } catch {
        return $null
    }
}

# =========================================================
# FUNCTION: Get-LenovoBaseModel
# =========================================================
function Get-LenovoBaseModel {
    param([string]$Model)

    try {
        if (-not $Model) { return $null }

        if ($Model -match '^(IdeaPad|Legion|ThinkPad|ThinkBook|Yoga|LOQ)\s+(.+?)(?:\s+[\dA-Z]+)?$') {
            $base = $Matches[0]
            $base = $base -replace '\s+\d+[A-Z]*\d*$', ''
            return $base.Trim()
        }

        return $Model
    } catch {
        return $Model
    }
}

# =========================================================
# FUNCTION: Get-IntelVMDVersion
# =========================================================
function Get-IntelVMDVersion {
    param([int]$Generation)

    try {
        if (-not $Generation) { return $null }

        switch ($Generation) {
            { $_ -ge 12 } { return "20.2.6.1025.3" }
            11 { return "19.5.8.1059.2" }
            default { return $null }
        }
    } catch {
        return $null
    }
}

# =========================================================
# FUNCTION: Invoke-DISMWithRetry
# =========================================================
function Invoke-DISMWithRetry {
    param(
        [string]$ImagePath,
        [string]$DriverPath,
        [string]$OperationName
    )

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            # Redirect all output to $null for silent operation
            & DISM.exe /Image:"$ImagePath" /Add-Driver /Driver:"$DriverPath" /Recurse > $null 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $true
            }

            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 5
            }
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 5
            }
        }
    }
    return $false
}

# =========================================================
# FUNCTION: Get-WindowsImagePath (WinPE‑safe)
# =========================================================
function Get-WindowsImagePath {
    # First try the task sequence variable OSDTargetSystemDrive (MDT)
    $tsDrive = $null
    try {
        $ts = New-Object -ComObject Microsoft.SMS.TSEnvironment
        $tsDrive = $ts.Value('OSDTargetSystemDrive')
    } catch {}

    $candidates = New-Object 'System.Collections.Generic.List[string]'

    if ($tsDrive) {
        $null = $candidates.Add(($tsDrive.TrimEnd('\') + '\'))
    }

    # Scan all filesystem drives for a Windows installation
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

        # Check for Windows\System32\Config\SOFTWARE
        if (Test-Path (Join-Path $candidate 'Windows\System32\Config\SOFTWARE')) {
            return ($candidate.TrimEnd('\') + '\')
        }
    }

    return $null
}

# =========================================================
# MAIN EXECUTION
# =========================================================

$WindowsImage = Get-WindowsImagePath

if ($WindowsImage) {
    $Drivers = Join-Path -Path $WindowsImage -ChildPath "Recovery\OEM\Drivers"

    if (Test-Path $Drivers) {
        # Get hardware info – WinPE‑safe via registry
        $RegKey = 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
        $CPUName = (Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue).ProcessorNameString

        if ($CPUName) {
            $ProcessorInfo = Get-ProcessorArchitecture -CPUName $CPUName
            $Model = Get-Model
            $Manufacturer = Get-Manufacturer

            # Apply OEM drivers if found
            if ($Model) {
                $OEMDrivers = Find-BestDriverFolder -Model $Model -DriversRoot $Drivers -Manufacturer $Manufacturer -ProcessorInfo $ProcessorInfo
                if ($OEMDrivers -and (Test-Path $OEMDrivers)) {
                    Invoke-DISMWithRetry -ImagePath $WindowsImage -DriverPath $OEMDrivers -OperationName "OEM Drivers"
                }
            }

            # Apply WLAN drivers if found
            $WLANDrivers = Join-Path -Path $Drivers -ChildPath "WLAN"
            if (Test-Path $WLANDrivers) {
                Invoke-DISMWithRetry -ImagePath $WindowsImage -DriverPath $WLANDrivers -OperationName "WLAN Drivers"
            }

            # Apply Intel VMD drivers if found
            if ($ProcessorInfo.Brand -eq "Intel" -and $ProcessorInfo.Generation) {
                $IntelVMDVersion = Get-IntelVMDVersion -Generation $ProcessorInfo.Generation
                if ($IntelVMDVersion) {
                    $IntelVMDDrivers = Join-Path -Path $Drivers -ChildPath "Storage\Intel\$IntelVMDVersion"
                    if (Test-Path $IntelVMDDrivers) {
                        Invoke-DISMWithRetry -ImagePath $WindowsImage -DriverPath $IntelVMDDrivers -OperationName "Intel VMD Storage Drivers"
                    }
                }
            }
        }
    }
}

# SCRIPT COMPLETION
