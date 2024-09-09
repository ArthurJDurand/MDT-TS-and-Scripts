# Function to move child-items from a source to a destination, removing existing items at the destination
function Move-ItemifExist {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )
    if (Test-Path $SourcePath) {
        Get-ChildItem -Path $SourcePath | ForEach-Object {
            $ItemPath = Join-Path -Path $DestinationPath -ChildPath $_.Name
            if (Test-Path $ItemPath) {
                Remove-Item -Path $ItemPath -Recurse -Force
            }
            Move-Item -Path $_.FullName -Destination $ItemPath -Force
        }
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

# Open the Windows Security app
Start-Process 'windowsdefender:' -WindowStyle Maximized

# Uninstall the Dell SupportAssist modern app
$SupportAssistUWP = Get-AppxPackage | Where-Object { $_.Name -Match 'DellInc.DellSupportAssistforPCs' }
if ($SupportAssistUWP) {
    Remove-AppxPackage -Package $SupportAssistUWP -AllUsers
}

# Uninstall Dell SupportAssist and restart
$SupportAssist = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -Match 'Dell SupportAssist'}
if ($SupportAssist) {
    $SupportAssist.Uninstall()
    Restart-Computer
    Exit
}

# Remove redundant directories
$PathsToRemove = @(
    "C:\Temp",
    "C:\Recovery\Customizations",
    "C:\Recovery\OEM\Point_*"
)

foreach ($Path in $PathsToRemove) {
    Remove-ItemifExist -Path $Path -Recurse
}

# Define the base scanstate path
$ScanStatePath = $null
while (-not $ScanStatePath) {
    if (Test-Path "\\SERVER\Shared\ScanState") {
        $BaseScanStatePath = "\\SERVER\Shared\ScanState"
    } else {
        $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
        if ($DeploymentDriveLetter) {
            $BaseScanStatePath = Join-Path -Path "${DeploymentDriveLetter}:" -ChildPath "ScanState"
        } else {
            Write-Host "Please switch on the deployment server or connect the deployment flash drive and press any key to continue."
            Read-Host "Press any key to continue."
            $BaseScanStatePath = $null
        }
    }

    # Define the scanstate path based on the OS version
    if ($BaseScanStatePath) {
        $OSCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        if ($OSCaption -like "*Windows 11*") {
            $ScanStatePath = Join-Path -Path $BaseScanStatePath -ChildPath "Win11\*"
        } elseif ($OSCaption -like "*Windows 10*") {
            $ScanStatePath = Join-Path -Path $BaseScanStatePath -ChildPath "Win10\x64\*"
        } else {
            $ScanStatePath = $null
        }
    }
}

# Copy files needed to deploy push button reset features to a temporary location
if ($BaseScanStatePath -and $ScanStatePath) {
    New-DirectoryIfNotExists -Path "C:\Temp\ScanState"
    Copy-Item -Path $ScanStatePath -Destination C:\Temp\ScanState -Force -Recurse
    Copy-Item -Path (Join-Path -Path $BaseScanStatePath -ChildPath "Custom\*.xml") -Destination C:\Temp\ScanState -Force
    Remove-ItemifExist -Path C:\Windows\Setup\Scripts -Recurse
    New-DirectoryIfNotExists -Path "C:\Windows\Setup\Scripts"
    Copy-Item -Path (Join-Path -Path $BaseScanStatePath -ChildPath "Custom\SetupComplete.cmd") -Destination C:\Windows\Setup\Scripts -Force
    if (Test-Path C:\Recovery\OEM) {
        New-DirectoryIfNotExists -Path "C:\Temp\OEM"
        Copy-Item -Path (Join-Path -Path $BaseScanStatePath -ChildPath "Custom\pre.ps1") -Destination C:\Temp\OEM -Force
    }
    if (Test-Path C:\Recovery\OEM\Apps\pbr.ps1) {
        New-DirectoryIfNotExists -Path "C:\Temp\OEM\Apps"
        Copy-Item -Path (Join-Path -Path $BaseScanStatePath -ChildPath "Custom\pbr.reg") -Destination C:\Temp\OEM\Apps -Force
    }
}

# Disable PCI Express Link State Power Management
powercfg -setacvalueindex scheme_current sub_pciexpress ee12f906-d277-404b-b6da-e5fa1a576df5 0

# Disable Ulps and Performance Settings for specific network adapters
$NetworkAdapterRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
if (Test-Path $NetworkAdapterRegistryPath) {
    Set-ItemProperty -Path $NetworkAdapterRegistryPath -Name "EnableUlps" -Value 0
    Set-ItemProperty -Path $NetworkAdapterRegistryPath -Name "PerformanceSettings" -Value 0
}

# Disable specific services
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\amdkmpfd") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\amdkmpfd" -Name "Start" -Value 0
}

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm" -Name "TdrLevel" -Value 0
}

# Repair Windows image health if necessary
$WindowsImageHealth = Repair-WindowsImage -Online -CheckHealth
if ($WindowsImageHealth.ImageHealthState -eq 'Repairable') {
    Repair-WindowsImage -Online -RestoreHealth
}

# Run System File Checker
SFC /SCANNOW

