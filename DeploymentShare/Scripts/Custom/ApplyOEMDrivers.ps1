# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# Define the paths
if ($WindowsDriveLetter) {
    $WindowsImage = "${WindowsDriveLetter}:"
    $Drivers = "${WindowsDriveLetter}:\Recovery\OEM\Drivers"
    $WLANDrivers = Join-Path -Path $Drivers -ChildPath "WLAN"

    # Get system information and define the system model
    $BaseBoardProduct = (Get-CimInstance Win32_BaseBoard).Product.Trim()
    $ComputerSystemProductVersion = (Get-CimInstance Win32_ComputerSystemProduct).Version.Trim()
    $ComputerSystemModel = (Get-CimInstance Win32_ComputerSystem).Model.Trim()
    $InvalidModelValues = 'Default string', 'Not Applicable', 'Not Available', 'System Product Name', 'System Version', 'To be filled by O.E.M.', 'Type1ProductConfigId'

    $Model = $BaseBoardProduct, $ComputerSystemProductVersion, $ComputerSystemModel | Where-Object {
        $_ -notin $InvalidModelValues -and -not [string]::IsNullOrWhiteSpace($_)
    } | Sort-Object Length -Descending | Select-Object -First 1

    # Define the OEM drivers path
    if ($Model) {
        $OEMDrivers = Join-Path -Path $Drivers -ChildPath $Model

        # Add the OEM drivers if they exist
        if (Test-Path $OEMDrivers) {
            DISM /Image:$WindowsImage /Add-Driver /Driver:$OEMDrivers /recurse
        }

        # Add the WLAN drivers if they exist
        if (Test-Path $WLANDrivers) {
            DISM /Image:$WindowsImage /Add-Driver /Driver:$WLANDrivers /recurse
        }

        # Get the CPU name
        $CPUName = (Get-CimInstance -ClassName Win32_Processor).Name

        # Define the storage driver based on processor name
        if ($CPUName -match "\bCore Ultra\b") {
            $StorageDrivers = Join-Path -Path $Drivers -ChildPath "Storage\Intel\VMD\20.0.0.1038.3"
        } elseif ($CPUName -match "\b(11|12|13)th Gen\b") {
            $StorageDrivers = Join-Path -Path $Drivers -ChildPath "Storage\Intel\VMD\19.5.2.1049.5"
        }

        # Add the Storage Drivers if they exist
        if ($StorageDrivers) {
            if (Test-Path $StorageDrivers) {
                DISM /Image:$WindowsImage /Add-Driver /Driver:$StorageDrivers /recurse
            }
        }
    }
}
