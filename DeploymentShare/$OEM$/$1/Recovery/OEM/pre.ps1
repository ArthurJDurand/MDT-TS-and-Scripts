Get-BitLockerVolume | Disable-BitLocker
Set-MPPreference -PUAProtection Enabled
Add-MpPreference -ExclusionPath C:\Recovery

if (Test-Path "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}")
{
    Remove-Item -Path "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -Recurse
}

if (Test-Path "HKCR:\CLSID\{04271989-C4D2-5507-C554-ABE25D4BDDBA}")
{
    Remove-Item -Path "HKCR:\CLSID\{04271989-C4D2-5507-C554-ABE25D4BDDBA}" -Force -Recurse
}

if (Test-Path "HKCR:\CLSID\{04271989-C4D2-F87B-1507-C086E2EFC9C8")
{
    Remove-Item -Path "HKCR:\CLSID\{04271989-C4D2-F87B-1507-C086E2EFC9C8}" -Force -Recurse
}

if (Test-Path "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}")
{
    Remove-Item -Path "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -Recurse
}

if (Test-Path "HKCR:\Wow6432Node\CLSID\{04271989-C4D2-5507-C554-ABE25D4BDDBA}")
{
    Remove-Item -Path "HKCR:\Wow6432Node\CLSID\{04271989-C4D2-5507-C554-ABE25D4BDDBA}" -Force -Recurse
}

if (Test-Path "HKCR:\Wow6432Node\CLSID\{04271989-C4D2-F87B-1507-C086E2EFC9C8}")
{
    Remove-Item -Path "HKCR:\Wow6432Node\CLSID\{04271989-C4D2-F87B-1507-C086E2EFC9C8}" -Force -Recurse
}

if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")
{
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace" -Force -Recurse
}

reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
if (Test-Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace)
{
    Remove-Item -Path HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace -Force -Recurse
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if ($OSCaption -like "*Windows 10*")
{
    New-ItemProperty -Path HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Feeds -Name ShellFeedsTaskbarOpenOnHover -Value 0 -PropertyType DWord
    Set-ItemProperty -Path HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Feeds -Name ShellFeedsTaskbarOpenOnHover -Value 0 -Force
    Set-ItemProperty -Path HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SystemPaneSuggestionsEnabled -Value 0 -Force
}
reg UNLOAD HKLM\temp

if (Test-Path C:\Recovery\OEM\OEMInfo.reg)
{
    reg import C:\Recovery\OEM\OEMInfo.reg
}

if (Test-Path C:\Recovery\OEM\gpsFix.reg)
{
    reg import C:\Recovery\OEM\gpsFix.reg
}

if (!(Test-Path C:\Recovery\OEM\Apps\Logs))
{
    New-Item C:\Recovery\OEM\Apps\Logs -itemType Directory
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Windows\OEM)))
{
    New-Item C:\Windows\OEM -itemType Directory
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell)))
{
    New-Item C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -itemType Directory
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (Test-Path C:\Recovery\OEM\LayoutModification.xml))
{
    Remove-Item C:\Recovery\OEM\LayoutModification.xml -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (Test-Path C:\Recovery\OEM\LayoutModification.json))
{
    Remove-Item C:\Recovery\OEM\LayoutModification.json -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (Test-Path C:\Recovery\OEM\TaskbarLayoutModification.xml))
{
    Remove-Item C:\Recovery\OEM\TaskbarLayoutModification.xml -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (Test-Path C:\Recovery\OEM\LayoutModification.json) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json)))
{
    Copy-Item C:\Recovery\OEM\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (Test-Path C:\Recovery\OEM\TaskbarLayoutModification.xml) -and (!(Test-Path C:\Windows\OEM\TaskbarLayoutModification.xml)))
{
    Copy-Item C:\Recovery\OEM\TaskbarLayoutModification.xml -Destination C:\Windows\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name LayoutXMLPath -Value C:\Windows\OEM\TaskbarLayoutModification.xml -Force
    Import-StartLayout -LayoutPath C:\Recovery\OEM\TaskbarLayoutModification.xml -Mountpath $env:SystemDrive\
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (Test-Path C:\Recovery\OEM\LayoutModification.xml) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml)))
{
    Copy-Item C:\Recovery\OEM\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$PackageFolderPath = "C:\Recovery\OEM\Apps\App Installer"
$Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
$DependencyFolderPath = "C:\Recovery\OEM\Apps\App Installer\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
$Log = "C:\Recovery\OEM\Apps\Logs\DesktopAppInstaller_UWP.log"
Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log

$PackageFolderPath = "C:\Recovery\OEM\Apps\Microsoft Store"
$Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
$DependencyFolderPath = "C:\Recovery\OEM\Apps\Microsoft Store\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
$Log = "C:\Recovery\OEM\Apps\Logs\WindowsStore_UWP.log"
Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log

$WindowsTerminal = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.WindowsTerminal' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and ([string]::IsNullOrWhiteSpace($WindowsTerminal)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Windows Terminal"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\Windows Terminal\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\WindowsTerminal_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$Todos = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.Todos' })
if ([string]::IsNullOrWhiteSpace($Todos))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Microsoft To Do"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\Microsoft To Do\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Todos_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$BingNews = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.BingNews' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and ([string]::IsNullOrWhiteSpace($BingNews)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Microsoft News"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\Microsoft News\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\News_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$PackageFolderPath = "C:\Recovery\OEM\Apps\Media Extensions"
$DependencyFolderPath = "C:\Recovery\OEM\Apps\Media Extensions\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName

