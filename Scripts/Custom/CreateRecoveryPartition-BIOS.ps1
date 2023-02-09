$OSDiskNumber = Get-Volume | Where {$_.FileSystemLabel -eq "Windows"} | Get-Partition | Get-Disk | Select Number

If (0 -eq ($OSDiskNumber.Number))
{
    diskpart /s $env:SCRIPTROOT\Custom\RecoveryPartition-BIOS.txt
}

If (1 -eq ($OSDiskNumber.Number))
{
    diskpart /s $env:SCRIPTROOT\Custom\RecoveryPartition-D1-BIOS.txt
}
