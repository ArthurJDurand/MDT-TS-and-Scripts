#Micro-Star International Co., Ltd FEB 2023

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

$MSICenter = (Get-AppxPackage | Where { $_.Name -Match '9426MICRO-STARINTERNATION.MSICenter' })
If (($Model -like '*Alpha*') -or ($Model -like '*Gaming*') -or ($Model -like '*GT*') -or ($Model -like '*GE*') -or ($Model -like '*GP*') -or ($Model -like '*GL*') -or ($Model -like '*GS*') -or ($Model -like '*GF*') -and ([string]::IsNullOrWhiteSpace($MSICenter)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\MSICenter"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MSICenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$MSICenterPro = (Get-AppxPackage | Where { $_.Name -Match '9426MICRO-STARINTERNATION.BusinessCenter' })
If (($Model -like '*Modern*') -or ($Model -like '*Prestige*') -or ($Model -like '*Summit*') -and ([string]::IsNullOrWhiteSpace($MSICenterPro)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\MSICenterPro"
    $Package = Get-ChildItem -File $PackageFolderPath -Filter "*.appxbundle*" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MSICenterPro_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$DriverAppCenter = (Get-AppxPackage | Where { $_.Name -Match 'msiappadm.MSIDriverAppCenter' })
if ([string]::IsNullOrWhiteSpace($DriverAppCenter))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\DriverAppCenter"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\DriverAppCenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$HelpDesk = (Get-AppxPackage | Where { $_.Name -Match 'msiappadm.MSIHelpDesk' })
if ([string]::IsNullOrWhiteSpace($HelpDesk))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\HelpDesk"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\HelpDesk_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Select Product
if ((-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct))) -or ($BaseBoardProduct.Product -eq 'Not Available'))
{
    [String]$Model = ($BaseBoardProduct.Product).ToString()
}

$MSICenter = (Get-AppxPackage | Where { $_.Name -Match '9426MICRO-STARINTERNATION.MSICenter' })
If (($Model -like '*Gaming*') -and ([string]::IsNullOrWhiteSpace($MSICenter)))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\MSICenter"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\MSICenter_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense -logpath $Log
}
