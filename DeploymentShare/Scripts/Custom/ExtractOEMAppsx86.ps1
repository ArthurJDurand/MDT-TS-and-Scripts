<#
.SYNOPSIS
    Extracts OEM-specific applications for 32-bit systems into recovery directory during deployment.

.DESCRIPTION
    Dynamically identifies system manufacturer and extracts corresponding OEM application packages
    from network share or deployment media to Windows recovery directory. Supports major OEM vendors.

.NOTES
    - Requires 7-Zip installed at X:\Program Files\7-Zip\7z.exe
    - Supports network share (\\SERVER\Shared\OEM\x86) and deployment media fallback
    - Handles multiple manufacturer detection methods with invalid value filtering
#>

# =========================================================
# FUNCTION: Get-Manufacturer
# =========================================================
function Get-Manufacturer {
    if ($script:CachedManufacturer) {
        return $script:CachedManufacturer
    }

    $InvalidValues = 'Default string', 'Not Applicable', 'Not Available', 'System Manufacturer', 'To be filled by O.E.M.'

    $Values = @(
        (Get-CimInstance Win32_BaseBoard).Manufacturer,
        (Get-CimInstance Win32_ComputerSystem).Manufacturer,
        (Get-CimInstance Win32_ComputerSystemProduct).Vendor
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notin $InvalidValues }

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
# FUNCTION: Get-SourceOEMAppPath
# =========================================================
function Get-SourceOEMAppPath {
    $PrimaryPath = "\\SERVER\Shared\OEM\x86"
    
    if (Test-Path $PrimaryPath) {
        return $PrimaryPath
    } else {
        $USBDrive = Get-Volume -FileSystemLabel 'DEPLOY' | Select-Object -First 1
        if ($USBDrive) {
            $USBPath = Join-Path -Path ($USBDrive.DriveLetter + ":") -ChildPath "OEM\x86"
            if (Test-Path $USBPath) {
                return $USBPath
            }
        }
    }

    return $null
}

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: SYSTEM DETECTION
# =========================================================

# Retrieve the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter | Select-Object -First 1

# =========================================================
# PHASE 2: SOURCE PATH RESOLUTION
# =========================================================

# Define the source path for OEM apps
$SourceOEMAppPath = Get-SourceOEMAppPath

# =========================================================
# PHASE 3: DESTINATION SETUP
# =========================================================

if ($WindowsDriveLetter) {
    $DestinationOEMApps = Join-Path -Path "${WindowsDriveLetter}:\" -ChildPath "Recovery\OEM"

    # Create the destination directory if it doesn't exist
    if (-not (Test-Path $DestinationOEMApps)) {
        New-Item $DestinationOEMApps -ItemType Directory -Force | Out-Null
    }

    # =========================================================
    # PHASE 4: MANUFACTURER DETECTION
    # =========================================================

    # Retrieve system manufacturer information
    $Manufacturer = Get-Manufacturer

    # =========================================================
    # PHASE 5: OEM APP SELECTION
    # =========================================================

    # Determine the appropriate OEM apps based on the manufacturer
    $SourceOEMApps = switch -Wildcard ($Manufacturer) {
        {$_ -like '*Acer*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Acer.7z" }
        {$_ -like '*ASUS*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "ASUS.7z" }
        {$_ -like '*Dell*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Dell.7z" }
        {$_ -like '*Dynabook*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Dynabook.7z" }
        {$_ -like '*Gigabyte*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Gigabyte.7z" }
        {$_ -like '*HP*' -or $_ -like '*Hewlett Packard*' -or $_ -like '*Hewlett-Packard*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "HP.7z" }
        {$_ -like '*Huawei*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Huawei.7z" }
        {$_ -like '*Lenovo*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Lenovo.7z" }
        {$_ -like '*Microsoft*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Microsoft.7z" }
        {$_ -like '*Micro-Star*' -or $_ -like '*MicroStar*' -or $_ -like '*MSI*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "MSI.7z" }
        {$_ -like '*Proline*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Proline.7z" }
        default { $null }
    }

    # =========================================================
    # PHASE 6: EXTRACTION PROCESS
    # =========================================================

    # Extract the appropriate OEM apps to the destination if both exist
    if ((Test-Path $SourceOEMApps) -and (Test-Path $DestinationOEMApps)) {
        $7Zip = "X:\Program Files\7-Zip\7z.exe"
        if (Test-Path $7Zip) {
            do {
                & $7Zip x -o"$DestinationOEMApps" $SourceOEMApps -y
            } while ($LASTEXITCODE -ne 0)
        }
    }
}

# =========================================================
# SCRIPT COMPLETION
# =========================================================
