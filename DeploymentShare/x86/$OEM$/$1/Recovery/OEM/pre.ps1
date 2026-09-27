<#
.SYNOPSIS
    OEM Setup (32‑bit): Complete system configuration with driver installation,
    application setup, Windows/Office activation, and system customization.

.VERSION
    2.1.0 (OOBE Resilience Update + Hardening)

.AUTHORS
    - Gemini (Primary Architect & Logic Optimization)
    - DeepSeek (Contributor - Resiliency Patterns & UWP Version Guards)

.NOTES
    LESSONS LEARNED & ARCHITECTURE DECISIONS (DO NOT REMOVE):
    1. UWP Versioning (0xc1570118): Modern Windows builds (24H2+) have newer inbox media extensions.
       We MUST check provisioned versions (Skip-IfNewerProvisioned) before Add-AppxProvisionedPackage.
    2. DISM Locks: AppX provisioning can fail if OOBE is running background tasks. 
       Implemented Exponential Backoff in Install-UWPApplication.
    3. MSI Collisions: Two MSIs executing back-to-back will throw errors if the Windows Installer 
       mutex isn't cleared. Wait-ForMSIMutex prevents this.
    4. AnyDesk Evaluation: AnyDesk installer now polls for binary presence; password config uses 
       exit codes checked via $LASTEXITCODE.
    5. RustDesk Evaluation: RustDesk ps1 config now uses exit codes; we check $LASTEXITCODE.
    6. OOBE CPU Thrashing: Added Wait-SystemIdle to allow the OS to breathe before heavy app installs.

    HARDENING APPLIED (v2.1.0):
    - Transcript wrapped in try/finally to guarantee Stop-Transcript.
    - RustDesk installer now polls for binary presence (no fixed 20s sleep, no hang risk).
    - AnyDesk installer now polls for binary presence (same hardened pattern as RustDesk).
    - All logs consolidated under C:\ProgramData\OEM\Logs.
    - Diskeeper license call standardized to full powershell.exe with -NonInteractive.
    - Folder attribute cleanup: removed +r from C:\Users\Default (safe +h only).
#>

[CmdletBinding()]
param()

# Enhanced tracking arrays
$Script:InstalledApps = @()
$Script:SkippedApps   = @()
$Script:FailedApps    = @()

# Define central directories and variables early for Transcript
$AppsDir = "C:\Recovery\OEM\Apps"
$Script:LogDir = "C:\ProgramData\OEM\Logs"   # Consolidated log location

# Ensure Log directory exists before starting transcript
if (-not (Test-Path -Path $Script:LogDir)) { New-Item -Path $Script:LogDir -ItemType Directory | Out-Null }

# Start Centralized Logging
$TranscriptPath = Join-Path $Script:LogDir "pre_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $TranscriptPath -Append -Force

