$CPUName = WMIC CPU Get Name
if ((-not ([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*12th Gen*"))
{
    & drvload.exe "X:\Drivers\Storage\Intel\VMD\19.5.1.1040"
}

$CPUName = WMIC CPU Get Name
if ((-not ([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*11th Gen*"))
{
    & drvload.exe "X:\Drivers\Storage\Intel\VMD\19.5.1.1040"
}
