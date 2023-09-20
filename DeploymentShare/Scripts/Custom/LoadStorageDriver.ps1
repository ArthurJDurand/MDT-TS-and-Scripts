$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*11th Gen*"))
{
    $StorageDrivers = "C:\Recovery\OEM\Drivers\Storage\Intel\VMD\19.5.2.1049.5"
}

$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*12th Gen*"))
{
    $StorageDrivers = "C:\Recovery\OEM\Drivers\Storage\Intel\VMD\19.5.2.1049.5"
}

$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*13th Gen*"))
{
    $StorageDrivers = "C:\Recovery\OEM\Drivers\Storage\Intel\VMD\19.5.2.1049.5"
}