# Deploy the provisioning package
if (Test-Path "C:\Temp\ScanState\scanstate.exe") {
    New-DirectoryIfNotExists -Path "C:\Recovery\OEM\Logs"
    & C:\Temp\ScanState\scanstate.exe /apps /ppkg C:\Recovery\Customizations\usmt.ppkg /i:C:\Temp\ScanState\OEMCustomizations.xml /config:C:\Temp\ScanState\Config_AppsAndSettings.xml /o /c /v:13 /l:C:\Recovery\OEM\Logs\ScanState.log
    Remove-ItemifExist -Path "C:\Temp\ScanState" -Recurse
}

# Vaidate the USMT provisioning package
if (Test-Path "C:\Recovery\Customizations\usmt.ppkg" -PathType Leaf) {
    # Create autoapply folders and remove the extensibility points if the USMT provisioning package is valid
    $ProvisioningPackageInfo = & DISM /Online /Get-ProvisioningPackageInfo /PackagePath:"C:\Recovery\Customizations\usmt.ppkg"
    if ($ProvisioningPackageInfo -match "The operation completed successfully") {
        if (Test-Path C:\Recovery\OEM\unattend.xml) {
            New-DirectoryIfNotExists -Path "C:\Recovery\AutoApply"
            Move-Item -Path C:\Recovery\OEM\unattend.xml -Destination C:\Recovery\AutoApply -Force
        }

        $OSCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        if ($OSCaption -like "*Windows 11*") {
            if (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json) {
                New-DirectoryIfNotExists -Path "C:\Recovery\AutoApply"
                Copy-Item -Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json -Destination C:\Recovery\AutoApply -Force
            }
            if (Test-Path C:\Windows\OEM\TaskbarLayoutModification.xml) {
                New-DirectoryIfNotExists -Path "C:\Recovery\AutoApply"
                Copy-Item -Path C:\Windows\OEM\TaskbarLayoutModification.xml -Destination C:\Recovery\AutoApply -Force
            }
        }

        if ($OSCaption -like "*Windows 10*") {
            if (Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml) {
                New-DirectoryIfNotExists -Path "C:\Recovery\AutoApply"
                Copy-Item -Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml -Destination C:\Recovery\AutoApply -Force
            }
        }

        if (Get-ChildItem "C:\Windows\System32\oobe\info" -Recurse | Where-Object { $_.PSIsContainer -or $_ }) {
            New-DirectoryIfNotExists -Path "C:\Recovery\AutoApply\OOBE"
            Copy-Item -Path C:\Windows\System32\oobe\info\* -Destination C:\Recovery\AutoApply\OOBE -Force -Recurse
        }

        $PathsToRemove = @(
            "C:\Recovery\OEM\Apps\BingNews",
            "C:\Recovery\OEM\Apps\Extensions",
            "C:\Recovery\OEM\Apps\Todos",
            "C:\Recovery\OEM\Customizations",
            "C:\Recovery\OEM\Drivers",
            "C:\Recovery\OEM\LGPO",
            "C:\Recovery\OEM\StoreContent"
        )

        foreach ($Path in $PathsToRemove) {
            Remove-ItemifExist -Path $Path -Recurse
        }

        $FilesToRemove = @(
            "C:\Recovery\OEM\*.7z",
            "C:\Recovery\OEM\*.cmd",
            "C:\Recovery\OEM\*.ps1",
            "C:\Recovery\OEM\*.reg",
            "C:\Recovery\OEM\LayoutModification.*",
            "C:\Recovery\OEM\TaskbarLayoutModification.*",
            "C:\Recovery\OEM\Reset*.*",
            "C:\Recovery\OEM\Apps\Logs\*.*",
            "C:\Recovery\OEM\Apps\*.cmd",
            "C:\Recovery\OEM\Apps\*.exe",
            "C:\Recovery\OEM\Apps\*.msi",
            "C:\Recovery\OEM\Apps\*.reg",
            "C:\Recovery\OEM\Apps\DymaxIO*.*"
        )

        foreach ($File in $FilesToRemove) {
            Remove-ItemifExist -Path $File
        }

        Move-ItemifExist -SourcePath "C:\Temp\OEM\Apps" -DestinationPath "C:\Recovery\OEM\Apps"
        Remove-ItemifExist -Path "C:\Temp\OEM\Apps" -Recurse
        Move-ItemifExist -SourcePath "C:\Temp\OEM" -DestinationPath "C:\Recovery\OEM"
        Remove-ItemifExist -Path "C:\Temp\OEM" -Recurse
    }

    # Remove the following if the USMT provisioning package is invalid
    if ($PPkgInfo -match "The data is invalid") {
        Remove-ItemifExist -Path "C:\Recovery\Customizations" -Recurse
        Remove-ItemifExist -Path "C:\Recovery\OEM\Logs\MigLog.xml"
        Remove-ItemifExist -Path "C:\Recovery\OEM\Logs\ScanState.log"
    }
}

# Generate a battery report and save it to the desktop of the current user
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$BatteryPresent = Get-CimInstance -ClassName Win32_Battery
if ($BatteryPresent) {
    # Generate the battery report and save it to the desktop
    $ReportPath = Join-Path -Path $DesktopPath -ChildPath "Battery-Report.html"
    powercfg /batteryreport /output $ReportPath
}

# Remove the temporary directory
if (-not (Get-ChildItem "C:\Temp" -Recurse | Where-Object { $_.PSIsContainer -or $_ })) {
    Remove-ItemifExist C:\Temp -Recurse
}

# Remove this script
Remove-Item $PSCommandPath -Force
