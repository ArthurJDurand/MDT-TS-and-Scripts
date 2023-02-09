#Microsoft Corp. FEB 2023

$SurfaceHub = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.SurfaceHub' })

if ([string]::IsNullOrWhiteSpace($SurfaceHub))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SurfaceHub"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\SurfaceHub\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx*" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\SurfaceHub_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}

$SurfaceDiagnostics = (Get-AppxPackage | Where { $_.Name -Match 'Microsoft.SurfaceDiagnostics' })

if ([string]::IsNullOrWhiteSpace($SurfaceDiagnostics))
{
    $PackageFolderPath = "C:\Recovery\OEM\Apps\SurfaceDiagnostics"
    $Package = Get-ChildItem -File $PackageFolderPath | Select-Object -ExpandProperty FullName
    $DependencyFolderPath = "C:\Recovery\OEM\Apps\SurfaceDiagnostics\Dependencies"
    $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx*" | Select-Object -ExpandProperty FullName
    $Log = "C:\Recovery\OEM\Apps\Logs\SurfaceDiagnostics_UWP.log"
    Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -logpath $Log
}