$AV1VideoExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.AV1VideoExtension' })
if ([string]::IsNullOrWhiteSpace($AV1VideoExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.AV1VideoExtension*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\AV1VideoExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$HEIFImageExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.HEIFImageExtension' })
if ([string]::IsNullOrWhiteSpace($HEIFImageExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.HEIFImageExtension*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\HEIFImageExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$HEVCVideoExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.HEVCVideoExtension' })
if ([string]::IsNullOrWhiteSpace($HEVCVideoExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.HEVCVideoExtensions*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\HEVCVideoExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$MPEG2VideoExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.MPEG2VideoExtension' })
if ([string]::IsNullOrWhiteSpace($MPEG2VideoExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.MPEG2VideoExtension*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MPEG2VideoExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$RawImageExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.RawImageExtension' })
if ([string]::IsNullOrWhiteSpace($RawImageExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.RawImageExtension_2.1*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\RawImageExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$RawImageExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.RawImageExtension' })
if ([string]::IsNullOrWhiteSpace($RawImageExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.RawImageExtension_2.0*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\RawImageExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$VP9VideoExtensions = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.VP9VideoExtensions' })
if ([string]::IsNullOrWhiteSpace($VP9VideoExtensions))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.VP9VideoExtensions*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\VP9VideoExtensions_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$WebpImageExtension = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.WebpImageExtension' })
if ([string]::IsNullOrWhiteSpace($WebpImageExtension))
{
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "Microsoft.WebpImageExtension*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\WebpImageExtension_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

& C:\Recovery\OEM\LGPO\LGPO.exe /g C:\Recovery\OEM\LGPO\Backup
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
reg import C:\Recovery\OEM\RegionalSettings.reg
reg UNLOAD HKLM\temp

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Select Product
if ((-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct))) -or ($BaseBoardProduct.Product -eq 'Not Available'))
{
    [String]$Model = ($BaseBoardProduct.Product).ToString()
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation -Name Model -Value "$Model" -Force
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
if ((-not ([string]::IsNullOrWhiteSpace($ProductVersion))) -or ($ProductVersion.Version -eq 'System Version') -or ($ProductVersion.Version -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($ProductVersion.Version).ToString()
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation -Name Model -Value "$Model" -Force
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | select Model
if ((-not ([string]::IsNullOrWhiteSpace($SystemModel))) -or ($SystemModel.Model -eq 'System Product Name') -or ($SystemModel.Model -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($SystemModel.Model).ToString()
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation -Name Model -Value "$Model" -Force
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
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation -Name Model -Value "$Model" -Force
}

$OPK = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
$OPKDesc = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKeyDescription

if (($OPKDesc -like "*Professional*") -and (-not ([string]::IsNullOrWhiteSpace($OPKDesc))))
{
    cscript C:\Windows\System32\slmgr.vbs /ipk $OPK
    cscript C:\Windows\System32\slmgr.vbs /ato
}

if (($OPKDesc -like "*Professional*") -and (-not ([string]::IsNullOrWhiteSpace($OPKDesc))) -and (Test-Path C:\ProgramData\KMS\Windows.cmd))
{
    Remove-Item C:\ProgramData\KMS\Windows.cmd -Force
}

if (($OPKDesc -like "*Professional*") -and (-not ([string]::IsNullOrWhiteSpace($OPKDesc))) -and (Test-Path C:\Recovery\OEM\Windows.cmd))
{
    Remove-Item C:\Recovery\OEM\Windows.cmd -Force
}

if ([string]::IsNullOrWhiteSpace($OPKDesc) -or (!($OPKDesc -like "*Professional*")) -and (Test-Path C:\Recovery\OEM\Windows.cmd) -and (!(Test-Path C:\Recovery\OEM\Office.cmd)))
{
    Add-MpPreference -ExclusionPath C:\ProgramData\KMS
    Add-MpPreference -ExclusionProcess C:\WINDOWS\System32\SppExtComObjHook.dll
    New-Item C:\ProgramData\KMS -itemType Directory
    Copy-Item C:\Recovery\OEM\Windows.cmd -Destination C:\ProgramData\KMS -Force
    & cmd /c C:\ProgramData\KMS\Windows.cmd
}

$Office365 = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft 365 - un-us' })
if ((Test-Path C:\Recovery\OEM\Office.cmd) -and (-not ([string]::IsNullOrWhiteSpace($Office365))))
{
    Start-Process "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe" -ArgumentList "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=O365HomePremRetail.16_en-us_x-none culture=en-us version.16=16.0 displaylevel=false" -Wait
}

$Office365 = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft 365 - en-us' })
$Office365Enterprise = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft 365 Apps for enterprise' })
if (([string]::IsNullOrWhiteSpace($Office365)) -or (-not ([string]::IsNullOrWhiteSpace($Office365Enterprise))) -and (!(Test-Path C:\Recovery\OEM\Office.cmd)))
{
    Start-Process C:\Recovery\OEM\Apps\Office365\setup.exe -ArgumentList "/configure C:\Recovery\OEM\Apps\Office365\configuration.xml" -Wait
}

$Office365Enterprise = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft 365 Apps for enterprise' })
if ((Test-Path C:\Recovery\OEM\Office.cmd) -and ([string]::IsNullOrWhiteSpace($Office365Enterprise)))
{
    Set-Location C:\Recovery\OEM\Apps\Office365
    Start-Process C:\Recovery\OEM\Apps\Office365\setup.exe -ArgumentList "/configure C:\Recovery\OEM\Apps\Office365\configuration.xml" -Wait
}

if ((Test-Path C:\Recovery\OEM\Office.cmd) -and (!(Test-Path C:\ProgramData\KMS)))
{
    Add-MpPreference -ExclusionPath C:\ProgramData\KMS
    Add-MpPreference -ExclusionProcess C:\WINDOWS\System32\SppExtComObjHook.dll
    New-Item C:\ProgramData\KMS -itemType Directory
    Copy-Item C:\Recovery\OEM\Office.cmd -Destination C:\ProgramData\KMS -Force
}

if ((Test-Path C:\Recovery\OEM\Office.cmd) -and (Test-Path C:\ProgramData\KMS\Windows.cmd))
{
    Remove-Item C:\ProgramData\KMS\Windows.cmd -Force
    Remove-Item C:\Recovery\OEM\Windows.cmd -Force
}

$Office365Enterprise = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft 365 Apps for enterprise' })
if ((Test-Path C:\ProgramData\KMS\Office.cmd) -and (-not ([string]::IsNullOrWhiteSpace($Office365Enterprise))))
{
    & cmd /c C:\ProgramData\KMS\Office.cmd
}

if ((Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Access.lnk") -and (!(Test-Path C:\Users\Public\Desktop\Access.lnk)))
{
    Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Access.lnk" -Destination C:\Users\Public\Desktop -Force
}

if ((Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Excel.lnk") -and (!(Test-Path C:\Users\Public\Desktop\Excel.lnk)))
{
    Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Excel.lnk" -Destination C:\Users\Public\Desktop -Force
}

if ((Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerPoint.lnk") -and (!(Test-Path C:\Users\Public\Desktop\PowerPoint.lnk)))
{
    Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerPoint.lnk" -Destination C:\Users\Public\Desktop -Force
}

if ((Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Publisher.lnk") -and (!(Test-Path C:\Users\Public\Desktop\Publisher.lnk)))
{
    Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Publisher.lnk" -Destination C:\Users\Public\Desktop -Force
}

if ((Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk") -and (!(Test-Path C:\Users\Public\Desktop\Word.lnk)))
{
    Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk" -Destination C:\Users\Public\Desktop -Force
}

$7Zip = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match '7-Zip' })
if ([string]::IsNullOrWhiteSpace($7Zip))
{
    Start-Process C:\Recovery\OEM\Apps\7z.exe -ArgumentList "/S" -Wait
}

$WinRAR = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'WinRAR' })
if ([string]::IsNullOrWhiteSpace($WinRAR))
{
    Start-Process C:\Recovery\OEM\Apps\winrar.exe -ArgumentList "/s" -Wait
    Start-Process C:\Recovery\OEM\Apps\rarreg.exe -Wait
}

$WinRAR = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'WinRAR' })
if (-not [string]::IsNullOrWhiteSpace($WinRAR))
{
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    reg import C:\Recovery\OEM\Apps\WinRARSettings.reg
    reg UNLOAD HKLM\temp
}

$Diskeeper = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Diskeeper' })
if ([string]::IsNullOrWhiteSpace($Diskeeper))
{
    Start-Process C:\Recovery\OEM\Apps\Diskeeper.exe -ArgumentList '/s /v"/qn"' -Wait
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy bypass -File C:\Recovery\OEM\Apps\DKLicense.ps1 -Verb RunAs" -Wait
}

$Diskeeper = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Diskeeper' })
if (-not [string]::IsNullOrWhiteSpace($Diskeeper))
{
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    reg import C:\Recovery\OEM\Apps\DiskeeperSettings.reg
    reg UNLOAD HKLM\temp
}

$HDD = Get-PhysicalDisk | select DeviceID, Friendlyname, BusType, MediaType | Where MediaType -eq 'HDD' | Select -ExpandProperty DeviceID
$DriveMonitor = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Acronis Drive Monitor' })
if ((-not ([string]::IsNullOrWhiteSpace($HDD))) -and ([string]::IsNullOrWhiteSpace($DriveMonitor)))
{
    Start-Process C:\Recovery\OEM\Apps\DriveMonitor.msi -ArgumentList "/qn /norestart /l*v C:\Recovery\OEM\Apps\Logs\DriveMonitor_Install.log" -Wait
    Remove-Item "C:\Users\Public\Desktop\Acronis Drive Monitor.lnk" -Force
}

$DriveMonitor = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Acronis Drive Monitor' })
if (-not [string]::IsNullOrWhiteSpace($DriveMonitor))
{
    reg import C:\Recovery\OEM\Apps\DriveMonitor.reg
}

$pnputil = "$env:WINDIR\System32\pnputil.exe"

$DriversPath = "C:\Recovery\OEM\Drivers\"
$WLAN = "C:\Recovery\OEM\Drivers\WLAN"

[String]$OEMDrivers = ($DriversPath).ToString() + "$Model"
if (Test-Path $OEMDrivers)
{
    Get-ChildItem $OEMDrivers -Recurse -Filter "*.cer" | ForEach-Object { Import-Certificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\TrustedPublisher }
    Get-ChildItem $OEMDrivers -Recurse -Filter "*.inf" | ForEach-Object { & $pnputil /add-driver $_.FullName /install }
}

if ((Test-Path $WLAN) -and (!(Test-Path $OEMDrivers)))
{
    Get-ChildItem $WLAN -Recurse -Filter "*.cer" | ForEach-Object { Import-Certificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\TrustedPublisher }
    Get-ChildItem $WLAN -Recurse -Filter "*.inf" | ForEach-Object { & $pnputil /add-driver $_.FullName /install }
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

if ((Test-Path $StorageDrivers) -and (!(Test-Path $OEMDrivers)))
{
    Get-ChildItem $StorageDrivers -Recurse -Filter "*.cer" | ForEach-Object { Import-Certificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\TrustedPublisher }
    Get-ChildItem $StorageDrivers -Recurse -Filter "*.inf" | ForEach-Object { & $pnputil /add-driver $_.FullName /install }
}

$AnyDesk = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'AnyDesk' })
if ([string]::IsNullOrWhiteSpace($AnyDesk))
{
    & cmd /c C:\Recovery\OEM\Apps\AnyDesk.cmd
}

$scheduleObject = New-Object -ComObject schedule.service
$scheduleObject.connect()
$rootFolder = $scheduleObject.GetFolder("\")
$rootFolder.CreateFolder("OEM")
schtasks /create /tn OEM\Update /xml C:\Recovery\OEM\Apps\Update.xml /f

if (Test-Path C:\_SMSTaskSequence)
{
    Remove-Item C:\_SMSTaskSequence -Force -Recurse
}

if (Test-Path C:\MININT)
{
    Remove-Item C:\MININT -Force -Recurse
}

if (Test-Path C:\Users\Default\AppData\Roaming\Microsoft\Windows\Themes)
{
    Remove-Item C:\Users\Default\AppData\Roaming\Microsoft\Windows\Themes -Recurse -Force
}

if (Test-Path C:\LTIBootstrap.vbs)
{
    Remove-Item C:\LTIBootstrap.vbs -Force
}

$SystemDiskNumber = Get-Volume | Where {$_.FileSystemLabel -Like "System"} | Get-Partition | Select DiskNumber
$RecoveryVolume = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | Get-Partition | Select PartitionNumber
if (-not ([string]::IsNullOrWhiteSpace($RecoveryVolume)))
{
    Set-Partition $SystemDiskNumber.DiskNumber $RecoveryVolume.PartitionNumber  -NewDriveLetter R
}

if (!(Test-Path R:\Recovery\WindowsRE))
{
    New-Item R:\Recovery\WindowsRE -itemType Directory
}

if (!(Test-Path R:\Recovery\WindowsRE\Winre.wim) -and (Test-Path C:\Recovery\WindowsRE\Winre.wim))
{
    Copy-Item C:\Recovery\WindowsRE\Winre.wim -Destination R:\Recovery\WindowsRE -Force
}

if (!(Test-Path R:\Recovery\WindowsRE\Winre.wim) -and (Test-Path C:\Windows\System32\Recovery\Winre.wim))
{
    Copy-Item C:\Windows\System32\Recovery\Winre.wim -Destination R:\Recovery\WindowsRE -Force
}

if (Test-Path R:\Recovery\WindowsRE\Winre.wim)
{
    reagentc /setreimage /path R:\Recovery\WindowsRE
    reagentc /enable
}

if (Test-Path R:\$Recycle.Bin)
{
    Remove-Item R:\$Recycle.Bin -Force -Recurse
}

if (-not ([string]::IsNullOrWhiteSpace($RecoveryVolume)))
{
    Get-Volume -Drive R | Get-Partition | Remove-PartitionAccessPath -accesspath R:\
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h