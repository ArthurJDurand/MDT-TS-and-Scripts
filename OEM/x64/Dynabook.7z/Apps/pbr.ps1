#Dynabook Inc. FEB 2023

$DependencyFolderPath = "C:\Recovery\OEM\Apps\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx*" | Select-Object -ExpandProperty FullName

$PCInformation = (Get-AppxPackage | Where { $_.Name -Match '7906AAC0.TOSHIBAPCInformation' })
if ([string]::IsNullOrWhiteSpace($PCInformation))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\PCInformation"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath C:\Recovery\OEM\Apps\Logs\PCInformation_UWP.log
}

$ServiceStation = (Get-AppxPackage | Where { $_.Name -Match '7906AAC0.TOSHIBAServiceStation' })
if ([string]::IsNullOrWhiteSpace($ServiceStation))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\ServiceStation"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath C:\Recovery\OEM\Apps\Logs\ServiceStation_UWP.log
}

$Settings = (Get-AppxPackage | Where { $_.Name -Match '7906AAC0.TOSHIBASettings' })
if ([string]::IsNullOrWhiteSpace($Settings))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Settings"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath C:\Recovery\OEM\Apps\Logs\Settings_UWP.log
}

$SupportUtility = (Get-AppxPackage | Where { $_.Name -Match '7906AAC0.dynabookSupportUtility' })
if ([string]::IsNullOrWhiteSpace($SupportUtility))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SupportUtility"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath C:\Recovery\OEM\Apps\Logs\SupportUtility_UWP.log
}
