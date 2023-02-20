$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
[String]$WindowsImage = ($WindowsVolumeLetter.Driveletter).ToString() + ":\"
[String]$WLAN = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\WLAN"
[String]$DriversPath = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\"

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Where-Object {$_.Product -ne 'Not Available'} | Select-Object -ExpandProperty Product
if (-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct)))
{
    $Model = $BaseBoardProduct
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Where-Object {$_.Version -ne 'System Version' -and $_.Version -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Version
if (-not ([string]::IsNullOrWhiteSpace($ProductVersion)))
{
    $Model = $ProductVersion
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Model -ne 'System Product Name' -and $_.Model -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Model
if (-not ([string]::IsNullOrWhiteSpace($SystemModel)))
{
    $Model = $SystemModel
}

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Manufacturer -ne 'Not Available' -and $_.Manufacturer -ne 'System manufacturer' -and $_.Manufacturer -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Manufacturer
if (-not ([string]::IsNullOrWhiteSpace($SystemManufacturer)))
{
    $Manufacturer = $SystemManufacturer
}

if ($Manufacturer -like '*Lenovo*')
{
    $ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
    $Model = $ProductVersion
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
