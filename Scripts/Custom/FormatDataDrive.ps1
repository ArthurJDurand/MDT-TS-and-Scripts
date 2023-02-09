$DataDisk = Get-Disk | Where-Object PartitionStyle -Eq 'RAW' | Select Number

if (-not ([string]::IsNullOrWhiteSpace($DataDisk)))
{
    Get-Disk | Where-Object PartitionStyle -Eq 'RAW' | Initialize-Disk -PartitionStyle GPT -PassThru | Get-Partition | Remove-Partition -Confirm:$false
    Get-Disk -Number $DataDisk.Number | New-Partition -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | New-Partition -AssignDriveLetter -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data' -Confirm:$false
}
