#Acer Inc. FEB 2023

$DependencyFolderPath = "C:\Recovery\OEM\Apps\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName

$QuickAccess = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Quick Access Service' })
If ([string]::IsNullOrWhiteSpace($QuickAccess))
{
    Start-Process C:\Recovery\OEM\Apps\QuickAccess\setup.exe -ArgumentList "-s -overwrite -report C:\Recovery\OEM\Apps\Logs" -Wait
}

$QuickAccessUWP = (Get-AppxPackage | Where { $_.Name -Match 'AcerIncorporated.QuickAccess' })
if ([string]::IsNullOrWhiteSpace($QuickAccessUWP))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\QuickAccess\QuickAccessUWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*_License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\QuickAccess_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -LicensePath $License -logpath $Log
}

$RegistrationUWP = (Get-AppxPackage | Where { $_.Name -Match 'AcerIncorporated.Registration' })
if ([string]::IsNullOrWhiteSpace($RegistrationUWP))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Registration"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.msix" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Registration_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$CareCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Care Center Service' })
If ([string]::IsNullOrWhiteSpace($CareCenter))
{
    Start-Process C:\Recovery\OEM\Apps\CareCenter\setup.exe -ArgumentList "-s -overwrite -report C:\Recovery\OEM\Apps\Logs"
    Start-Sleep -seconds 60
}

$CareCenterUWP = (Get-AppxPackage | Where { $_.Name -Match 'AcerIncorporated.AcerCareCenterS' })
if ([string]::IsNullOrWhiteSpace($CareCenterUWP))
{
    $Package = "C:\Recovery\OEM\Apps\CareCenter\CareCenterUWP\x64\d9aa3f7864624a8594fe4a1ded8ab781.appx"
    $License = "C:\Recovery\OEM\Apps\CareCenter\CareCenterUWP\x64\d9aa3f7864624a8594fe4a1ded8ab781_License1.xml"
    $Log = "C:\Recovery\OEM\Apps\Logs\CareCenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -LicensePath $License -logpath $Log
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

$NitroSense = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'NitroSense' })
If (($Model -like '*Nitro*') -and ([string]::IsNullOrWhiteSpace($NitroSense)))
{
    Start-Process C:\Recovery\OEM\Apps\NitroSense\setup.exe -ArgumentList "-s -overwrite -report C:\Recovery\OEM\Apps\Logs" -Wait
}

$NitroSenseUWP = (Get-AppxPackage | Where { $_.Name -Match 'AcerIncorporated.NitroSenseV31' })
if (($Model -like '*Nitro*') -and ([string]::IsNullOrWhiteSpace($NitroSenseUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\NitroSense\NitroSenseV3.1"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*_License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\NitroSense_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -LicensePath $License -logpath $Log
}

$PredatorSense = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'PredatorSense' })
If (($Model -like '*Nitro*') -and ([string]::IsNullOrWhiteSpace($PredatorSense)))
{
    Start-Process C:\Recovery\OEM\Apps\PredatorSense\setup.exe -ArgumentList "-s -overwrite -report C:\Recovery\OEM\Apps\Logs" -Wait
}

$PredatorSenseUWP = (Get-AppxPackage | Where { $_.Name -Match 'AcerIncorporated.PredatorSenseV31' })
If (($Model -like '*Nitro*') -and ([string]::IsNullOrWhiteSpace($PredatorSenseUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\PredatorSense\PredatorSenseUWP"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $License = Get-ChildItem -File $PackageFolderPath -Filter "*_License1.xml" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\PredatorSense_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -LicensePath $License -logpath $Log
}
