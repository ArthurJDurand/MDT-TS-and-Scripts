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
