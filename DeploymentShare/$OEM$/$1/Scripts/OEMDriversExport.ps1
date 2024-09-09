# Define paths
$DriversBasePath = "C:\Temp\Drivers"
$7Zip = "C:\Program Files\7-Zip\7z.exe"

# Function to create a directory that doesn't exist
function New-DirectoryIfNotExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory
    }
}

# Function to remove an existing item at a given path
function Remove-ItemifExist {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,  # The path of the item to remove
        [switch]$Recurse  # Whether to remove an item recursively
    )
    if (Test-Path $Path) {
        Remove-Item $Path -Force -Recurse:$Recurse
    }
}

# Get system information and define the system model
$BaseBoardProduct = (Get-CimInstance Win32_BaseBoard).Product.Trim()
$ComputerSystemProductVersion = (Get-CimInstance Win32_ComputerSystemProduct).Version.Trim()
$ComputerSystemModel = (Get-CimInstance Win32_ComputerSystem).Model.Trim()
$InvalidModelValues = 'Default string', 'Not Applicable', 'Not Available', 'System Product Name', 'System Version', 'To be filled by O.E.M.', 'Type1ProductConfigId'
$Model = $BaseBoardProduct, $ComputerSystemProductVersion, $ComputerSystemModel | Where-Object {
    $_ -notin $InvalidModelValues -and -not [string]::IsNullOrWhiteSpace($_)
} | Sort-Object Length -Descending | Select-Object -First 1

$DriversPath = Join-Path $DriversBasePath $Model

# Get CPU name and generation and define the drivers path
$Gen = (Get-CimInstance -ClassName Win32_Processor).Name | Select-String -Pattern "(\d+th Gen Intel)" | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Select-Object -First 1

$Archive = if ($Gen) {
    "$DriversPath $Gen.7z"
} else {
    "$DriversPath.7z"
}

# Ensure the drivers path is clean and create a new directory
Remove-ItemifExist -Path $DriversBasePath -Recurse
New-DirectoryIfNotExists -Path $DriversPath

# Export drivers
if (Test-Path $DriversPath) {
    pnputil /export-driver * $DriversPath
}

# Remove printer drivers
Remove-ItemifExist -Path "$DriversPath\prn*" -Recurse

# Compress drivers
if (Test-Path $7Zip) {
    do {
        & $7Zip a -mx9 -ssw $Archive $DriversPath
        & $7Zip t $Archive
        if ($LASTEXITCODE -ne 0) {
            Remove-ItemifExist -Path $Archive
        }
    } while ($LASTEXITCODE -ne 0)
}

# Define DriverPack path and ensure its existence
$DriverPackPath = $null
while (-not $DriverPackPath) {
    if (Test-Path '\\SERVER\Shared\DriverPacks') {
        $DriverPackPath = '\\SERVER\Shared\DriverPacks'
    } else {
        $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
        if ($DeploymentDriveLetter) {
            $DriverPackPath = "${DeploymentDriveLetter}:\DriverPacks"
        } else {
            Write-Host "Please switch on the deployment server or connect the deployment flash drive and press any key to continue."
            $null = Read-Host "Press any key to continue."
        }
    }
}

New-DirectoryIfNotExists -Path $DriverPackPath

# Copy archive to DriverPack path
if (Test-Path $Archive) {
    Copy-Item -Path $Archive -Destination $DriverPackPath -Force
}

# Validate and recopy if needed
$DestinationArchive = Join-Path -Path $DriverPackPath -ChildPath (Split-Path -Path $Archive -Leaf)
if (Test-Path $Archive) {
    do {
        if (-not (Test-Path $DestinationArchive)) {
            Copy-Item -Path $Archive -Destination $DriverPackPath -Force
        }
        & $7Zip t $DestinationArchive
        if ($LASTEXITCODE -ne 0) {
            Remove-ItemifExist -Path $DestinationArchive
        }
    } while ($LASTEXITCODE -ne 0)
}

# Remove the temporary directory
Remove-ItemifExist -Path $Archive
Remove-ItemifExist -Path $DriversBasePath -Recurse
if (-not (Get-ChildItem "C:\Temp" -Recurse | Where-Object { $_.PSIsContainer -or $_ })) {
    Remove-ItemifExist -Path C:\Temp -Recurse
}

# Remove this script
Remove-Item $PSCommandPath -Force
