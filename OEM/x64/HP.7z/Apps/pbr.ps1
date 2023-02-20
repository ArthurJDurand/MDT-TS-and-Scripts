#HP Inc. FEB 2023

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

$myHP = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.myHP' })
if ([string]::IsNullOrWhiteSpace($myHP))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\myHP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    Start-Process $Package -ArgumentList "-s" -Wait
}

$HPPCHD = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPPCHardwareDiagnosticsWindows' })
if ([string]::IsNullOrWhiteSpace($HPPCHD))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\HDW"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\HPPCHD_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$PS = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPPrivacySettings' })
if ([string]::IsNullOrWhiteSpace($PS))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\PS"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "install.exe" | Select-Object -ExpandProperty FullName
    Start-Process $Package -ArgumentList "-s -overwrite -report C:\Recovery\OEM\Apps\Logs" -Wait
}

$SSD = Get-PhysicalDisk | select DeviceID, Friendlyname, BusType, MediaType | Where MediaType -eq 'SSD' | Select -ExpandProperty DeviceID
if (-not ([string]::IsNullOrWhiteSpace($SSD)))
{
    $Sleep = '60'
} else {
    $Sleep = '300'
}

$SA = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPSupportAssistant' })
if ([string]::IsNullOrWhiteSpace($SA))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SA"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    Start-Process $Package -ArgumentList "-s"
    Start-Sleep -seconds $Sleep
}

$LegacySA = (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'HP Support Assistant' })
$SA = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPSupportAssistant' })
if (([string]::IsNullOrWhiteSpace($SA)) -and ([string]::IsNullOrWhiteSpace($LegacySA)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\LegacySA"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    Start-Process $Package -ArgumentList "-s"
    Start-Sleep -seconds $Sleep
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Windows\OEM)))
{
    New-Item C:\Windows\OEM -itemType Directory
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell)))
{
    New-Item C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -itemType Directory
}

$LegacySA = (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'HP Support Assistant' })
$SA = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPSupportAssistant' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and ([string]::IsNullOrWhiteSpace($SA)) -and (-not ([string]::IsNullOrWhiteSpace($LegacySA))))
{
    Copy-Item C:\Recovery\OEM\Apps\LegacySA\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
    Copy-Item C:\Recovery\OEM\Apps\LegacySA\TaskbarLayoutModification.xml -Destination C:\Windows\OEM -Force
}

$LegacySA = (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'HP Support Assistant' })
$SA = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.HPSupportAssistant' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and ([string]::IsNullOrWhiteSpace($SA)) -and (-not ([string]::IsNullOrWhiteSpace($LegacySA))))
{
    Copy-Item C:\Recovery\OEM\Apps\LegacySA\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OMENCommandCenter = (Get-AppxPackage | Where { $_.Name -Match 'AD2F1837.OMENCommandCenter' })
if (($Model -like '*Gaming*') -or ($Model -like '*OMEN*') -or ($Model -like '*Victus*') -and ([string]::IsNullOrWhiteSpace($OMENCommandCenter)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\OCC"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.msix" | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\OCC\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\OMENCommandCenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$HDUEFI = Get-ChildItem -File C:\Recovery\OEM\Apps\HDUEFI -Filter "*.exe" | Select-Object -ExpandProperty FullName
New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name !HDUEFI -Value "$HDUEFI"
