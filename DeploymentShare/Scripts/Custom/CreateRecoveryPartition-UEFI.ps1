<#
.SYNOPSIS
    Creates Recovery partition on UEFI-based systems by shrinking Windows partition.

.DESCRIPTION
    Automates recovery partition creation for UEFI systems by shrinking existing Windows partition,
    creating new primary partition formatted as NTFS with recovery GUID, and setting GPT attributes
    for partition protection.

.NOTES
    - Designed for UEFI-based systems only (not BIOS)
    - Requires minimum 1GB free space on Windows partition for shrinkage
    - Sets partition GUID to de94bba4-06d1-4d40-a16a-bfd50179d6ac (Windows Recovery Environment)
    - Configures GPT attributes to protect partition from accidental modification
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
        "set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac",
        "gpt attributes=0x8000000000000001"
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
