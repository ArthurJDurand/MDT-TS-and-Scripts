$WinRAR = "X:\Program Files\WinRAR\WinRAR.exe"
$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter

if (-not ([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    $SrcDriversPath = ($DeployVolumeLetter.DriveLetter).ToString() + ":\DriverPacks\"
}

if (Test-Path \\SERVER\Shared\DriverPacks\)
{
    $SrcDriversPath = "\\SERVER\Shared\DriverPacks\"
}

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

[String]$SrcDrivers = "$SrcDriversPath" + "$Model.7z"

if (-not ([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
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
