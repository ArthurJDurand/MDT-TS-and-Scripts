#ASUSTek Computer Inc. FEB 2023

$DependencyFolderPath = "C:\Recovery\OEM\Apps\Dependencies"
$Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName

$MyASUS = (Get-AppxPackage | Where { $_.Name -Match 'B9ECED6F.ASUSPCAssistant' })
if ([string]::IsNullOrWhiteSpace($MyASUS))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\MyASUS"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MyASUS_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$Hotkeys = (Get-AppxPackage | Where { $_.Name -Match 'B9ECED6F.ASUSKeyboardHotkeys' })
$HardwareType = Get-WmiObject -Class Win32_ComputerSystem -Property PCSystemType
If (([string]::IsNullOrWhiteSpace($Hotkeys)) -and ($HardwareType.PCSystemType -eq 2))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\Hotkeys"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\Hotkeys_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
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

$ArmouryCrate = (Get-AppxPackage | Where { $_.Name -Match 'B9ECED6F.ArmouryCrate' })
if (($Model -like '*PRIME*') -or ($Model -like '*ROG*') -or ($Model -like '*TUF*') -and ([string]::IsNullOrWhiteSpace($ArmouryCrate)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\ArmouryCrate"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.msixbundle" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\ArmouryCrate_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$ACService = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'ARMOURY CRATE' })
if (($Model -like '*PRIME*') -or ($Model -like '*ROG*') -or ($Model -like '*TUF*') -and ([string]::IsNullOrWhiteSpace($ACService)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\ArmouryCrate"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.exe" | Select-Object -ExpandProperty FullName
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name !ArmouryCrateInstaller -Value "$Package"
}
