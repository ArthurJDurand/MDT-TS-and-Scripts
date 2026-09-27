<#
.SYNOPSIS
    Formats raw data disks with GPT partition style and creates formatted data partitions.

.DESCRIPTION
    Identifies unformatted disks, initializes them with GPT partition style, creates system
    and data partitions with specific GPT type GUIDs, and formats data partition with NTFS.

.NOTES
    - Targets raw (unformatted) disks only
    - Creates two partitions: 128MB system partition and primary data partition
    - Uses GPT type GUIDs for proper partition identification
    - Requires administrative privileges for disk operations
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: RAW DISK DETECTION
# =========================================================

# Check if a raw data disk is present
$DataDisk = Get-Disk | Where-Object PartitionStyle -Eq 'RAW' | Select-Object -ExpandProperty Number

# =========================================================
# PHASE 2: DISK INITIALIZATION
# =========================================================

# If a raw data disk is present, partition and format the disk, then assign a drive letter
if (-not [string]::IsNullOrWhiteSpace($DataDisk)) {
    # Initialize disk with GPT partition style and remove any existing partitions
    Get-Disk -Number $DataDisk | Initialize-Disk -PartitionStyle GPT -PassThru | Get-Partition | Remove-Partition -Confirm:$false

    # =========================================================
    # PHASE 3: PARTITION CREATION
    # =========================================================

    # Create 128MB system partition with specific GPT type
    Get-Disk -Number $DataDisk | New-Partition -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'

    # =========================================================
    # PHASE 4: DATA PARTITION SETUP
    # =========================================================

    # Create primary data partition using maximum available space
    Get-Disk -Number $DataDisk | New-Partition -AssignDriveLetter -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data' -Confirm:$false
}

# =========================================================
# SCRIPT COMPLETION
# =========================================================
