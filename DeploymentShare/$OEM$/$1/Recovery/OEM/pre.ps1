# Function to get installed application
function Get-InstalledApplication {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $registryPaths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction Stop | Where-Object { $_.DisplayName -match $AppName }
        if ($App) {
            return $App
        }
    }
}

# Function to import registry settings for an application if installed
function Import-AppRegistrySettingsIfInstalled {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$true)]
        [string]$RegFilePath
    )
    $App = Get-InstalledApplication -AppName $AppName
    if ($App) {
        reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
        reg import $RegFilePath
        reg UNLOAD HKLM\temp
    }
}

# Function to import registry settings if files exist
function Import-RegistrySettings {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$Files,
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    foreach ($File in $Files) {
        $FilePath = Join-Path -Path $Path -ChildPath $File
        if (Test-Path $FilePath) {
            reg import $FilePath
        }
    }
}

# Function to install appx packages if not already installed
function Install-AppxPackageIfNotInstalled {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PackageName,
        [Parameter(Mandatory=$true)]
        [string]$PackageFolderPath,
        [Parameter(Mandatory=$true)]
        [string]$LogFileName
    )

    if (-not (Get-AppxPackage | Where-Object { $_.Name -match $PackageName })) {
        $Package = Get-ChildItem -File "$PackageFolderPath\$PackageName*.*" | Select-Object -ExpandProperty FullName
        $Log = Join-Path -Path C:\Recovery\OEM\Apps\Logs -ChildPath $LogFileName
        $DependencyFolderPath = "C:\Recovery\OEM\Apps\Dependencies"
        $Dependencies = Get-ChildItem -Path $DependencyFolderPath -Filter "*.appx" | Select-Object -ExpandProperty FullName
        Add-AppxProvisionedPackage -Online -PackagePath $Package -DependencyPackagePath $Dependencies -SkipLicense -LogPath $Log
    }
}

# Function to install an application if not already installed
function Install-ApplicationIfNotInstalled {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath,
        [Parameter(Mandatory=$true)]
        [string]$Arguments
    )
    $App = Get-InstalledApplication -AppName $AppName
    if (-not $App) {
        Start-Process $InstallerPath -ArgumentList $Arguments -Wait
    }
}

# Function to create a directory if it doesn't exist
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
        [string]$Path,
        [switch]$Recurse
    )
    if (Test-Path $Path) {
        Remove-Item $Path -Force -Recurse:$Recurse
    }
}

# Function to create or update registry values
function Set-RegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [Parameter(Mandatory=$true)]
        [string]$Type
    )

    $CurrentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue

    if ($null -eq $CurrentValue) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force
    } else {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
    }
}

# Create directories if they do not exist
New-DirectoryIfNotExists -Path "C:\Recovery\OEM\Apps\Logs"
New-DirectoryIfNotExists -Path "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"

# Enable PUA Protection and add the recovery environment to Windows Security's exclusions
Set-MPPreference -PUAProtection Enabled
Add-MpPreference -ExclusionPath "C:\Recovery"

# Import group policy settings
& "C:\Recovery\OEM\LGPO\LGPO.exe" /g "C:\Recovery\OEM\LGPO\Backup"

# Get system information and define the system model
$BaseBoardProduct = (Get-CimInstance Win32_BaseBoard).Product.Trim()
$ComputerSystemProductVersion = (Get-CimInstance Win32_ComputerSystemProduct).Version.Trim()
$ComputerSystemModel = (Get-CimInstance Win32_ComputerSystem).Model.Trim()
$InvalidModelValues = 'Default string', 'Not Applicable', 'Not Available', 'System Product Name', 'System Version', 'To be filled by O.E.M.', 'Type1ProductConfigId'
$Model = $BaseBoardProduct, $ComputerSystemProductVersion, $ComputerSystemModel | Where-Object {
    $_ -notin $InvalidModelValues -and -not [string]::IsNullOrWhiteSpace($_)
} | Sort-Object Length -Descending | Select-Object -First 1

# Install OEM drivers if present
$DriversPath = "C:\Recovery\OEM\Drivers"
if ($Model) {
    $OEMDrivers = Join-Path -Path $DriversPath -ChildPath $Model

    # Add the OEM drivers if present
    if (Test-Path $OEMDrivers) {
        Get-ChildItem -Path $OEMDrivers -Recurse -Filter *.inf | ForEach-Object {
            pnputil /add-driver $_.FullName /install
        }
    }
}

# Install WLAN drivers if present
$WLANDrivers = Join-Path -Path $DriversPath -ChildPath WLAN
if (Test-Path $WLANDrivers) {
    Get-ChildItem -Path $WLANDrivers -Recurse -Filter *.inf | ForEach-Object {
        pnputil /add-driver $_.FullName /install
    }
}

