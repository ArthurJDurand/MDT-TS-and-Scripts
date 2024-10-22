# Define the path to WinRAR
$WinRAR = "X:\Program Files\WinRAR\WinRAR.exe"

# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# Define the source path for OEM apps
$OEMAppsSourcePath = if (Test-Path "\\SERVER\OEM\x86") {
    "\\SERVER\OEM\x86"
} else {
    $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
    if ($DeploymentDriveLetter) {
        Join-Path -Path "${DeploymentDriveLetter}:" -ChildPath "OEM\x86"
    } else {
        $null
    }
}

# Define the destination path for OEM apps if the WIndows drive letter is present
if ($WindowsDriveLetter) {
    $OEMAppsDestinationPath = Join-Path -Path "${WindowsDriveLetter}:\" -ChildPath "Recovery\OEM"

    # Get system information and define the system manufacturer
    $BaseBoardManufacturer = (Get-CimInstance Win32_BaseBoard).Manufacturer.Trim()
    $ComputerSystemPackageVendor = (Get-CimInstance -ClassName CIM_ComputerSystemPackage).Vendor.Trim()
    $ComputerSystemManufacturer = (Get-CimInstance -ClassName CIM_ComputerSystem).Manufacturer.Trim()
    $InvalidManufacturerValues = 'Default string', 'Not Applicable', 'Not Available', 'System Manufacturer', 'To be filled by O.E.M.'
    $Manufacturer = $BaseBoardManufacturer, $ComputerSystemPackageVendor, $ComputerSystemManufacturer | Where-Object {
        $_ -notin $InvalidManufacturerValues -and -not [string]::IsNullOrWhiteSpace($_)
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1 -ExpandProperty Name

    # Create the destination directory if it doesn't exist
    if (-not (Test-Path $OEMAppsDestinationPath)) {New-Item $OEMAppsDestinationPath -itemType Directory}

    # Determine the appropriate OEM apps based on the manufacturer
    $OEMAppPath = switch -Wildcard ($Manufacturer) {
        {$_ -like '*Acer*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Acer.7z"}
        {$_ -like '*ASUS*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "ASUS.7z"}
        {$_ -like '*Dell*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Dell.7z"}
        {$_ -like '*Dynabook*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Dynabook.7z"}
        {$_ -like '*Gigabyte*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Gigabyte.7z"}
        {$_ -like '*HP*' -or $_ -like '*Hewlett Packard*' -or $_ -like '*Hewlett-Packard*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "HP.7z"}
        {$_ -like '*Huawei*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Huawei.7z"}
        {$_ -like '*Lenovo*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Lenovo.7z"}
        {$_ -like '*Microsoft*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Microsoft.7z"}
        {$_ -like '*Micro-Star*' -or $_ -like '*MicroStar*' -or $_ -like '*MSI*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "MSI.7z"}
        {$_ -like '*Proline*'} {Join-Path -Path $OEMAppsSourcePath -ChildPath "Proline.7z"}
        default {Join-Path -Path $OEMAppsSourcePath -ChildPath "Default.7z"}
    }

    # Extract the appropriate OEM apps to the destination if both exists
    if ((Test-Path $OEMAppPath) -and (Test-Path $OEMAppsDestinationPath)) {
        Start-Process $WinRAR -ArgumentList "x -o+ `"$OEMAppPath`" $OEMAppsDestinationPath" -Wait
    }
}
