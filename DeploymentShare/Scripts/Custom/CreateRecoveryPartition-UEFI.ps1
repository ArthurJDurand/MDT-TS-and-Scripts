# Function to execute diskpart commands
function Invoke-DiskpartCommand {
    param (
        [string[]]$Commands
    )

    $Script = $Commands -join "`r`n"
    $TempFile = [System.IO.Path]::GetTempFileName()
    $TempFile = [System.IO.Path]::ChangeExtension($TempFile, ".txt")
    [System.IO.File]::WriteAllText($TempFile, $Script)
    & diskpart /s $TempFile
    Remove-Item $TempFile
}

# Get system disk information
$OSDiskNumber = (Get-Disk | Where-Object { $_.BootFromDisk -eq $true }).Number
$OSPartitionNumber = (Get-Partition | Where-Object { $_.DriveLetter -eq (Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Windows' }).DriveLetter }).PartitionNumber

# Shrink the WIndows partition if present and create a recovery partition
if ($OSPartitionNumber) {
    Invoke-DiskpartCommand @("
        select disk $OSDiskNumber
        select partition $OSPartitionNumber
        shrink minimum=1000
        create partition primary
        format quick fs=ntfs label=Recovery
        set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac
        gpt attributes=0x8000000000000001
    ")
}