# Install Storage drivers if present and necessary
if ($CPUName -match "\b(10|[1-9][0-9])th Gen\b") {
    $StorageDrivers = Join-Path -Path $DriversPath -ChildPath Storage
    if (Test-Path $StorageDrivers) {
        Get-ChildItem -Path $StorageDrivers -Recurse -Filter *.inf | ForEach-Object {
            pnputil /add-driver $_.FullName /install
        }
    }
}

# Load the default user's registry hive
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat

# Import additional registry settings if files exist
Import-RegistrySettings -Files @("DesktopIcons.reg", "gpsFix.reg", "OEMInfo.reg", "RegionalSettings.reg") -Path "C:\Recovery\OEM"

# Set OEM model information in the registry
if ($Model) {
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "Model" -Value $Model -Type  "String"
}

# Get the Windows version
$OSCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption

# Apply settings for Windows 10
if ($OSCaption -like "*Windows 10*") {
    Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type "DWord"
    Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisablePreviewDesktop" -Value 0 -Type "DWord"
    Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type "DWord"
    Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Value 0 -Type "DWord"
}

# Unload the registry hive
reg UNLOAD HKLM\temp

if ($OSCaption -like "*Windows 11*") {
    # Check and copy LayoutModification.json if it doesn't already exist
    if ((Test-Path C:\Recovery\OEM\LayoutModification.json) -and -not (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json)) {
        Copy-Item C:\Recovery\OEM\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
    }
    # Check and copy TaskbarLayoutModification.xml if it doesn't already exist
    if ((Test-Path C:\Recovery\OEM\TaskbarLayoutModification.xml) -and -not (Test-Path C:\Windows\OEM\TaskbarLayoutModification.xml)) {
        New-DirectoryIfNotExists -Path "C:\Windows\OEM"
        Copy-Item C:\Recovery\OEM\TaskbarLayoutModification.xml -Destination C:\Windows\OEM -Force
    }
    # Set the Taskbar layout if the file exists
    if (Test-Path C:\Windows\OEM\TaskbarLayoutModification.xml) {
        Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name LayoutXMLPath -Value C:\Windows\OEM\TaskbarLayoutModification.xml -Force
        Import-StartLayout -LayoutPath C:\Windows\OEM\TaskbarLayoutModification.xml -Mountpath $env:SystemDrive\
    }
} elseif ($OSCaption -like "*Windows 10*") {
    # Check and copy LayoutModification.xml if it doesn't already exist
    if ((Test-Path C:\Recovery\OEM\LayoutModification.xml) -and -not (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml)) {
        Copy-Item C:\Recovery\OEM\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
    }
}

# Activate Windows with the original product key if present
$SLS = Get-CimInstance -ClassName SoftwareLicensingService
$OPKD = $SLS.OA3xOriginalProductKeyDescription
$OPK = $SLS.OA3xOriginalProductKey
if ($OPKD -like "*Professional*" -and -not [string]::IsNullOrWhiteSpace($OPK)) {
    cscript C:\Windows\System32\slmgr.vbs /ipk $OPK
    cscript C:\Windows\System32\slmgr.vbs /ato
}

# Activate Windows with a digital license if not already activated with a digital license
$LicenseInfo = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1 LicenseStatus
$IsKMSActivated = $LicenseInfo.Description -like "*KMS*"
if ($LicenseInfo.LicenseStatus -ne 1 -or $IsKMSActivated) {
    if (Test-Path "C:\Recovery\OEM\Activation\HWID_Activation.cmd") {
        & cmd /c "C:\Recovery\OEM\Activation\HWID_Activation.cmd /HWID"
    }
}

# Install or reinstall Office if necessary
$Office365 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -Match 'Microsoft 365 - en-us' }
$Office365Path = "C:\Recovery\OEM\Apps\Office365"

if ([string]::IsNullOrWhiteSpace($Office365) -and (Test-Path $Office365Path) -and (Test-Path "$Office365Path\setup.exe")) {
    Push-Location -Path $Office365Path
    & .\setup.exe /configure .\configuration.xml
    Pop-Location
}

# Copy Office app shortcuts to the all user's desktop
$AppNames = "Access", "Excel", "PowerPoint", "Project", "Publisher", "Visio", "Word"
foreach ($AppName in $AppNames) {
    $SourcePath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
    $DestinationPath = "C:\Users\Public\Desktop\$AppName.lnk"
    if ((Test-Path $SourcePath) -and (-not (Test-Path $DestinationPath))) {
        Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
    }
}

# Install To Do if not present
$Todos = Get-AppxPackage | Where-Object { $_.Name -match 'Microsoft.Todos' }
if (-not $Todos) {
    Install-AppxPackageIfNotInstalled -PackageName "Microsoft.Todos" -PackageFolderPath "C:\Recovery\OEM\Apps\Todos" -LogFileName "Todos_UWP.log"
}

