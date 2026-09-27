<#
.SYNOPSIS
    Dynamically identifies optimal target OS disk for deployment prioritizing NVMe and SSD drives.

.DESCRIPTION
    Selects most suitable disk for operating system installation by evaluating storage media types,
    excluding USB drives, and prioritizing performance-oriented storage in specific order.

.NOTES
    - Prioritization order: NVMe SSDs > SATA SSDs > Non-SSD drives
    - Excludes USB drives from consideration using BusType property
    - Sets OSDDiskIndex environment variable for MDT deployment tasks
    - Requires administrative privileges and Microsoft.SMS.TSEnvironment COM access
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: DISK COLLECTION
# =========================================================

# Initialize OS Disk
$OSDisk = 0

# Get Physical Disks excluding USB drives
$PhysicalDisks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'USB' }

# =========================================================
# PHASE 2: STORAGE MEDIA CLASSIFICATION
# =========================================================

# Get SSDs, ensuring the output is an array
$SSDs = @( $PhysicalDisks | Where-Object { $_.MediaType -eq 'SSD' } )

# =========================================================
# PHASE 3: DISK SELECTION LOGIC
# =========================================================

# Set the first available NVMe or SATA SSD as the OS Disk
if ($SSDs.Count -gt 0) {
    $NVMeSSDs = @( $SSDs | Where-Object { $_.BusType -eq 'NVMe' } )
    if ($NVMeSSDs.Count -gt 0) {
        $OSDisk = $NVMeSSDs | Sort-Object -Property Size | Select-Object -First 1 -ExpandProperty DeviceID
    } else {
        $OSDisk = $SSDs | Sort-Object -Property Size | Select-Object -First 1 -ExpandProperty DeviceID
    }
} else {
    # Set the first available non-SSD drive as the OS Disk if no SSDs are found
    if ($PhysicalDisks.Count -gt 0) {
        $OSDisk = $PhysicalDisks | Sort-Object -Property Size | Select-Object -First 1 -ExpandProperty DeviceID
    } else {
        $OSDisk = 0
    }
}

# =========================================================
# PHASE 4: ENVIRONMENT VARIABLE SETTING
# =========================================================

# Set the OS Disk Index
(New-Object -COMObject Microsoft.SMS.TSEnvironment).Value('OSDDiskIndex') = $OSDisk

# =========================================================
# SCRIPT COMPLETION
# =========================================================
