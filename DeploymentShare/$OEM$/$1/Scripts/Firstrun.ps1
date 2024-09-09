# Function to open an app and set window properties
function Open-AppAndSetWindow {
    param (
        [string]$AppPath,
        [string]$WindowTitle
    )

    # Start the application
    Start-Process $AppPath
    
    # Give the app some time to open
    Start-Sleep -Seconds 3
    
    # Get the process of the opened app
    $App = Get-Process | Where-Object MainWindowTitle -match $WindowTitle
    
    # P/Invoke code to show the window
    $PInvokeCode = @"
[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
    $PInvoke = Add-Type -MemberDefinition $PInvokeCode -Name User32 -Namespace Win32Functions -PassThru
    
    # Set the window state (3 = maximize)
    $PInvoke::ShowWindow($App.MainWindowHandle, 3)
}

# Function to get the Program Files path and Registry path based on architecture
function Get-ProgramFilesPathAndRegistryPath {
    # Get the system architecture
    $Architecture = (Get-CimInstance Win32_Processor).AddressWidth
    
    # Set paths based on architecture
    if ($Architecture -eq 64) {
        return @{
            ProgramFilesPath = 'C:\Program Files (x86)'
            RegistryPath = 'HKLM\SOFTWARE\WOW6432Node'
        }
    } else {
        return @{
            ProgramFilesPath = 'C:\Program Files'
            RegistryPath = 'HKLM\SOFTWARE'
        }
    }
}

# Open required apps and set window focus
Open-AppAndSetWindow "ms-settings:windowsupdate" "Settings"
Open-AppAndSetWindow "ms-windows-store://home" "Microsoft Store"
Open-AppAndSetWindow "windowsdefender:DeviceSecurity" "Windows Security"

# Check for AnyDesk and DriveMonitor
$Paths = Get-ProgramFilesPathAndRegistryPath
$AnyDesk = Join-Path $Paths.ProgramFilesPath 'AnyDesk\AnyDesk.exe'
$DriveMonitor = Join-Path $Paths.ProgramFilesPath 'Acronis\DriveMonitor\adm_console.exe'

# Start AnyDesk if installed
if (Test-Path $AnyDesk) {
    Start-Process $AnyDesk
}

# Start DriveMonitor if installed and export its settings
if (Test-Path $DriveMonitor) {
    Start-Process $DriveMonitor
    Write-Host "Please configure Acronis Drive Monitor Settings before continuing!"
    Pause
    reg export (Join-Path $Paths.RegistryPath 'Acronis\DriveMonitor\Settings') C:\Recovery\OEM\Apps\DriveMonitor.reg /y
}

# Run update commands directly
# Scan for updates and install them
Invoke-Expression -Command "usoclient.exe ScanInstallWait"
Invoke-Expression -Command "usoclient.exe StartInstall"

# Upgrade all apps using winget
winget upgrade --all --accept-source-agreements --accept-package-agreements -s msstore

# Remove this script
Remove-Item $PSCommandPath -Force
