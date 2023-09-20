$WinRAR = "X:\Program Files\WinRAR\WinRAR.exe"
$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter

if (!([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    $SrcDriversPath = ($DeployVolumeLetter.DriveLetter).ToString() + ":\DriverPacks\"
}

if (Test-Path \\SERVER\Shared\DriverPacks\)
{
    $SrcDriversPath = "\\SERVER\Shared\DriverPacks\"
}

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

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Manufacturer -ne 'Not Available' -and $_.Manufacturer -ne 'System Manufacturer' -and $_.Manufacturer -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Manufacturer
if (!([string]::IsNullOrWhiteSpace($SystemManufacturer)))
{
    $Manufacturer = $SystemManufacturer
}

if ($Manufacturer -like '*Lenovo*')
{
    $ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
    $Model = $ProductVersion
}

[String]$SrcDrivers = "$SrcDriversPath" + "$Model.7z"

if (!([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
{
    [String]$WindowsImage = ($WindowsVolumeLetter.Driveletter).ToString() + ":\"
    [String]$DstDriversPath = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM\Drivers"
}

if (!(Test-Path $DstDriversPath))
{
    New-Item $DstDriversPath -itemType Directory
}

if ((Test-Path $SrcDrivers) -and (Test-Path $DstDriversPath))
{
    Start-Process $WinRAR -ArgumentList "x -o+ `"$SrcDrivers`" $DstDriversPath" -Wait
}
