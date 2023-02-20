takeown /F C:\Recovery\OEM /R /D Y /SKIPSL
icacls C:\Recovery\OEM /T /C /L /Q /RESET

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
