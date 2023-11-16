$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
[String]$WindowsImage = ($WindowsVolumeLetter.Driveletter).ToString() + ":\"
[String]$WLAN = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\WLAN"
[String]$DriversPath = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\"

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Where-Object {$_.Product -ne 'Not Available'} | Select-Object -ExpandProperty Product
if (!([string]::IsNullOrWhiteSpace($BaseBoardProduct)))
{
    $Model = $BaseBoardProduct
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Where-Object {$_.Version -ne 'System Version' -and $_.Version -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Version
if (!([string]::IsNullOrWhiteSpace($ProductVersion)))
{
    $Model = $ProductVersion
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Model -ne 'System Product Name' -and $_.Model -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Model
if (!([string]::IsNullOrWhiteSpace($SystemModel)))
{
    $Model = $SystemModel
}

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Manufacturer -ne 'Not Available' -and $_.Manufacturer -ne 'System manufacturer' -and $_.Manufacturer -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Manufacturer
if (!([string]::IsNullOrWhiteSpace($SystemManufacturer)))
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

if (Test-Path $WLAN)
{
    DISM /Image:$WindowsImage /Add-Driver /Driver:$WLAN /recurse
}

$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*11th Gen*"))
{
    [String]$StorageDrivers = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\Storage\Intel\VMD"
}

$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*12th Gen*"))
{
    [String]$StorageDrivers = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\Storage\Intel\VMD"
}

$CPUName = WMIC CPU Get Name
if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and ($CPUName -like "*13th Gen*"))
{
    [String]$StorageDrivers = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers\Storage\Intel\VMD"
}

if ((!([string]::IsNullOrWhiteSpace($CPUName))) -and (Test-Path $StorageDrivers\*))
{
    DISM /Image:$WindowsImage /Add-Driver /Driver:$StorageDrivers /recurse
}