# Install Bing News if not present on Windows 10
$OSCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
if ($OSCaption -like "*Windows 10*") {
    $BingNews = Get-AppxPackage | Where-Object { $_.Name -match 'Microsoft.BingNews' }
    if (-not $BingNews) {
        Install-AppxPackageIfNotInstalled -PackageName "Microsoft.BingNews" -PackageFolderPath "C:\Recovery\OEM\Apps\BingNews" -LogFileName "News_UWP.log"
    }
}

# Install various extensions if not present
$Extensions = @(
    @{Name="Microsoft.AV1VideoExtension"; Log="AV1VideoExtension_UWP.log"},
    @{Name="Microsoft.HEIFImageExtension"; Log="HEIFImageExtension_UWP.log"},
    @{Name="Microsoft.HEVCVideoExtensions"; Log="HEVCVideoExtension_UWP.log"},
    @{Name="Microsoft.MPEG2VideoExtension"; Log="MPEG2VideoExtension_UWP.log"},
    @{Name="Microsoft.RawImageExtension"; Log="RawImageExtension_UWP.log"},
    @{Name="Microsoft.VP9VideoExtensions"; Log="VP9VideoExtensions_UWP.log"},
    @{Name="Microsoft.WebMediaExtensions"; Log="WebMediaExtensions_UWP.log"},
    @{Name="Microsoft.WebpImageExtension"; Log="WebpImageExtension_UWP.log"}
)

foreach ($Extension in $Extensions) {
    Install-AppxPackageIfNotInstalled -PackageName $Extension.Name -PackageFolderPath "C:\Recovery\OEM\Apps\Extensions" -LogFileName $Extension.Log
}

$AnyDesk = Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -Match 'AnyDesk' }
if (-not $AnyDesk) {
    Get-Process -Name "AnyDesk" -ErrorAction SilentlyContinue | Stop-Process -Force
    & cmd /c C:\Recovery\OEM\Apps\AnyDesk.cmd
}

# Install 7-Zip if not installed
Install-ApplicationIfNotInstalled -AppName '7-Zip' -InstallerPath "C:\Recovery\OEM\Apps\7z.exe" -Arguments "/S"

# Install WinRAR if not installed and import settings
Install-ApplicationIfNotInstalled -AppName 'WinRAR' -InstallerPath "C:\Recovery\OEM\Apps\winrar.exe" -Arguments "/s"
Start-Process C:\Recovery\OEM\Apps\rarreg.exe -Wait

# Import WinRAR settings if installed
Import-AppRegistrySettingsIfInstalled -AppName 'WinRAR' -RegFilePath "C:\Recovery\OEM\Apps\WinRARSettings.reg"

# Install DymaxIO if not installed
Install-ApplicationIfNotInstalled -AppName 'DymaxIO' -InstallerPath "C:\Recovery\OEM\Apps\DymaxIO.exe" -Arguments '/s /v"/qn"'
powershell -ExecutionPolicy bypass -File C:\Recovery\OEM\Apps\DymaxIOLicense.ps1

# Import DymaxIO settings if installed
Import-AppRegistrySettingsIfInstalled -AppName 'DymaxIO' -RegFilePath "C:\Recovery\OEM\Apps\DymaxIO.reg"

# Install Acronis Drive Monitor not already installed and if necessary
$HDD = Get-PhysicalDisk | Select-Object DeviceID, Friendlyname, BusType, MediaType | Where-Object MediaType -eq 'HDD'
if ($HDD) {
    Install-ApplicationIfNotInstalled -AppName 'Acronis Drive Monitor' -InstallerPath "C:\Recovery\OEM\Apps\DriveMonitor.msi" -Arguments "/qn /norestart /l*v C:\Recovery\OEM\Apps\Logs\DriveMonitor_Install.log"
    Remove-ItemifExist -Path "C:\Users\Public\Desktop\Acronis Drive Monitor.lnk"
}

# Import Acronis Drive Monitor settings if installed
Import-AppRegistrySettingsIfInstalled -AppName 'Acronis Drive Monitor' -RegFilePath "C:\Recovery\OEM\Apps\DriveMonitor.reg"

# Check the Windows RE status and enable Windows RE if disabled
$WinREStatus = (reagentc /info | Select-String -Pattern "Windows RE status").ToString().Split(":")[1].Trim()
if ($WinREStatus -eq "Disabled") {
    reagentc.exe /enable
}

# Set attributes for the Default user and its contents
attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h

# Remove files and folders
Remove-ItemifExist -Path "C:\_SMSTaskSequence" -Recurse
Remove-ItemifExist -Path "C:\MININT" -Recurse
Remove-ItemifExist -Path "C:\LTIBootstrap.vbs"

# Disable BitLocker
Get-BitLockerVolume | Disable-BitLocker
