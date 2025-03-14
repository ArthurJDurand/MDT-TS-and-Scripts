# Initialize OS Disk
$OSDisk = 0

# Get Physical Disks excluding USB drives
$PhysicalDisks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'USB' }

# Get SSDs, ensuring the output is an array
$SSDs = @( $PhysicalDisks | Where-Object { $_.MediaType -eq 'SSD' } )

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

# Set the OS Disk Index
(New-Object -COMObject Microsoft.SMS.TSEnvironment).Value('OSDDiskIndex') = $OSDisk
