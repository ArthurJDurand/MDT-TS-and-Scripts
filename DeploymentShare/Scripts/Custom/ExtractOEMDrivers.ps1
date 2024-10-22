# Define the path to WinRAR
$WinRAR = "X:\Program Files\WinRAR\WinRAR.exe"

# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# Define the source path for OEM drivers
$SrcDriversPath = if (Test-Path "\\SERVER\Shared\DriverPacks\*") {
    "\\SERVER\Shared\DriverPacks"
} else {
    $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
    if ($DeploymentDriveLetter) {
        Join-Path -Path "${DeploymentDriveLetter}:" -ChildPath "DriverPacks"
    } else {
        $null
    }
}

# Define the source and destination driver paths and extract the drivers if the Windows drive letter and the source driver path is present
if ($WindowsDriveLetter -and $SrcDriversPath) {
    # Get system information and define the system model
    $BaseBoardProduct = (Get-CimInstance Win32_BaseBoard).Product.Trim()
    $ComputerSystemProductVersion = (Get-CimInstance Win32_ComputerSystemProduct).Version.Trim()
    $ComputerSystemModel = (Get-CimInstance Win32_ComputerSystem).Model.Trim()
    $InvalidModelValues = 'Default string', 'Not Applicable', 'Not Available', 'System Product Name', 'System Version', 'To be filled by O.E.M.', 'Type1ProductConfigId'
    $Model = $BaseBoardProduct, $ComputerSystemProductVersion, $ComputerSystemModel | Where-Object {
        $_ -notin $InvalidModelValues -and -not [string]::IsNullOrWhiteSpace($_)
    } | Sort-Object Length -Descending | Select-Object -First 1

    # Get CPU name and generation
    $CPUName = (Get-CimInstance -ClassName Win32_Processor).Name
    $Gen = $CPUName | Select-String -Pattern "(\d+th Gen Intel)" | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Select-Object -First 1

    # Define the source drivers to extract
    $SrcDriversWithGen = if ($Gen) { Join-Path -Path $SrcDriversPath -ChildPath "$Model $Gen.7z" } else { $null }
    $SrcDriversWithoutGen = Join-Path -Path $SrcDriversPath -ChildPath "$Model.7z"

    if ($SrcDriversWithGen -and (Test-Path $SrcDriversWithGen)) {
        $SrcDrivers = $SrcDriversWithGen
    } elseif (Test-Path $SrcDriversWithoutGen) {
        $SrcDrivers = $SrcDriversWithoutGen
    } else {
        $SrcDrivers = $null
    }

    # Define the destination driver path
    $DstDriversPath = Join-Path -Path "$($WindowsDriveLetter):" -ChildPath "Recovery\OEM\Drivers"

    # Create the destination directory if it doesn't exist
    if (-not (Test-Path $DstDriversPath)) {
        New-Item -Path $DstDriversPath -ItemType Directory
    }

    # Extract the source drivers
    if ($SrcDrivers) {
        Start-Process -FilePath $WinRAR -ArgumentList "x -o+ `"$SrcDrivers`" `"$DstDriversPath`"" -Wait
    }
}
