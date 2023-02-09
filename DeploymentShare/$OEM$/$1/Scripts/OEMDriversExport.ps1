takeown /F C:\Recovery\OEM /R /D Y /SKIPSL
icacls C:\Recovery\OEM /T /C /L /Q /RESET

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

$DriversPath = "C:\Recovery\OEM\Drivers\"
[String]$Drivers = "$DriversPath" + "$Model"
[String]$Archive = "$Drivers" + ".7z"

if (Test-Path $DriversPath)
{
  Remove-Item $DriversPath -Force -Recurse
}

if (!(Test-Path $DriversPath))
{
New-Item $Drivers -itemType Directory
}

if (Test-Path $Drivers)
{
    pnputil /export-driver * $Drivers
}

if (Test-Path $Drivers\prn*)
{
    Remove-Item $Drivers\prn* -Force -Recurse
}

$7Zip = "C:\Program Files\7-Zip\7z.exe"
if (Test-Path $7Zip)
{
     & $7Zip a -mx9 -ssw $Archive $Drivers
}

$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter
if (-not ([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    $DriverPackPath = ($DeployVolumeLetter.Driveletter).ToString() + ":\DriverPacks"
}

if (Test-Path "\\SERVER\Shared\DriverPacks")
{
    $DriverPackPath = "\\SERVER\Shared\DriverPacks"
}

if (!(Test-Path $DriverPackPath))
{
    New-Item $DriverPackPath -itemType Directory
}

if ((Test-Path $Archive) -and (Test-Path $DriverPackPath))
{
    Copy-Item -Path $Archive -Destination $DriverPackPath -Force
}

if (Test-Path $Archive)
{
    Remove-Item $Archive -Force
}

Remove-Item $PSCommandPath -Force
