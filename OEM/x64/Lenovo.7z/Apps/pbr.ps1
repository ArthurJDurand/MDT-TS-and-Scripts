#Lenovo Group Limited, FEB 2023

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Where-Object {$_.Version -ne 'System Version' -and $_.Version -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Version
if (-not ([string]::IsNullOrWhiteSpace($ProductVersion)))
{
    $Model = $ProductVersion
}

$PackageFolderPath = "C:\Recovery\OEM\Apps\Vantage"
$Package = Get-ChildItem -File $PackageFolderPath -Filter "SystemInterfaceFoundation*.exe" | Select-Object -ExpandProperty FullName
$Log = "C:\Recovery\OEM\Apps\Logs\SIF_install.log"
Start-Process $Package -ArgumentList "/VERYSILENT /NORESTART /LOG=$Log" -Wait

$Vantage = (Get-AppxPackage | Where { $_.Name -Match 'E046963F.LenovoCompanion' })
if ([string]::IsNullOrWhiteSpace($Vantage))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Vantage"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.msixbundle" | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\Vantage\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Vantage_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$VantageService = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Lenovo Vantage Service' })
if ([string]::IsNullOrWhiteSpace($VantageService))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Vantage"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*Service.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\C:\Recovery\OEM\Apps\Logs\VantageService_install.log"
    Start-Process $Package -ArgumentList "/VERYSILENT /NORESTART /LOG=$Log" -Wait
}

$Utility = (Get-AppxPackage | Where { $_.Name -Match 'E0469640.LenovoUtility' })
if ([string]::IsNullOrWhiteSpace($Utility))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Utility"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.msixbundle" | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\Utility\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Utility_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$Voice = (Get-AppxPackage | Where { $_.Name -Match 'E046963F.LenovoVoiceWorldWide' })
if ([string]::IsNullOrWhiteSpace($Voice))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Voice"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Voice_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$NerveCenterUWP = (Get-AppxPackage | Where { $_.Name -Match 'E046963F.LenovoCompanion' })
if (($Model -like '*IdeaPad Gaming 3 15IHU6*') -or ($Model -like '*IdeaPad Gaming 3-15IMH05*') -or ($Model -like '*Legion 5 Pro-16ACH6*') -or ($Model -like '*Legion 5 Pro-16ITH6*') -or ($Model -like '*Legion 5-15ACH6*') -or ($Model -like '*Legion 5-15ARH05*') -or ($Model -like '*Legion 5-15IMH6*') -or ($Model -like '*Legion 5-15ITH6*') -or ($Model -like '*Legion 5-17ACH6*') -or ($Model -like '*Legion 5-17ITH6*') -or ($Model -like '*Legion 7-16ITHg6*') -or ($Model -like '*Legion S7-15ACH6*') -and ([string]::IsNullOrWhiteSpace($NerveCenterUWP)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\NerveCenter"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\NerveCenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$NerveCenter = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'Lenovo Nerve Center Core Component' })
if (($Model -like '*IdeaPad Gaming 3 15IHU6*') -or ($Model -like '*IdeaPad Gaming 3-15IMH05*') -or ($Model -like '*Legion 5 Pro-16ACH6*') -or ($Model -like '*Legion 5 Pro-16ITH6*') -or ($Model -like '*Legion 5-15ACH6*') -or ($Model -like '*Legion 5-15ARH05*') -or ($Model -like '*Legion 5-15IMH6*') -or ($Model -like '*Legion 5-15ITH6*') -or ($Model -like '*Legion 5-17ACH6*') -or ($Model -like '*Legion 5-17ITH6*') -or ($Model -like '*Legion 7-16ITHg6*') -or ($Model -like '*Legion S7-15ACH6*') -and ([string]::IsNullOrWhiteSpace($NerveCenter)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\NerveCenter"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\NerveCenter_install.log"
    Start-Process $Package -ArgumentList "/VERYSILENT /NORESTART /LOG=$Log" -Wait
}
