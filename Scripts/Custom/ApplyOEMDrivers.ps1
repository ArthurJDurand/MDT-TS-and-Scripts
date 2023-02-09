$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
[String]$WindowsImage = ($WindowsVolumeLetter.Driveletter).ToString() + ":\"
[String]$WLAN = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\WLAN"
[String]$DriversPath = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\"

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Select Product
if ((-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct))) -or ($BaseBoardProduct.Product -eq 'Not Available'))
{
    [String]$Model = ($BaseBoardProduct.Product).ToString()
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
if ((-not ([string]::IsNullOrWhiteSpace($ProductVersion))) -or ($ProductVersion.Version -eq 'System Version') -or ($ProductVersion.Version -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($ProductVersion.Version).ToString()
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | select Model
if ((-not ([string]::IsNullOrWhiteSpace($SystemModel))) -or ($SystemModel.Model -eq 'System Product Name') -or ($SystemModel.Model -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($SystemModel.Model).ToString()
}

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | select Manufacturer
if ((-not ([string]::IsNullOrWhiteSpace($SystemManufacturer))) -or ($SystemManufacturer.Manufacturer -eq 'Not Available') -or ($SystemManufacturer.Manufacturer -eq 'System manufacturer') -or ($SystemManufacturer.Manufacturer -eq 'To be filled by O.E.M.'))
{
    [String]$Manufacturer = ($SystemManufacturer.Manufacturer).ToString()
}

if ($Manufacturer -like '*Lenovo*')
{
    $ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
    [String]$Model = ($ProductVersion.Version).ToString()
}

[String]$SrcDrivers = ($DriversPath).ToString() + "$Model"

if (Test-Path $SrcDrivers\*)
{
    DISM /Image:$WindowsImage /Add-Driver /Driver:$SrcDrivers /recurse
}

if ((Test-Path $WLAN\*) -and (!(Test-Path $SrcDrivers)))
{
    DISM /Image:$WindowsImage /Add-Driver /Driver:$WLAN /recurse
}

$CPUName = WMIC CPU Get Name
if ((-not ([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*11th Gen*"))
{
    $StorageDrivers = "C:\Recovery\OEM\Drivers\Storage\Intel\VMD\19.5.1.1040"
}

$CPUName = WMIC CPU Get Name
if ((-not ([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*12th Gen*"))
{
    $StorageDrivers = "C:\Recovery\OEM\Drivers\Storage\Intel\VMD\19.5.1.1040"
}

if (Test-Path $StorageDrivers\*)
{
    DISM /Image:$WindowsImage /Add-Driver /Driver:$StorageDrivers /recurse
}