try {
    #region Core Functions
    function Wait-SystemIdle {
        Write-Host "  [ ] Waiting for system CPU to settle..." -ForegroundColor Gray
        for ($i = 0; $i -lt 10; $i++) {
            $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
            if ($cpu -lt 85) { break }
            Start-Sleep -Seconds 3
        }
    }

    function Wait-ForMSIMutex {
        param([int]$TimeoutSeconds = 300)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            try {
                $null = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
                Start-Sleep -Seconds 2
            } catch {
                return $true # Mutex is clear
            }
        }
        Write-Host "  [⚠] MSI Mutex timeout reached." -ForegroundColor Yellow
        return $false
    }

    # Initialize the provisioned cache so Skip-IfNewerProvisioned works correctly
    $Script:ProvisionedCache = $null

    function Skip-IfNewerProvisioned {
        param(
            [string]$PackagePath,
            [string]$PackageName
        )
        $fileName = Split-Path $PackagePath -Leaf
        if ($fileName -match '_(\d+\.\d+\.\d+\.\d+)_') {
            $newVersion = [version]$Matches[1]
        } else { return $false }

        # Cache once per session
        if (-not $Script:ProvisionedCache) {
            $Script:ProvisionedCache = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        }

        $normalizedPackage = ($PackageName -replace '[^A-Za-z0-9\.]', '').ToLower()

        $existing = $Script:ProvisionedCache | Where-Object {
            $display = ($_.DisplayName -replace '[^A-Za-z0-9\.]', '').ToLower()
            $pkg     = ($_.PackageName -replace '[^A-Za-z0-9\.]', '').ToLower()
            return ($display.Contains($normalizedPackage) -or $pkg.Contains($normalizedPackage))
        } | Select-Object -First 1

        if ($existing -and [version]$existing.Version -ge $newVersion) {
            Write-Host "  [ℹ] Skipped $PackageName - OS already has $($existing.Version) (>= $newVersion)" -ForegroundColor DarkGray
            return $true
        }
        return $false
    }

    function Get-InstalledApplication {
        param ([Parameter(Mandatory = $true)][string]$AppName)
        # 32‑bit: only the native registry path
        $App = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match $AppName }
        if ($App) { return $App }

        $AppxPackage = Get-AppxPackage | Where-Object { $_.Name -match $AppName }
        if ($AppxPackage) { return $AppxPackage }
        return $null
    }

    function Get-InstallationPackages {
        param ([Parameter(Mandatory = $true)][string]$InstallationPath)
        if (Test-Path -Path $InstallationPath -PathType Container) {
            return Get-ChildItem -Path $InstallationPath -File | Where-Object {
                $_.Extension -in ".exe", ".msi", ".appx", ".appxbundle", ".msix", ".msixbundle"
            }
        } elseif (Test-Path -Path $InstallationPath -PathType Leaf) {
            return @((Get-Item -Path $InstallationPath))
        } else { return @() }
    }

    function Get-Manufacturer {
        if ($script:CachedManufacturer) { return $script:CachedManufacturer }
        $InvalidValues = 'Default string', 'Not Applicable', 'Not Available', 'System Manufacturer', 'To be filled by O.E.M.'
        $Values = @((Get-CimInstance Win32_BaseBoard).Manufacturer, (Get-CimInstance Win32_ComputerSystem).Manufacturer, (Get-CimInstance Win32_ComputerSystemProduct).Vendor) | 
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Where-Object { $_ -notin $InvalidValues }

        if (-not $Values) { $script:CachedManufacturer = 'Unknown'; return 'Unknown' }

        $Manufacturer = $Values | Group-Object | Sort-Object @{Expression={$_.Count};Descending=$true}, @{Expression={$_.Name};Descending=$false} | Select-Object -First 1 -ExpandProperty Name
        $script:CachedManufacturer = $Manufacturer
        return $Manufacturer
    }

    function Get-Model {
        param([switch]$ForceManufacturerRefresh)
        if ($ForceManufacturerRefresh) { $script:CachedManufacturer = $null }

        $InvalidValues = @('Default string', 'Not Applicable', 'Not Available', 'System Product Name', 'System Version', 'To be filled by O.E.M.', 'Type1ProductConfigId')
        $baseboardProduct = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        $csModel = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
        $cspName = (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Name
        $cspVersion = (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Version

        $Values = @($csModel, $cspName, $baseboardProduct, $cspVersion) |
            ForEach-Object { if ($_ -ne $null) { $_.ToString().Trim() } else { $null } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Where-Object { $_ -notin $InvalidValues }

        if (-not $Values -or $Values.Count -eq 0) { return $null }

        if ($Values.Count -gt 1) {
            $Manufacturer = Get-Manufacturer
            if ($Manufacturer -like '*Lenovo*') {
                $lenovoPattern = '^(IdeaPad|Legion|Lenovo|LOQ|ThinkBook|ThinkCentre|ThinkPad|Yoga)[\s\d\-]'
                $Model = $Values | Where-Object { $_ -match $lenovoPattern } | Select-Object -First 1
                if ($Model) { return $Model }
            }
            elseif ($Manufacturer -like '*Acer*') {
                $acerPattern = '^(Aspire|Extensa|Predator|Nitro|Swift|TravelMate|Spin|ConceptD|Acer|Veriton|Vero|One)[\s\d\-]'
                $excludeSuffixPattern = '_(ADU|BDS|BDN|BDZ|DEV|INT|SKU)$'
                $Model = $Values | Where-Object { $_ -match $acerPattern -and -not ($_ -match $excludeSuffixPattern) } | Select-Object -First 1
                if ($Model) { return $Model }
            }
        }
        return $Values | Sort-Object @{Expression = { $_.Length }; Descending = $true }, @{Expression = { $_ }; Descending = $false } | Select-Object -First 1
    }

    function Add-ToListUnique {
        param ([Parameter(Mandatory=$true)][ref]$ListRef, [Parameter(Mandatory=$true)][string]$Value)
        if (-not ([string]::IsNullOrWhiteSpace($Value))) {
            if (-not ($ListRef.Value -contains $Value)) { $ListRef.Value += $Value }
        }
    }

    function Install-Application {
        param (
            [Parameter(Mandatory = $true)][string]$AppName,
            [Parameter(Mandatory = $true)][string]$InstallationPath,
            [Parameter(Mandatory = $false)][string]$Arguments,
            [Parameter(Mandatory = $false)][string]$LogFileName,
            [Parameter(Mandatory = $false)][string[]]$ConflictingApp,
            [Parameter(Mandatory = $false)][switch]$NoNewWindow
        )

        Write-Host "Processing: $AppName" -ForegroundColor Cyan

        $InstallationPackages = Get-InstallationPackages -InstallationPath $InstallationPath
        if (-not $InstallationPackages) { 
            Write-Host "  [✗] No installation packages found" -ForegroundColor Red
            Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value $AppName
            return $false 
        }

        if ($ConflictingApp) {
            foreach ($App in $ConflictingApp) {
                if (Get-InstalledApplication -AppName $App) {
                    Write-Host "  [⚠] Skipped (conflict with: $App)" -ForegroundColor Yellow
                    Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value $AppName
                    return $false
                }
            }
        }

        $AppAlreadyInstalled = Get-InstalledApplication -AppName $AppName
        $WasInstalled = $false

        foreach ($InstallationPackage in $InstallationPackages) {
            $Extension = $InstallationPackage.Extension

            if (-not $AppAlreadyInstalled -and $Extension -in ".exe", ".msi") {
                $ExitCode = Install-DesktopApplication -InstallationPackage $InstallationPackage.FullName -Arguments $Arguments -NoNewWindow:$NoNewWindow
                if ($ExitCode -eq 0) { 
                    $WasInstalled = $true 
                    Write-Host "  [✓] Successfully installed" -ForegroundColor Green
                    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value $AppName
                }
            }

            if (-not $AppAlreadyInstalled -and $Extension -in ".appx", ".appxbundle", ".msix", ".msixbundle") {
                $didInstall = Install-UWPApplication -InstallationPackage $InstallationPackage.FullName -LogFileName $LogFileName -DependencyPackages $Script:Dependencies -LogDirectory $Script:LogDir
                if ($didInstall) {
                    $WasInstalled = $true
                    Write-Host "  [✓] Successfully installed" -ForegroundColor Green
                    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value $AppName
                } else {
                    $AppAlreadyInstalled = $true # Treated as already installed/skipped
                }
            }
        }

        if (-not $WasInstalled -and $AppAlreadyInstalled) {
            Write-Host "  [ℹ] Already installed" -ForegroundColor Gray
            Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value $AppName
        }

        if (-not $WasInstalled -and -not $AppAlreadyInstalled) {
            Write-Host "  [✗] Installation failed" -ForegroundColor Red
            Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Install Failed)"
        }

        return $WasInstalled
    }

    function Install-DesktopApplication {
        param (
            [Parameter(Mandatory = $true)][string]$InstallationPackage,
            [Parameter(Mandatory = $false)][string]$Arguments,
            [Parameter(Mandatory = $false)][switch]$NoNewWindow
        )

        # MSI Mutex Check Before Execution
        if ($InstallationPackage -match '\.msi$' -or $InstallationPackage -match '\.exe$') {
            Wait-ForMSIMutex | Out-Null
        }

        $StartProcessArgs = @{
            FilePath     = $InstallationPackage
            ArgumentList = $Arguments
            Wait         = $true
            PassThru     = $true
        }
        if ($NoNewWindow) { $StartProcessArgs.NoNewWindow = $true }

        $Process = Start-Process @StartProcessArgs
        return $Process.ExitCode
    }

    function Install-LayoutModification {
        param ([Parameter(Mandatory = $true)][string]$DirectoryPath)
        Write-Host "Processing layout modification" -ForegroundColor Cyan

        if ($OSCaption -like "*Windows 10*") {
            $LayoutModification = (Join-Path $DirectoryPath 'LayoutModification.xml')
            if (Test-Path $LayoutModification) {
                Copy-Item $LayoutModification -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force -ErrorAction SilentlyContinue
                Write-Host "  [✓] Applied Windows 10 LayoutModification.xml" -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Layout: $(Split-Path $DirectoryPath -Leaf)"
            }
        }
    }

    function Install-UWPApplication {
        param (
            [Parameter(Mandatory = $true)][string]$InstallationPackage,
            [Parameter(Mandatory = $true)][string]$LogFileName,
            [Parameter(Mandatory = $false)][string[]]$DependencyPackages,
            [Parameter(Mandatory = $false)][string]$LogDirectory
        )

        $packageBaseName = (Split-Path $InstallationPackage -Leaf) -replace '_.*'

        if (Skip-IfNewerProvisioned -PackagePath $InstallationPackage -PackageName $packageBaseName) {
            return $false
        }

        $maxRetries = 3
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                if ($DependencyPackages) {
                    Add-AppxProvisionedPackage -Online -PackagePath $InstallationPackage -DependencyPackagePath $DependencyPackages -SkipLicense -LogPath (Join-Path $LogDirectory $LogFileName) -ErrorAction Stop
                } else {
                    Add-AppxProvisionedPackage -Online -PackagePath $InstallationPackage -SkipLicense -LogPath (Join-Path $LogDirectory $LogFileName) -ErrorAction Stop
                }
                return $true
            } catch {
                $errMsg = $_.Exception.Message
                if ($errMsg -match "Element not found" -or $errMsg -match "0xc1570118") {
                    Write-Host "  [ℹ] OS rejected package natively (already installed). Skipping." -ForegroundColor DarkGray
                    return $false
                }
                if ($i -lt $maxRetries) {
                    Write-Host "  [⚠] UWP Install failed (DISM Lock). Retrying in $(3 * $i)s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds (3 * $i)
                } else {
                    Write-Host "  [✗] UWP Install failed after $maxRetries attempts." -ForegroundColor Red
                    return $false
                }
            }
        }
    }

    # Improved Import-RegistrySettings with try/finally for safe hive unloading
    function Import-RegistrySettings {
        param (
            [Parameter(Mandatory = $true)][string[]]$RegFile,
            [Parameter(Mandatory = $false)][string]$AppName,
            [switch]$LoadDefaultUserHive,
            [switch]$PrerequisiteApp
        )
        if ($PrerequisiteApp -and $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('AppName')) {
            $App = Get-InstalledApplication -AppName $AppName
            if (-not $App) { Write-Host "  [⚠] Prerequisite app not found: $AppName" -ForegroundColor Yellow; return }
        }
        if ($LoadDefaultUserHive) { reg LOAD HKLM\temp C:\Users\Default\ntuser.dat }
        try {
            if (Test-Path $RegFile) { reg import $RegFile; Write-Host "  [✓] Imported registry file: $(Split-Path $RegFile -Leaf)" -ForegroundColor Green }
        } finally {
            if ($LoadDefaultUserHive) { reg UNLOAD HKLM\temp }
        }
    }

    function New-DirectoryIfNotExists {
        param ([Parameter(Mandatory = $true)][string]$Path)
        if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -ItemType Directory | Out-Null }
    }

    function Remove-ItemIfExist {
        param ([Parameter(Mandatory = $true)][string]$Path)
        if (Test-Path $Path) {
            if (Test-Path $Path -PathType Container) { Remove-Item -Path $Path -Force -Recurse }
            else { Remove-Item -Path $Path -Force }
            Write-Host "  [✓] Removed: $Path" -ForegroundColor Green
        }
    }

    # Improved Set-RegistryValue with try/finally for safe hive unloading
    function Set-RegistryValue {
        param (
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Value,
            [Parameter(Mandatory = $true)][ValidateSet("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord")][string]$Type,
            [switch]$LoadDefaultUserHive
        )
        if ($LoadDefaultUserHive) { reg LOAD HKLM\temp C:\Users\Default\ntuser.dat }
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            $CurrentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
            if ($null -eq $CurrentValue -or $CurrentValue -ne $Value) {
                New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction SilentlyContinue
                Write-Host "  [✓] Set registry value: $Path\$Name = $Value" -ForegroundColor Green
            }
        } finally {
            if ($LoadDefaultUserHive) { reg UNLOAD HKLM\temp }
        }
    }

    function Write-CleanSummary {
        Write-Host "`n" + "="*50 -ForegroundColor Yellow
        Write-Host "INSTALLATION SUMMARY" -ForegroundColor Yellow
        Write-Host "="*50 -ForegroundColor Yellow

        if ($Script:InstalledApps.Count -gt 0) {
            Write-Host "`n✅ SUCCESSFULLY INSTALLED ($($Script:InstalledApps.Count)):" -ForegroundColor Green
            $Script:InstalledApps | Sort-Object | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
        }
        if ($Script:SkippedApps.Count -gt 0) {
            Write-Host "`n⚠️  SKIPPED ($($Script:SkippedApps.Count)):" -ForegroundColor Yellow
            $Script:SkippedApps | Sort-Object | ForEach-Object { Write-Host "  ⚠ $_" -ForegroundColor Yellow }
        }
        if ($Script:FailedApps.Count -gt 0) {
            Write-Host "`n❌ FAILED ($($Script:FailedApps.Count)):" -ForegroundColor Red
            $Script:FailedApps | Sort-Object | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
        }

        Write-Host "`n" + "="*50 -ForegroundColor Yellow
        Write-Host "QUICK OVERVIEW" -ForegroundColor Cyan
        Write-Host "="*50 -ForegroundColor Yellow

        $totalProcessed = $Script:InstalledApps.Count + $Script:SkippedApps.Count + $Script:FailedApps.Count
        Write-Host "  Installed: $($Script:InstalledApps.Count)" -ForegroundColor Green
        Write-Host "  Skipped:   $($Script:SkippedApps.Count)" -ForegroundColor Yellow
        Write-Host "  Failed:    $($Script:FailedApps.Count)" -ForegroundColor Red

        if ($totalProcessed -gt 0) {
            $successRate = [math]::Round(($Script:InstalledApps.Count / $totalProcessed) * 100, 1)
            $color = if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" }
            Write-Host "  Success rate: $successRate%" -ForegroundColor $color
        }

        Write-Host "="*50 -ForegroundColor Yellow

        if ($Script:FailedApps.Count -eq 0 -and $Script:InstalledApps.Count -gt 0) {
            Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
        } elseif ($Script:FailedApps.Count -gt 0) {
            Write-Host "`n⚠️  Deployment completed with errors" -ForegroundColor Yellow
        } else {
            Write-Host "`nℹ️  No applications were installed" -ForegroundColor Cyan
        }
    }

    function Activate-Windows {
        $SLP = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
        if ($SLP.LicenseStatus -eq 1 -and $SLP.Description -notlike '*KMS*') { return $true }

        $EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $SLS = Get-CimInstance -ClassName SoftwareLicensingService
        
        if ($SLS.OA3xOriginalProductKey -and $SLS.OA3xOriginalProductKeyDescription -like "*$EditionId*") {
            cscript.exe "$env:WinDir\System32\slmgr.vbs" /ipk $SLS.OA3xOriginalProductKey | Out-Null
            cscript.exe "$env:WinDir\System32\slmgr.vbs" /ato | Out-Null
            return $true
        }

        $ActivationScript = 'C:\Recovery\OEM\Activation\HWID_Activation.cmd'
        if (Test-Path $ActivationScript) {
            & cmd /c "$ActivationScript /HWID"
            return $true
        }
        return $false
    }

    function Test-OfficeInstalled {
        foreach ($Ver in 12..16) {
            $Path = Join-Path "HKLM:\Software\Microsoft\Office\$Ver.0\Common\InstallRoot" 'Path'
            if (Test-Path $Path) { return $true }
        }
        $C2rKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        if ((Test-Path $C2rKey) -and (Get-ItemPropertyValue -Path $C2rKey -Name VersionToReport -ErrorAction SilentlyContinue)) { return $true }
        return $false
    }

    function Get-OfficeInstallerFolder {
        $Root = 'C:\Recovery\OEM\Apps'
        if (-not (Test-Path $Root)) { return $null }
        $Dirs = Get-ChildItem -Path $Root -Directory -Filter 'Office*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        return $Dirs | Select-Object -First 1
    }

    function Install-Office {
        param([string]$InstallerPath)
        $SetupPath = Join-Path $InstallerPath 'setup.exe'
        $ConfigPath = Join-Path $InstallerPath 'configuration.xml'
        if ((-not (Test-Path $SetupPath)) -or (-not (Test-Path $ConfigPath))) { return $false }
        Push-Location $InstallerPath
        $Process = Start-Process -FilePath $SetupPath -ArgumentList '/configure configuration.xml' -Wait -PassThru
        Pop-Location
        return $Process.ExitCode -eq 0
    }

    function Activate-Office {
        $ActivationScript = 'C:\Recovery\OEM\Activation\Ohook_Activation.cmd'
        if (-not (Test-Path $ActivationScript)) { return $false }
        Add-MpPreference -ExclusionPath $ActivationScript -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess (Split-Path $ActivationScript -Leaf) -ErrorAction SilentlyContinue
        Write-Host "[*] Running Office activation script..." -ForegroundColor Cyan
        $Process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$ActivationScript /Ohook`"" -Wait -PassThru
        if ($Process.ExitCode -eq 0) {
            Write-Host "[✓] Office activated successfully." -ForegroundColor Green
            Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Office Activation"
            return $true
        } else {
            Write-Host "[✗] Office activation failed (ExitCode=$($Process.ExitCode))." -ForegroundColor Red
            Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "Office Activation"
            return $false
        }
    }
    #endregion

    #region Initialization
    Write-Host "==============================================" -ForegroundColor Yellow
    Write-Host "          OEM Setup Initialization           " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow

    $OSCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
    $Model = Get-Model
    $Manufacturer = Get-Manufacturer
    $Drivers = "C:\Recovery\OEM\Drivers"
    $DependencyDir = Join-Path -Path $AppsDir -ChildPath "Dependencies"
    $Script:Dependencies = Get-ChildItem -Path $DependencyDir -Filter "*.appx" | Select-Object -ExpandProperty FullName

    New-DirectoryIfNotExists -Path "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"

    Write-Host "[✓] System initialized" -ForegroundColor Green
    Write-Host "    OS: $OSCaption" -ForegroundColor Gray
    Write-Host "    Model: $Model" -ForegroundColor Gray
    Write-Host "    Manufacturer: $Manufacturer" -ForegroundColor Gray
    #endregion

    #region Main Execution
    Write-Host "==============================================" -ForegroundColor Yellow
    Write-Host "            Beginning OEM Setup               " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow

    Write-Host "[ ] Configuring Windows Defender..." -ForegroundColor Cyan
    Set-MPPreference -PUAProtection Enabled
    Add-MpPreference -ExclusionPath "C:\Recovery"
    Write-Host "[✓] Windows Defender configured" -ForegroundColor Green

    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker" -Name "PreventDeviceEncryption" -Value 1 -Type "DWord"

    if ($Model) {
        Write-Host "[ ] Installing OEM drivers for $Model..." -ForegroundColor Cyan
        $OEMDrivers = Join-Path -Path $Drivers -ChildPath $Model

        if (-not (Test-Path $OEMDrivers)) {
            Write-Host "  [ℹ] Trying fallback wildcard matching..." -ForegroundColor Yellow
            $BestMatch = Get-ChildItem -Path $Drivers | Where-Object { $_.Name -like "*$($Model -replace ' ', '*')*" } | Sort-Object Name | Select-Object -First 1
            if ($BestMatch) {
                $OEMDrivers = $BestMatch.FullName
                Write-Host "  [✓] Found driver folder via fallback: $($BestMatch.Name)" -ForegroundColor Green
            }
        }

        if ($OEMDrivers -and (Test-Path $OEMDrivers)) {
            Write-Host "  [📁] Installing drivers from: $(Split-Path $OEMDrivers -Leaf)" -ForegroundColor Cyan
            Get-ChildItem -Path $OEMDrivers -Recurse -Filter *.inf | ForEach-Object { pnputil /add-driver $_.FullName /install }
            Write-Host "[✓] OEM drivers installed" -ForegroundColor Green
            Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "OEM Drivers"
        } else {
            Write-Host "[⚠] No OEM drivers found for $Model" -ForegroundColor Yellow
            Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "OEM Drivers"
        }
    }

    Write-Host "[ ] Installing WLAN drivers..." -ForegroundColor Cyan
    $WLANDrivers = Join-Path -Path $Drivers -ChildPath "WLAN"
    if (Test-Path $WLANDrivers) {
        Get-ChildItem -Path $WLANDrivers -Recurse -Filter *.inf | ForEach-Object { pnputil /add-driver $_.FullName /install }
        Write-Host "[✓] WLAN drivers installed" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "WLAN Drivers"
    } else {
        Write-Host "[⚠] No WLAN drivers found" -ForegroundColor Yellow
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "WLAN Drivers"
    }

    Write-Host "[ ] Importing group policy settings..." -ForegroundColor Cyan
    if (Test-Path "C:\Recovery\OEM\LGPO\LGPO.exe") {
        & "C:\Recovery\OEM\LGPO\LGPO.exe" /g "C:\Recovery\OEM\LGPO\Backup"
        Write-Host "[✓] Group policy settings imported" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Group Policy"
    } else {
        Write-Host "[⚠] LGPO.exe not found" -ForegroundColor Yellow
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Group Policy"
    }

    if ($Model) { Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "Model" -Value $Model -Type "String" }

    Write-Host "[ ] Importing registry settings..." -ForegroundColor Cyan
    $RegFiles = "DesktopIcons.reg", "gpsFix.reg", "OEMInfo.reg", "RegionalSettings.reg"
    $RegFilePaths = $RegFiles | ForEach-Object { Join-Path "C:\Recovery\OEM" $_ }
    foreach ($File in $RegFilePaths) { if (Test-Path $File) { Import-RegistrySettings -RegFile $File -LoadDefaultUserHive } }

    if ($OSCaption -like "*Windows 10*") {
        Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type "DWord" -LoadDefaultUserHive
        Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisablePreviewDesktop" -Value 0 -Type "DWord" -LoadDefaultUserHive
        Set-RegistryValue -Path "HKLM:\temp\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Value 0 -Type "DWord" -LoadDefaultUserHive
    }

    Install-LayoutModification -DirectoryPath C:\Recovery\OEM

    Write-Host "[ ] Activating Windows..." -ForegroundColor Cyan
    if (Activate-Windows) {
        Write-Host "[✓] Windows activated successfully" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Windows Activation"
    } else {
        Write-Host "[⚠] Windows activation failed or not required" -ForegroundColor Yellow
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Windows Activation"
    }

    Write-Host "[ ] Checking for Office installation..." -ForegroundColor Cyan
    if (-not (Test-OfficeInstalled)) {
        Write-Host "[ ] Checking for Office installers..." -ForegroundColor Cyan
        $InstallerDir = Get-OfficeInstallerFolder
        if ($InstallerDir) {
            Write-Host "[ ] Found Office installer: $($InstallerDir.Name)" -ForegroundColor Cyan
            if (Install-Office -InstallerPath $InstallerDir.FullName) {
                Write-Host "[✓] Office installed successfully" -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Microsoft Office"
            } else {
                Write-Host "[✗] Office installation failed" -ForegroundColor Red
                Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "Microsoft Office"
            }
        } else {
            Write-Host "[⚠] No Office installer found" -ForegroundColor Yellow
            Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Microsoft Office"
        }
    } else {
        Write-Host "[✓] Office is already installed" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Microsoft Office"
    }

    Write-Host "[ ] Copying Office shortcuts..." -ForegroundColor Cyan
    $AppNames = "Access", "Excel", "PowerPoint", "Project", "Publisher", "Visio", "Word"
    foreach ($AppName in $AppNames) {
        $SourcePath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
        $DestinationPath = "C:\Users\Public\Desktop\$AppName.lnk"
        if ((Test-Path $SourcePath) -and (-not (Test-Path $DestinationPath))) { Copy-Item -Path $SourcePath -Destination $DestinationPath -Force }
    }
    Write-Host "[✓] Office shortcuts copied" -ForegroundColor Green

    if (Test-OfficeInstalled) { Activate-Office | Out-Null }

    # Ensure System is calm before massive application deployments
    Wait-SystemIdle

    Install-Application -AppName "Microsoft.Todos" -InstallationPath (Join-Path $AppsDir "Todos") -LogFileName "Todos_UWP.log"

    if ($OSCaption -like "*Windows 10*") {
        Install-Application -AppName "Microsoft.OutlookForWindows" -InstallationPath (Join-Path $AppsDir "Outlook") -LogFileName "OutlookForWindows_UWP.log"
    }

    if ($OSCaption -like '*Windows 10*') {
        Write-Host "[ ] Removing legacy apps..." -ForegroundColor Cyan
        $AppxNames = @("Microsoft.windowscommunicationsapps", "Microsoft.People", "Microsoft.Office.OneNote")
        foreach ($Appx in $AppxNames) {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "$Appx*" | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName }
            Get-AppxPackage -AllUsers | Where-Object Name -like "$Appx*" | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers }
        }
        Write-Host "[✓] Legacy apps removed" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Legacy Apps Cleanup"
    }

    if ($OSCaption -like "*Windows 10*") {
        Install-Application -AppName "Microsoft.BingNews" -InstallationPath (Join-Path $AppsDir "BingNews") -LogFileName "News_UWP.log"
    }

    Write-Host "[ ] Installing media extensions..." -ForegroundColor Cyan
    $Extensions = @(
        @{Name = "Microsoft.AV1VideoExtension"; Log = "AV1VideoExtension_UWP.log" },
        @{Name = "Microsoft.HEIFImageExtension"; Log = "HEIFImageExtension_UWP.log" },
        @{Name = "Microsoft.HEVCVideoExtension"; Log = "Microsoft.HEVCVideoExtension_UWP.log" },
        @{Name = "Microsoft.MPEG2VideoExtension"; Log = "MPEG2VideoExtension_UWP.log" },
        @{Name = "Microsoft.RawImageExtension"; Log = "RawImageExtension_UWP.log" },
        @{Name = "Microsoft.VP9VideoExtensions"; Log = "VP9VideoExtensions_UWP.log" },
        @{Name = "Microsoft.WebMediaExtensions"; Log = "WebMediaExtensions_UWP.log" },
        @{Name = "Microsoft.WebpImageExtension"; Log = "WebpImageExtension_UWP.log" }
    )
    foreach ($Extension in $Extensions) { Install-Application -AppName $Extension.Name -InstallationPath (Join-Path $AppsDir "Extensions") -LogFileName $Extension.Log }
    Write-Host "[✓] Media extensions processed" -ForegroundColor Green

    #region AnyDesk Installation (Hardened with polling)
    Write-Host "[ ] Installing and configuring AnyDesk..." -ForegroundColor Cyan
    $AnyDeskInstaller = Join-Path $AppsDir "AnyDesk.exe"
    $AppName = "AnyDesk"

    if (Test-Path $AnyDeskInstaller) {
        Write-Host "  [$AppName] Launching silent installer..." -ForegroundColor Gray
        # Launch the installer (no -Wait needed)
        Start-Process -FilePath $AnyDeskInstaller `
            -ArgumentList '--install "C:\Program Files\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon'

        # Poll for the installed binary (up to 60 seconds)
        $Timeout = 60
        $Elapsed = 0
        $AnyDeskExe = Join-Path ${env:ProgramFiles(x86)} 'AnyDesk\anydesk.exe'
        while (-not (Test-Path $AnyDeskExe) -and $Elapsed -lt $Timeout) {
            Start-Sleep -Seconds 2
            $Elapsed += 2
        }

        if (-not (Test-Path $AnyDeskExe)) {
            Write-Host "  [✗] AnyDesk installation timed out." -ForegroundColor Red
            Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Install Timeout)"
        } else {
            Write-Host "  [✓] AnyDesk installed." -ForegroundColor Green

            Write-Host "  [$AppName] Setting permanent password..." -ForegroundColor Gray
            $AnyDeskPassword = 'p@$$w0rd'   # Replace with secure retrieval if needed
            try {
                # Set password via stdin (same as the original cmd script)
                $AnyDeskPassword | & $AnyDeskExe --set-password
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [✓] $AppName password configured successfully." -ForegroundColor Green
                    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value $AppName
                } else {
                    Write-Host "  [✗] $AppName password configuration failed (ExitCode: $LASTEXITCODE)." -ForegroundColor Red
                    Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Config)"
                }
            } catch {
                Write-Host "  [✗] $AppName password configuration error: $($_.Exception.Message)" -ForegroundColor Red
                Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Config)"
            }
        }
    } else {
        Write-Host "  [✗] $AppName installer not found at: $AnyDeskInstaller" -ForegroundColor Red
        Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Installer Missing)"
    }
    #endregion

    #region RustDesk Installation (Hardened with polling)
    Write-Host "[ ] Installing and configuring RustDesk..." -ForegroundColor Cyan
    $RustDeskInstaller = Join-Path $AppsDir "RustDesk.exe"
    $AppName = "RustDesk"

    if (Test-Path $RustDeskInstaller) {
        Wait-ForMSIMutex | Out-Null
        Write-Host "  [$AppName] Launching silent installer..." -ForegroundColor Gray
        Start-Process -FilePath $RustDeskInstaller -ArgumentList "--silent-install"
        
        $Timeout = 60
        $Elapsed = 0
        $InstalledPath = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
        while (-not (Test-Path $InstalledPath) -and $Elapsed -lt $Timeout) {
            Start-Sleep -Seconds 2
            $Elapsed += 2
        }
        if (Test-Path $InstalledPath) {
            Write-Host "  [✓] RustDesk installed. Waiting 5 seconds for service registration..." -ForegroundColor Green
            Start-Sleep -Seconds 5
        }
        if (-not (Test-Path $InstalledPath)) {
            Write-Host "  [✗] RustDesk installation timed out." -ForegroundColor Red
            Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Install Timeout)"
        } else {
            Write-Host "  [✓] RustDesk installed." -ForegroundColor Green
        }
    } else {
        Write-Host "  [✗] $AppName installer not found at: $RustDeskInstaller" -ForegroundColor Red
        Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Installer Missing)"
    }

    $RustDeskConfigScript = Join-Path $AppsDir "RustDesk.ps1"
    if (Test-Path $RustDeskConfigScript) {
        if (Test-Path $InstalledPath) {
            Write-Host "  [$AppName] Applying configuration..." -ForegroundColor Gray
            $global:LASTEXITCODE = $null

            # IMPORTANT: Run the script in a separate PowerShell process to contain its exit code
            # and prevent it from killing the parent session (because it uses 'exit').
            try {
                powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RustDeskConfigScript
                $exitCode = $LASTEXITCODE
            } catch {
                Write-Host "  [✗] Failed to launch RustDesk configuration script: $($_.Exception.Message)" -ForegroundColor Red
                $exitCode = 999
            }

            switch ($exitCode) {
                0 {
                    Write-Host "  [✓] $AppName setup completed successfully (full persistence)." -ForegroundColor Green
                    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value $AppName
                }
                1 {
                    Write-Host "  [!] $AppName partial success – check password or config file." -ForegroundColor Yellow
                    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "$AppName (Partial Config)"
                }
                2 {
                    Write-Host "  [✗] $AppName configuration failed completely." -ForegroundColor Red
                    Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Config)"
                }
                default {
                    Write-Host "  [✗] $AppName unexpected exit code: $exitCode" -ForegroundColor Red
                    Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "$AppName (Unknown error)"
                }
            }
        } else {
            Write-Host "  [✗] Skipping configuration – RustDesk not installed." -ForegroundColor Yellow
        }
    }
    #endregion

    Install-Application -AppName "7-Zip" -InstallationPath (Join-Path $AppsDir "7z.exe") -Arguments "/S"

    $WinRARInstalled = Install-Application -AppName "WinRAR" -InstallationPath "$AppsDir\winrar.exe" -Arguments "/s"
    if ($WinRARInstalled) {
        Start-Process -FilePath (Join-Path $AppsDir "rarreg.exe") -Wait
        Import-RegistrySettings -RegFile (Join-Path $AppsDir "WinRAR.reg") -AppName "WinRAR" -LoadDefaultUserHive
    }

    $DiskeeperInstalled = Install-Application -AppName "Diskeeper" -InstallationPath "$AppsDir\Diskeeper.exe" -Arguments '/s /v"/qn"' -NoNewWindow
    if ($DiskeeperInstalled) {
        Write-Host "  [ ] Running Diskeeper licensing script..." -ForegroundColor Gray
        $global:LASTEXITCODE = $null
        & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $AppsDir "DiskeeperLicense.ps1")
        $licenseExitCode = $LASTEXITCODE

        switch ($licenseExitCode) {
            0 {
                Write-Host "  [✓] Diskeeper licensed successfully." -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Diskeeper License"
                Import-RegistrySettings -RegFile (Join-Path $AppsDir "Diskeeper.reg") -AppName "Diskeeper" -LoadDefaultUserHive
            }
            2 {
                Write-Host "  [i] Diskeeper licensing skipped (application not detected)." -ForegroundColor Gray
                Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Diskeeper License"
            }
            default {
                Write-Host "  [✗] Diskeeper licensing failed (exit code $licenseExitCode)." -ForegroundColor Red
                Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "Diskeeper License"
            }
        }
    }

    $HDD = Get-PhysicalDisk | Select-Object DeviceID, Friendlyname, BusType, MediaType | Where-Object MediaType -eq 'HDD'
    if ($HDD) {
        $DriveMonitorInstalled = Install-Application -AppName "Acronis Drive Monitor" -InstallationPath (Join-Path $AppsDir "DriveMonitor.msi") -Arguments "/qn /norestart /l*v $(Join-Path $Script:LogDir 'DriveMonitor_Install.log')"
        if ($DriveMonitorInstalled) {
            Remove-ItemIfExist -Path "C:\Users\Public\Desktop\Acronis Drive Monitor.lnk"
            Import-RegistrySettings -RegFile (Join-Path $AppsDir "DriveMonitor.reg") -AppName "Acronis Drive Monitor"
        }
    }

    Write-Host "[ ] Checking Windows RE status..." -ForegroundColor Cyan
    $WinREStatus = (reagentc /info | Select-String -Pattern "Windows RE status").ToString().Split(":")[1].Trim()
    if ($WinREStatus -eq "Disabled") {
        reagentc.exe /enable
        Write-Host "[✓] Windows RE enabled" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Windows RE"
    } else {
        Write-Host "[✓] Windows RE is already enabled" -ForegroundColor Green
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Windows RE"
    }

    Write-Host "[ ] Setting system attributes..." -ForegroundColor Cyan
    attrib C:\ProgramData +h +i
    # Safe: +h only, no +r
    attrib C:\Users\Default +h
    attrib C:\Users\Default\NTUSER.DAT +a +h +i
    attrib C:\Users\Default\AppData +h
    Write-Host "[✓] System attributes set" -ForegroundColor Green
    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "System Attributes"

    Write-Host "[ ] Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-ItemIfExist -Path "C:\_SMSTaskSequence"
    Remove-ItemIfExist -Path "C:\MININT"
    Remove-ItemIfExist -Path "C:\LTIBootstrap.vbs"
    Write-Host "[✓] Temporary files cleaned up" -ForegroundColor Green
    Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Cleanup"

    Write-CleanSummary
    Write-Host "`nScript execution completed." -ForegroundColor Gray
    #endregion
}
finally {
    # Guarantee transcript stops even on crash
    Stop-Transcript
}
#endregion
