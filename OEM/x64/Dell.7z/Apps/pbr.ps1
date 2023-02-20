#Dell Inc. FEB 2023

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

$DependencyFolderPath = "C:\Recovery\OEM\Apps\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName

$AlienwareDigitalDeliveryUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.AlienwareDigitalDelivery' })
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -and ([string]::IsNullOrWhiteSpace($AlienwareDigitalDeliveryUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DDD\AWUWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DDD_AWUWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$DigitalDeliveryUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.DellDigitalDelivery' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -or ($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ([string]::IsNullOrWhiteSpace($DigitalDeliveryUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DDD\UWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DDD_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$DigitalDelivery = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell Digital Delivery Services' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -or ($Model -like '*XPS*') -or ($Model -like '*Alienware*') -or ($Model -like '*Virt*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ([string]::IsNullOrWhiteSpace($DigitalDelivery)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DDD"
    $MSIPackage = Get-ChildItem -Path $PackageFolderPath -Filter "*.msi*" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DDD_Install.log"
    Start-Process $MSIPackage -ArgumentList "/qn /norestart /l*v $Log" -Wait
    # Copy-Item C:\Recovery\OEM\Apps\DDD\Link\NonAlienware\*.* -Destination C:\Users\Public\Desktop" -Force
}

$WindowsDesktopRuntime = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Microsoft Windows Desktop Runtime' })
If ([string]::IsNullOrWhiteSpace($WindowsDesktopRuntime))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SupportAssist\PreinstallKit"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "windowsdesktop-runtime*.exe" | Select-Object -ExpandProperty FullName
    Start-Process $Package -ArgumentList "/install /quiet /norestart" -Wait
    Start-Sleep -seconds 10
}

$SupportAssistUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.DellSupportAssistforPCs' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -or ($Model -like '*XPS*') -or ($Model -like '*Alienware*') -or ($Model -like '*Virt*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -or ($Model -like '*Embed*') -and ([string]::IsNullOrWhiteSpace($SupportAssistUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SupportAssist\PreinstallKit"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\SA_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$SupportAssist = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell SupportAssist' })
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -or ($Model -like '*Embed*') -and ([string]::IsNullOrWhiteSpace($SupportAssist)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SupportAssist"
    $MSIPackage = Get-ChildItem -File $PackageFolderPath -Filter "*.msi" | Select-Object -ExpandProperty FullName
    $MSPPackage = Get-ChildItem -File $PackageFolderPath -Filter "*.msp" | Select-Object -ExpandProperty FullName
    $MSILog = "C:\Recovery\OEM\Apps\Logs\SA_MSI.log"
    $MSPLog = "C:\Recovery\OEM\Apps\Logs\SA_MSP.log"
    Start-Process $MSIPackage -ArgumentList "Source=DellOSRI FACTORY=1 VARIANT=aa REBOOT=ReallySuppress /qn /norestart /l*v $MSILog" -Wait
    Start-Process $MSPPackage -ArgumentList "Source=DellOSRI FACTORY=1 VARIANT=aa /qn /norestart /l*v $MSPLog" -Wait
    # Copy-Item /S /I /Q /F C:\Recovery\OEM\Apps\SupportAssist\Link\*.* -Destination C:\Users\Public\Desktop" -Force
}

$SupportAssist = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell SupportAssist' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -or ($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ([string]::IsNullOrWhiteSpace($SupportAssist)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SupportAssist"
    $MSIPackage = Get-ChildItem -File $PackageFolderPath -Filter "*.msi" | Select-Object -ExpandProperty FullName
    $MSPPackage = Get-ChildItem -File $PackageFolderPath -Filter "*.msp" | Select-Object -ExpandProperty FullName
    $MSILog = "C:\Recovery\OEM\Apps\Logs\SA_MSI.log"
    $MSPLog = "C:\Recovery\OEM\Apps\Logs\SA_MSP.log"
    Start-Process $MSIPackage -ArgumentList "Source=DellOSRI FACTORY=1 VARIANT=dsc REBOOT=ReallySuppress /qn /norestart /l*v $MSILog" -Wait
    Start-Process $MSPPackage -ArgumentList "Source=DellOSRI FACTORY=1 VARIANT=dsc /qn /norestart /l*v $MSPLog" -Wait
    # Copy-Item /S /I /Q /F C:\Recovery\OEM\Apps\SupportAssist\Link\*.* -Destination C:\Users\Public\Desktop" -Force
}

$AlienwareUpdateUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.AlienwareUpdate' })
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -and ([string]::IsNullOrWhiteSpace($AlienwareUpdateUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DU\AWUWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DU_AWUWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -LicensePath $License -logpath $Log
}

$AlienwareUpdate = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell Update for Windows Universal' })
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -and ([string]::IsNullOrWhiteSpace($AlienwareUpdate)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DU"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DU_Install.log"
    Start-Process $Package -ArgumentList "/s /l=$Log" -Wait
    # Copy-Item C:\Recovery\OEM\Apps\DU\Link\NonANW\*.* -Destination C:\Users\Public\Desktop" /chrky#
}

$UpdateUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.DellUpdate' })
If (($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ([string]::IsNullOrWhiteSpace($UpdateUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DU\UWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DU_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -LicensePath $License -logpath $Log
}

$Update = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell Update for Windows Universal' })
If (($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ([string]::IsNullOrWhiteSpace($Update)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DU"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DU_Install.log"
    Start-Process $Package -ArgumentList "/s /l=$Log" -Wait
    # Copy-Item C:\Recovery\OEM\Apps\DU\Link\NonANW\*.* -Destination C:\Users\Public\Desktop" /chrky#
}

$CommandUpdateUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.DellCommandUpdate' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -and ([string]::IsNullOrWhiteSpace($CommandUpdateUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DCU"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DCU_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -LicensePath $License -logpath $Log
}

$CommandUpdate = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Dell Command | Update for Windows Universal' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -and ([string]::IsNullOrWhiteSpace($CommandUpdate)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DCU"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DCU_Install.log"
    Start-Process $Package -ArgumentList "/s /l=$Log" -Wait
    # Copy-Item C:\Recovery\OEM\Apps\DCU\Link\*.* -Destination C:\Users\Public\Desktop" -Force
}

$CustomerConnectUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.DellCustomerConnect' })
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -or ($Model -like '*XPS*') -or ($Model -like '*Alienware*') -or ($Model -like '*Virt*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -or ($Model -like '*Embed*') -and ([string]::IsNullOrWhiteSpace($CustomerConnectUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DCC"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DCC_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
If (($Model -like '*XPS*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -and ([string]::IsNullOrWhiteSpace($MyDellUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\MyDell"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MyDell_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*XPS*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -and (-not ([string]::IsNullOrWhiteSpace($MyDellUWP))) -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\MyDell\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*XPS*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -and (-not ([string]::IsNullOrWhiteSpace($MyDellUWP))) -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\MyDell\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
If (($Model -like '*Alienware*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -and ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\ACC"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\ACC_Install.log"
    Start-Process $Package -ArgumentList "/s /l=$Log" -Wait
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name !AlienwareCommandCenter -Value "$Package"
}

$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -and (-not ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter))) -and ([string]::IsNullOrWhiteSpace($MyDellUWP)) -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ACC\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -and (-not ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter))) -and ([string]::IsNullOrWhiteSpace($MyDellUWP)) -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ACC\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -and (-not ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter))) -and (-not ([string]::IsNullOrWhiteSpace($MyDellUWP))) -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ACC\withMyDell\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -and (-not ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter))) -and (-not ([string]::IsNullOrWhiteSpace($MyDellUWP))) -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ACC\withMyDell\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$FusionService = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Fusion Service' })
$AlienwareCommandCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Alienware Command Center' })
$MyDellUWP = (Get-AppxPackage | Where { $_.Name -Match 'DellInc.MyDell' })
If ((-not ([string]::IsNullOrWhiteSpace($AlienwareCommandCenter))) -or (-not ([string]::IsNullOrWhiteSpace($MyDellUWP))) -and ([string]::IsNullOrWhiteSpace($FusionService)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\FS"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\FS_Install.log"
    Start-Process $Package -ArgumentList "/s /l=$Log" -Wait
}
