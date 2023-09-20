powercfg -setacvalueindex scheme_current sub_pciexpress ee12f906-d277-404b-b6da-e5fa1a576df5 0
Start-Process 'windowsdefender:' -WindowStyle Maximized

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Name "EnableUlps" -Value 0
}

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Name "PerformanceSettings" -Value 0
}

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\amdkmpfd") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\amdkmpfd" -Name "Start" -Value 0
}

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm" -Name "TdrLevel" -Value 0
}

$SystemDiskNumber = Get-Volume | Where {$_.FileSystemLabel -Like "System"} | Get-Partition | Select DiskNumber
$RecoveryVolume = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | Get-Partition | Select PartitionNumber
if (!([string]::IsNullOrWhiteSpace($RecoveryVolume)))
{
    Set-Partition $SystemDiskNumber.DiskNumber $RecoveryVolume.PartitionNumber  -NewDriveletter R
}

$DriversPath = "C:\Recovery\OEM\Drivers\"

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Select Product
if ((!([string]::IsNullOrWhiteSpace($BaseBoardProduct))) -or ($BaseBoardProduct.Product -eq 'Not Available'))
{
    [String]$Model = ($BaseBoardProduct.Product).ToString()
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
if ((!([string]::IsNullOrWhiteSpace($ProductVersion))) -or ($ProductVersion.Version -eq 'System Version') -or ($ProductVersion.Version -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($ProductVersion.Version).ToString()
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | select Model
if ((!([string]::IsNullOrWhiteSpace($SystemModel))) -or ($SystemModel.Model -eq 'System Product Name') -or ($SystemModel.Model -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($SystemModel.Model).ToString()
}

$SystemManufacturer = Get-WmiObject -Class:Win32_ComputerSystem | select Manufacturer
if ((!([string]::IsNullOrWhiteSpace($SystemManufacturer))) -or ($SystemManufacturer.Manufacturer -eq 'Not Available') -or ($SystemManufacturer.Manufacturer -eq 'System manufacturer') -or ($SystemManufacturer.Manufacturer -eq 'To be filled by O.E.M.'))
{
    [String]$Manufacturer = ($SystemManufacturer.Manufacturer).ToString()
}

if ($Manufacturer -like '*Lenovo*')
{
    $ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
    [String]$Model = ($ProductVersion.Version).ToString()
}

[String]$Drivers = ($DriversPath).ToString() + "$Model"

if (!(Test-Path $Drivers))
{
    New-Item $Drivers -itemType Directory
    pnputil /export-driver * $Drivers
    Remove-Item $Drivers\prn* -Force -Recurse
}

if (!(Test-Path C:\Temp\Drivers))
{
    New-Item C:\Temp\Drivers -itemType Directory
}

if (Test-Path $Drivers\iaAHCI*)
{
    Copy-Item -Path $Drivers\iaAHCI* -Destination C:\Temp\Drivers -Force -Recurse
}

if (Test-Path $Drivers\iaRVMD*)
{
    Copy-Item -Path $Drivers\iaRVMD* -Destination C:\Temp\Drivers -Force -Recurse
}

if (Test-Path $Drivers\iaStor*)
{
    Copy-Item -Path $Drivers\iaStor* -Destination C:\Temp\Drivers -Force -Recurse
}

if (!(Test-Path C:\Temp\WindowsRE))
{
    New-Item C:\Temp\WindowsRE -itemType Directory
}

if ((Test-Path R:\Recovery\WindowsRE\winre.wim) -and (Test-Path C:\Temp\Drivers\*))
{
    Mount-WindowsImage -ImagePath R:\Recovery\WindowsRE\winre.wim -index 1 -Path C:\Temp\WindowsRE
    Add-WindowsDriver -Path C:\Temp\WindowsRE -Driver C:\Temp\Drivers -recurse
    Dismount-WindowsImage -Path C:\Temp\WindowsRE -Save
    Export-WindowsImage -SourceImagePath R:\Recovery\WindowsRE\winre.wim -SourceIndex 1 -DestinationImagePath C:\Temp\WindowsRE\winre.wim
    Move-Item -Path C:\Temp\WindowsRE\winre.wim -Destination R:\Recovery\WindowsRE -Force
}

if (Test-Path R:\$Recycle.Bin)
{
    Remove-Item R:\$Recycle.Bin -Force -Recurse
}

if (!([string]::IsNullOrWhiteSpace($RecoveryVolume)))
{
    Get-Volume -Drive R | Get-Partition | Remove-PartitionAccessPath -accesspath R:\
}

if (Test-Path C:\Temp\WindowsRE)
{
    Remove-Item C:\Temp\WindowsRE -Force -Recurse
}

$ScanStatePath = $null
$DeployVolumeLetter = Get-Volume | Where-Object {$_.FileSystemLabel -Like "Deploy"} | Select-Object -ExpandProperty DriveLetter
while ($ScanStatePath -eq $null) {
    if (Test-Path '\\SERVER\Shared\ScanState') {
        $ScanStatePath = '\\SERVER\Shared\ScanState'
    }
    elseif (Test-Path "$DeployVolumeLetter`:\ScanState") {
        $DeployVolumeLetter = Get-Volume | Where-Object {$_.FileSystemLabel -Like "Deploy"} | Select-Object -ExpandProperty DriveLetter
        $ScanStatePath = "$DeployVolumeLetter`:\ScanState"
    }
    else {
        Write-Host "Please switch on the deployment server or connect the deployment flash drive and press any key to continue."
        $null = Read-Host "Press any key to continue."
    }
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (!(Test-Path C:\Temp\ScanState)))
{
    New-Item C:\Temp\ScanState -itemType Directory
    Copy-Item -Path "$ScanStatePath\Win11\*" -Destination C:\Temp\ScanState -Force -Recurse
    Copy-Item -Path "$ScanStatePath\Custom\*.xml" -Destination C:\Temp\ScanState -Force -Recurse
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (!(Test-Path C:\Temp\ScanState)))
{
    New-Item C:\Temp\ScanState -itemType Directory
    Copy-Item -Path "$ScanStatePath\Win10\x64\*" -Destination C:\Temp\ScanState -Force -Recurse
    Copy-Item -Path "$ScanStatePath\Custom\*.xml" -Destination C:\Temp\ScanState -Force -Recurse
}

if (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Themes)
{
    Remove-Item C:\Users\Default\AppData\Local\Microsoft\Windows\Themes -Force -Recurse
}

if (Test-Path C:\Users\Default\AppData\Roaming\Microsoft\Windows\Themes)
{
    Remove-Item C:\Users\Default\AppData\Roaming\Microsoft\Windows\Themes -Force -Recurse
}

if (Test-Path C:\Windows\Setup\FirstLogon)
{
    Remove-Item C:\Windows\Setup\FirstLogon -Force -Recurse
}

if (Test-Path C:\Windows\Setup\FirstRun)
{
    Remove-Item C:\Windows\Setup\FirstRun -Force -Recurse
}

if (Test-Path C:\Windows\Setup\Scripts)
{
    Remove-Item C:\Windows\Setup\Scripts -Force -Recurse
}

if (Test-Path C:\Recovery\AutoApply)
{
    takeown /F C:\Recovery\AutoApply /R /D Y /SKIPSL
    icacls C:\Recovery\AutoApply /T /C /L /Q /RESET
}

if (Test-Path C:\Recovery\Customizations)
{
    takeown /F C:\Recovery\Customizations /R /D Y /SKIPSL
    icacls C:\Recovery\Customizations /T /C /L /Q /RESET
    Remove-Item C:\Recovery\Customizations -Force -Recurse
}

if (Test-Path C:\Recovery\OEM)
{
    takeown /F C:\Recovery\OEM /R /D Y /SKIPSL
    icacls C:\Recovery\OEM /T /C /L /Q /RESET
}

if (Test-Path C:\Recovery\OEM\Point_B)
{
    Remove-Item C:\Recovery\OEM\Point_B -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Point_D)
{
    Remove-Item C:\Recovery\OEM\Point_D -Force -Recurse
}

if (!(Test-Path C:\Recovery\OEM))
{
    New-Item C:\Recovery\OEM -itemType Directory
}

if (!(Test-Path C:\Recovery\AutoApply))
{
    New-Item C:\Recovery\AutoApply -itemType Directory
}

if (Test-Path C:\Recovery\OEM\unattend.xml)
{
    Move-Item -Path C:\Recovery\OEM\unattend.xml -Destination C:\Recovery\AutoApply -Force
}

if (Test-Path C:\Windows\OEM\TaskbarLayoutModification.xml)
{
    Copy-Item -Path C:\Windows\OEM\TaskbarLayoutModification.xml -Destination C:\Recovery\AutoApply -Force
}

if (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.*)
{
    Copy-Item -Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.* -Destination C:\Recovery\AutoApply -Force
}

if (!(Test-Path C:\Recovery\AutoApply\OOBE))
{
    New-Item C:\Recovery\AutoApply\OOBE -itemType Directory
}

if (Test-Path C:\Windows\System32\oobe\info\*)
{
    Copy-Item -Path C:\Windows\System32\oobe\info\* -Destination C:\Recovery\AutoApply\OOBE -Force -Recurse
}

if (!(Test-Path C:\Recovery\AutoApply\OOBE\*))
{
    Remove-Item C:\Recovery\AutoApply\OOBE -Force -Recurse
}

if (!(Test-Path C:\Recovery\AutoApply\*))
{
    Remove-Item C:\Recovery\AutoApply -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Apps\Logs)
{
    Remove-Item C:\Recovery\OEM\Apps\Logs\*.* -Force
}

if (Test-Path "C:\Recovery\OEM\Apps\App Installer")
{
    Remove-Item "C:\Recovery\OEM\Apps\App Installer" -Force -Recurse
}

if (Test-Path "C:\Recovery\OEM\Apps\Media Extensions")
{
    Remove-Item "C:\Recovery\OEM\Apps\Media Extensions" -Force -Recurse
}

if (Test-Path "C:\Recovery\OEM\Apps\Microsoft News")
{
    Remove-Item "C:\Recovery\OEM\Apps\Microsoft News" -Force -Recurse
}

if (Test-Path "C:\Recovery\OEM\Apps\Microsoft Store")
{
    Remove-Item "C:\Recovery\OEM\Apps\Microsoft Store" -Force -Recurse
}

if (Test-Path "C:\Recovery\OEM\Apps\Microsoft To Do")
{
    Remove-Item "C:\Recovery\OEM\Apps\Microsoft To Do" -Force -Recurse
}

if (Test-Path "C:\Recovery\OEM\Apps\Windows Terminal")
{
    Remove-Item "C:\Recovery\OEM\Apps\Windows Terminal" -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Apps)
{
    Remove-Item C:\Recovery\OEM\Apps\*.cmd -Force
    Remove-Item C:\Recovery\OEM\Apps\*.exe -Force
    Remove-Item C:\Recovery\OEM\Apps\*.msi -Force
    Remove-Item C:\Recovery\OEM\Apps\*.reg -Force
}

if (Test-Path C:\Recovery\OEM\Apps\DK*.*)
{
    Remove-Item C:\Recovery\OEM\Apps\DK*.* -Force
}

if (Test-Path C:\Recovery\OEM\Customizations)
{
    Remove-Item C:\Recovery\OEM\Customizations -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Drivers)
{
    Remove-Item C:\Recovery\OEM\Drivers -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\LGPO)
{
    Remove-Item C:\Recovery\OEM\LGPO -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\StoreContent)
{
    Remove-Item C:\Recovery\OEM\StoreContent -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Win10)
{
    Remove-Item C:\Recovery\OEM\Win10 -Force -Recurse
}

if (Test-Path C:\Recovery\OEM\Win11)
{
    Remove-Item C:\Recovery\OEM\Win11 -Force -Recurse
}

if (!(Test-Path C:\Windows\Setup\Scripts))
{
    New-Item C:\Windows\Setup\Scripts -itemType Directory
}

if (Test-Path C:\Recovery\OEM)
{
    Remove-Item C:\Recovery\OEM\*.7z -Force
	Remove-Item C:\Recovery\OEM\*.cmd -Exclude "Office.cmd", "Windows.cmd)" -Force
    Remove-Item C:\Recovery\OEM\*.ps1 -Force
    Remove-Item C:\Recovery\OEM\*.reg -Force
    Remove-Item C:\Recovery\OEM\LayoutModification.* -Force
	Remove-Item C:\Recovery\OEM\TaskbarLayoutModification.* -Force
	Remove-Item C:\Recovery\OEM\Reset*.* -Force
    Copy-Item -Path $ScanStatePath\Custom\pre.ps1 -Destination C:\Recovery\OEM -Force
    Copy-Item -Path $ScanStatePath\Custom\SetupComplete.cmd -Destination C:\Windows\Setup\Scripts -Force
}

if (!(Test-Path C:\Recovery\Customizations))
{
    New-Item C:\Recovery\Customizations -itemType Directory
}

if ((!(Test-Path C:\Scripts\*)) -and (Test-Path C:\Scripts))
{
    Remove-Item C:\Scripts -Force
}

$ServicingPath = $null
$DeployVolumeLetter = Get-Volume | Where-Object {$_.FileSystemLabel -Like "Deploy"} | Select-Object -ExpandProperty DriveLetter
while ($ServicingPath -eq $null) {
    if (Test-Path '\\SERVER\Shared\Servicing') {
        $ServicingPath = '\\SERVER\Shared\Servicing'
    }
    elseif (Test-Path "$DeployVolumeLetter`:\Servicing") {
        $DeployVolumeLetter = Get-Volume | Where-Object {$_.FileSystemLabel -Like "Deploy"} | Select-Object -ExpandProperty DriveLetter
        $ServicingPath = "$DeployVolumeLetter`:\Servicing"
    }
    else {
        Write-Host "Please switch on the deployment server or connect the deployment flash drive and press any key to continue."
        $null = Read-Host "Press any key to continue."
    }
}

if ((Test-Path $ServicingPath) -and (!(Test-Path C:\Temp\Servicing)))
{
    New-Item C:\Temp\Servicing -itemType Directory
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (Test-Path $ServicingPath))
{
    Copy-Item -Path $ServicingPath\Win11\* -Destination C:\Temp\Servicing -Force -Recurse
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (Test-Path $ServicingPath))
{
    Copy-Item -Path $ServicingPath\Win10\x64\* -Destination C:\Temp\Servicing -Force -Recurse
}

$WindowsImageHealth = Repair-WindowsImage -Online -CheckHealth
if (($WindowsImageHealth.ImageHealthState -eq 'Repairable') -and (Test-Path 'C:\Temp\Servicing\*'))
{
    Repair-WindowsImage -Online -RestoreHealth -Source C:\Temp\Servicing\Windows -LimitAccess
}

$WindowsImageHealth = Repair-WindowsImage -Online -CheckHealth
if ($WindowsImageHealth.ImageHealthState -eq 'Repairable')
{
    Repair-WindowsImage -Online -RestoreHealth
}

SFC /SCANNOW

Remove-Item $PSCommandPath -Force
