$WinRAR = "X:\Program Files\WinRAR\WinRAR.exe"
$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter

if (-not ([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    $OEMAppsSrcPath = ($DeployVolumeLetter.DriveLetter).ToString() + ":\OEM\x64\"
}

if (Test-Path \\SERVER\OEM\x64)
{
    $OEMAppsSrcPath = "\\SERVER\OEM\x64\"
}

if (-not ([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
{
    [String]$OEMDestination = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\OEM"
}

$BaseBoardManufacturer = Get-WmiObject Win32_BaseBoard | Select Manufacturer
if ((-not ([string]::IsNullOrWhiteSpace($BaseBoardManufacturer))) -or ($BaseBoardManufacturer.Manufacturer -eq 'Not Available') -or ($BaseBoardManufacturer.Manufacturer -eq 'System manufacturer'))
{
    [String]$Manufacturer = ($BaseBoardManufacturer.Manufacturer).ToString()
}

$ProductManufacturer = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Vendor
if ((-not ([string]::IsNullOrWhiteSpace($ProductManufacturer))) -or ($ProductManufacturer.Vendor -eq 'Not Available') -or ($ProductManufacturer.Vendor -eq 'System manufacturer') -or ($ProductManufacturer.Vendor -eq 'To be filled by O.E.M.'))
{
    [String]$Manufacturer = ($ProductManufacturer.Vendor).ToString()
}

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | select Manufacturer
if ((-not ([string]::IsNullOrWhiteSpace($SystemManufacturer))) -or ($SystemManufacturer.Manufacturer -eq 'Not Available') -or ($SystemManufacturer.Manufacturer -eq 'System manufacturer') -or ($SystemManufacturer.Manufacturer -eq 'To be filled by O.E.M.'))
{
    [String]$Manufacturer = ($SystemManufacturer.Manufacturer).ToString()
}

if (!(Test-Path $OEMDestination))
{
    New-Item $OEMDestination -itemType Directory
}

If ($Manufacturer -like '*Acer*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Acer.7z"
}

If ($Manufacturer -like '*ASUS*')
{
    $OEMApps = "$OEMAppsSrcPath" + "ASUS.7z"
}

If ($Manufacturer -like '*Dell*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Dell.7z"
}

If ($Manufacturer -like '*Dynabook*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Dynabook.7z"
}

If ($Manufacturer -like '*Gigabyte*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Gigabyte.7z"
}

If (($Manufacturer -like '*HP*') -or ($Manufacturer -like '*Hewlett Packard*') -or ($Manufacturer -like '*Hewlett-Packard*'))
{
    $OEMApps = "$OEMAppsSrcPath" + "HP.7z"
}

If ($Manufacturer -like '*Huawei*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Huawei.7z"
}

If ($Manufacturer -like '*Lenovo*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Lenovo.7z"
}

If ($Manufacturer -like '*Microsoft*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Microsoft.7z"
}

If (($Manufacturer -like '*Micro-Star*') -or ($Manufacturer -like '*MicroStar*') -or ($Manufacturer -like '*MSI*'))
{
    $OEMApps = "$OEMAppsSrcPath" + "MSI.7z"
}

If ($Manufacturer -like '*Proline*')
{
    $OEMApps = "$OEMAppsSrcPath" + "Proline.7z"
}

If ((Test-Path $OEMApps) -and (Test-Path $OEMDestination))
{
    & Start-Process $Winrar -ArgumentList "x -o+ `"$OEMApps`" $OEMDestination" -Wait
}
