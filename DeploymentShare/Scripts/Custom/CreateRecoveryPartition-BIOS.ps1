<#
.SYNOPSIS
    Creates Recovery partition on BIOS-based systems by shrinking Windows partition.

.DESCRIPTION
    Automates recovery partition creation for BIOS systems by shrinking existing Windows partition,
    creating new primary partition formatted as NTFS with recovery ID, and assigning Recovery label.

.NOTES
    - Designed for BIOS-based systems only (not UEFI)
    - Requires minimum 1GB free space on Windows partition for shrinkage
    - Sets partition ID to 27 (recovery partition type)
    - Uses DiskPart for reliable partition operations
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: HARDWARE DETECTION
# =========================================================

# Get system disk information
$OSDiskNumber = (Get-Disk | Where-Object { $_.BootFromDisk -eq $true }).Number
$OSPartitionNumber = (Get-Partition | Where-Object { $_.DriveLetter -eq (Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Windows' }).DriveLetter }).PartitionNumber

# =========================================================
# PHASE 2: PARTITION OPERATIONS
# =========================================================

# Shrink the Windows partition if present and create a recovery partition
if ($OSPartitionNumber) {
    $Commands = @(
        "select disk $OSDiskNumber",
        "select partition $OSPartitionNumber", 
        "shrink minimum=1000",
        "create partition primary",
        "format quick fs=ntfs label=Recovery",
        "set id=27"
    )

    # =========================================================
    # PHASE 3: DISKPART SCRIPT GENERATION
    # =========================================================

    $Script = $Commands -join "`r`n"
    $TempFile = [System.IO.Path]::GetTempFileName()
    $TempFile = [System.IO.Path]::ChangeExtension($TempFile, ".txt")
    [System.IO.File]::WriteAllText($TempFile, $Script)

    # =========================================================
    # PHASE 4: PARTITION EXECUTION
    # =========================================================

    & diskpart /s $TempFile

    # =========================================================
    # PHASE 5: CLEANUP
    # =========================================================

    Remove-Item $TempFile -ErrorAction SilentlyContinue
}

# =========================================================
# SCRIPT COMPLETION
# =========================================================
