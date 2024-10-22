# Check if a raw data disk is present
$DataDisk = Get-Disk | Where-Object PartitionStyle -Eq 'RAW' | Select-Object -ExpandProperty Number

# If a raw data disk is present, partition and format the disk, then assign a drive letter
if (-not [string]::IsNullOrWhiteSpace($DataDisk)) {
    Get-Disk -Number $DataDisk | Initialize-Disk -PartitionStyle GPT -PassThru | Get-Partition | Remove-Partition -Confirm:$false
    Get-Disk -Number $DataDisk | New-Partition -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    Get-Disk -Number $DataDisk | New-Partition -AssignDriveLetter -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data' -Confirm:$false
}
