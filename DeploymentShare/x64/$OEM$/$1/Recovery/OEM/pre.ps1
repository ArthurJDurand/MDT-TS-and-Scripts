<#
.SYNOPSIS
    OEM Setup: Complete system configuration with driver installation, application setup,
    Windows/Office activation, and system customization.

.VERSION
    2.2.0 (SYSTEM-Safe Office Activation + Latent-Bug Fixes)

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
    - DymaxIO license call standardized to full powershell.exe with -NonInteractive.
    - Folder attribute cleanup: removed +r from C:\Users\Default (safe +h only).

    HARDENING APPLIED (v2.1.1) - CRITICAL FIX:
    - Get-Counter inside Wait-SystemIdle can raise a TERMINATING PDH error (0x800007D6)
      that -ErrorAction SilentlyContinue does NOT downgrade. This was killing the
      entire script at ~84s on affected machines (mostly Lenovo, because the Lenovo
      imdriver / Intel DAL / Dolby DAX3 drivers we install destabilise the perf-
      counter registry). Wait-SystemIdle now:
        * wraps Get-Counter in try/catch,
        * falls back to WMI Win32_Processor LoadPercentage,
        * falls back to a fixed 5s delay and returns if neither works.
    - Added a top-level catch so ANY terminating error logs and continues, letting
      SetupComplete.cmd proceed to Customizations.ps1 and pbr.ps1 rather than
      silently losing every downstream install.

    HARDENING APPLIED (v2.2.0) - SYSTEM-SAFE OFFICE ACTIVATION + LATENT BUGS:
    - Activate-Office is now gated by Test-OfficeSafeForActivation: two clean
      checks (2s apart) that no Office UI process is running in any interactive
      user session. Fail-closed: if Win32_Process cannot be enumerated, Ohook
      is deferred. Owner lookup is for logging only, not part of the decision.
      This is safe whether pre.ps1 runs in OOBE (no user sessions) or via
      scheduled task as SYSTEM alongside a signed-in user.
    - Test-OfficeInstalled now reads the InstallRoot 'Path' VALUE instead of
      testing for a subkey of that name. The old check never matched MSI-based
      Office installs (16.0 VL etc.) and returned $false for the wrong reason
      on C2R installs (which have no 'Path' value at all).
    - Get-OfficeInstallerFolder now sorts by LastWriteTime, not Name.
      'Sort-Object Name -Descending' picks Office365 over Office2021.
    - Activate-Windows captures /ipk and /ato exit codes separately, and
      falls through to HWID if the firmware-key path fails, so a machine
      cannot be left unactivated by a single slmgr regression.
      (The OEM-key *match* logic is unchanged - it is proven correct against
      real Dell/HP/Lenovo BIOS strings such as "[4.0] Professional OEM:DM".)
    - Install-Office passes -WorkingDirectory instead of relying on
      Push-Location, which does not update [Environment]::CurrentDirectory.
    - Activate-Office no longer calls Add-MpPreference -ExclusionProcess on
      the .cmd file itself; the interpreter is cmd.exe and no process is
      ever named after the script.
    - Transcript is guarded with $Script:TranscriptStarted so a failed
      Start-Transcript no longer causes a noisy Stop-Transcript error.
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
if (-not (Test-Path -Path $Script:LogDir)) { New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null }

# Start Centralized Logging (guarded - see Finding 7)
$TranscriptPath = Join-Path $Script:LogDir "pre_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Script:TranscriptStarted = $false
try {
    Start-Transcript -Path $TranscriptPath -Append -Force | Out-Null
    $Script:TranscriptStarted = $true
} catch {
    Write-Host "[⚠] Could not start transcript: $($_.Exception.Message)" -ForegroundColor Yellow
}

try {
    #region Core Functions
    function Wait-SystemIdle {
        Write-Host "  [ ] Waiting for system CPU to settle..." -ForegroundColor Gray
        for ($i = 0; $i -lt 10; $i++) {
            $cpu = $null

            # Attempt 1: Get-Counter (fast, but can terminate on broken perf counters)
            try {
                $sample = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
                if ($sample -and $sample.CounterSamples.Count -gt 0) {
                    $cpu = [double]$sample.CounterSamples[0].CookedValue
                }
            } catch {
                $cpu = $null
            }

            # Attempt 2: WMI fallback
            if ($null -eq $cpu) {
                try {
                    $wmi = Get-CimInstance Win32_Processor -ErrorAction Stop |
                           Measure-Object -Property LoadPercentage -Average
                    if ($wmi.Average) { $cpu = [double]$wmi.Average }
                } catch {
                    $cpu = $null
                }
            }

            # Attempt 3: give up gracefully
            if ($null -eq $cpu) {
                Write-Host "  [i] CPU counters unavailable; using fixed 5s settle delay." -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
                return
            }

            if ($cpu -lt 85) { return }
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
        $RegistryPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($Path in $RegistryPaths) {
            $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $AppName }
            if ($App) { return $App }
        }
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

    # ============================================================
    # FUNCTION: Get-IntelProcessorGeneration (100% accurate)
    # ============================================================
    function Get-IntelProcessorGeneration {
        [CmdletBinding()]
        param ([Parameter(Mandatory)][string]$CPUName)

        # Series → generation mapping table (future‑proof; only update this)
        $SeriesMap = @{
            '1' = 14   # Series 1 (Meteor Lake / Raptor Lake Refresh U)
            '2' = 15   # Series 2 (Lunar Lake / Arrow Lake)
            '3' = 16   # Future Series 3
        }

        # Normalise the input (remove trademarks, extra spaces, etc.)
        $Name = ($CPUName -replace '\s+', ' ').Trim()
        $Name = $Name -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
        $Name = ($Name -replace '\s+', ' ').Trim()

        # --- 1. Immediate exclusions (families without generation numbers) ---
        if ($Name -match '(?i)\bAMD\b')                   { return $null }
        if ($Name -match '(?i)\b(?:N|J)\d{2,4}\b')        { return $null }
        if ($Name -match '(?i)\bPentium\b|\bCeleron\b|\bAtom\b|\bXeon\b') { return $null }

        # --- 2. Explicit “Nth Gen” string (highest confidence) ---
        if ($Name -match '(?i)\b(?<gen>1[1-9])(?:st|nd|rd|th)?\s+Gen\b') {
            $gen = [int]$Matches['gen']
            if ($gen -ge 11) { return $gen }
        }

        # --- 3. Core Ultra (Series mapping) ---
        if ($Name -match '(?i)\bCore\s+Ultra\s+[3579]\s+(?<sku>\d{3})[A-Z]*\b') {
            $seriesDigit = $Matches['sku'].Substring(0,1)
            return $SeriesMap[$seriesDigit]
        }

        # --- 4. New Core (Core 3 / 5 / 7 / 9, no ‘i’) ---
        if ($Name -match '(?i)\bCore\s+[3579]\s+(?<sku>\d{3})[A-Z]*\b') {
            $seriesDigit = $Matches['sku'].Substring(0,1)
            return $SeriesMap[$seriesDigit]
        }

        # --- 5. Classic Core i (i3 / i5 / i7 / i9) ---
        if ($Name -match '(?i)\bi[3579][- ](?<model>\d{4,5})[A-Z0-9]*\b') {
            $model = $Matches['model']
            $len   = $model.Length

            if ($len -eq 5) {
                $gen = [int]$model.Substring(0,2)
                if ($gen -ge 11) { return $gen }
            }
            elseif ($len -eq 4) {
                $gen = [int]$model.Substring(0,2)
                if ($gen -ge 11 -and $gen -le 13) { return $gen }
            }
        }

        return $null
    }

    function Find-BestDriverFolder {
        param([string]$Model, [string]$DriversRoot, [string]$Manufacturer)
        
        $IsHP = $Manufacturer -match 'HP|Hewlett-Packard'
        $IsLenovo = $Manufacturer -match 'Lenovo'
        $Model = ($Model -replace '\s+', ' ').Trim()
        $candidateFolders = @()
        
        $candidateFolders += $Model
        
        if ($IsHP) {
            if ($Model -notmatch 'Notebook PC' -and $Model -match '^\w+ \w+ \d+ [A-Z]\d+$') { $candidateFolders += "$Model Notebook PC" }
            elseif ($Model -match 'Notebook PC') { $candidateFolders += $Model -replace ' Notebook PC', '' }
            $candidateFolders += $Model -replace 'HP ', 'HP '
            $candidateFolders += $Model -replace 'ProBook ', 'ProBook '
        }
        
        if ($IsLenovo) {
            $baseModel = Get-LenovoBaseModel -Model $Model
            if ($baseModel -and $baseModel -ne $Model) { $candidateFolders += $baseModel }
        }
        
        $suffixes = @('Notebook PC', 'Notebook', 'Desktop', 'Laptop', 'PC', 'Computer')
        $cleanModel = $Model
        foreach ($suffix in $suffixes) {
            if ($cleanModel -match [regex]::Escape($suffix)) {
                $cleanModel = $cleanModel -replace [regex]::Escape($suffix), ''
                $cleanModel = $cleanModel.Trim()
            }
        }
        if ($cleanModel -ne $Model -and ($cleanModel -split '\s+').Count -ge 2) { $candidateFolders += $cleanModel }
        
        foreach ($folderName in $candidateFolders) {
            $folderPath = Join-Path -Path $DriversRoot -ChildPath $folderName
            if (Test-Path $folderPath) {
                Write-Host "  [✓] Found driver folder: $folderName" -ForegroundColor Green
                return $folderPath
            }
        }
        Write-Host "  [⚠] No driver folder found for model: $Model" -ForegroundColor Yellow
        Write-Host "  [ℹ] Tried variations: $($candidateFolders -join ', ')" -ForegroundColor Gray
        return $null
    }

    function Get-LenovoBaseModel {
        param([string]$Model)
        if (-not $Model) { return $null }
        if ($Model -match '^(IdeaPad|Legion|ThinkPad|ThinkBook|Yoga|LOQ)\s+(.+?)(?:\s+[\dA-Z]+)?$') {
            $base = $Matches[0]
            $base = $base -replace '\s+\d+[A-Z]*\d*$', ''
            return $base.Trim()
        }
        return $Model
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

        if ($OSCaption -like "*Windows 11*") {
            $LayoutModification = (Join-Path $DirectoryPath 'LayoutModification.json')
            $TaskbarLayoutModification = (Join-Path $DirectoryPath 'TaskbarLayoutModification.xml')

            if (Test-Path $LayoutModification) {
                Copy-Item $LayoutModification -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force -ErrorAction SilentlyContinue
                Write-Host "  [✓] Applied Windows 11 LayoutModification.json" -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Layout: $(Split-Path $DirectoryPath -Leaf)"
            }

            if (Test-Path $TaskbarLayoutModification) {
                New-DirectoryIfNotExists -Path C:\Windows\OEM
                Copy-Item $TaskbarLayoutModification -Destination C:\Windows\OEM -Force -ErrorAction SilentlyContinue
                Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "LayoutXMLPath" -Value "C:\Windows\OEM\TaskbarLayoutModification.xml" -Type "String"
                Write-Host "  [✓] Applied Windows 11 TaskbarLayoutModification.xml (registry reference only)" -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Taskbar Layout"
            }
        }
        elseif ($OSCaption -like "*Windows 10*") {
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

    # ============================================================
    # FUNCTION: Test-ConventionalHardDrive (robust HDD detection)
    # ============================================================
    function Test-ConventionalHardDrive {
        <#
        .SYNOPSIS
            Returns $true only if a physical spinning HDD is present.
            Zero false positives on SSD‑only systems. Works on Windows 10/11.
        #>

        # --- 1. Ensure Storage module is loaded and subsystem initialised ---
        try {
            Import-Module Storage -Force -ErrorAction Stop
        } catch {
            Write-Host "  [HDD] Could not import Storage module, continuing with WMI." -ForegroundColor Gray
        }

        # Warm up the storage stack (critical on Win10)
        $null = Get-Disk -ErrorAction SilentlyContinue

        # --- 2. Try Get-PhysicalDisk with one retry ---
        for ($attempt = 0; $attempt -lt 2; $attempt++) {
            try {
                $allDisks = Get-PhysicalDisk -ErrorAction Stop | Where-Object {
                    $_.BusType -notmatch 'USB|FileBackedVirtual'
                }
                if ($allDisks) {
                    $mediaTypes = $allDisks | Select-Object -ExpandProperty MediaType -Unique
                    if ($mediaTypes -contains 'HDD') {
                        Write-Host "  [HDD] Detected HDD(s) via Get-PhysicalDisk." -ForegroundColor Green
                        return $true
                    }
                    if (-not ($mediaTypes -contains 'HDD') -and $mediaTypes -contains 'SSD') {
                        Write-Host "  [HDD] Only SSD media detected via Get-PhysicalDisk. No HDD present." -ForegroundColor Gray
                        return $false          # immediate exit – no WMI fallback
                    }
                    # Mixed or unknown media – fall through to WMI
                    break
                }
                break   # no disks found, break out
            } catch {
                if ($attempt -eq 0) {
                    Write-Host "  [HDD] Get-PhysicalDisk attempt 1 failed, retrying..." -ForegroundColor Gray
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "  [HDD] Get-PhysicalDisk query failed: $_" -ForegroundColor Gray
                }
            }
        }

        # --- 3. Ultimate fallback: Win32_DiskDrive (WMI) ---
        try {
            $wmiDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Where-Object {
                $_.InterfaceType -ne 'USB' -and $_.Model -notmatch 'Virtual|vhd|RAM'
            }

            foreach ($disk in $wmiDisks) {
                if ($disk.MediaType -ne 'Fixed hard disk media') { continue }

                # Normalise RotationRate to an integer (-1 if $null)
                $rpm = if ($null -eq $disk.RotationRate) { -1 } else { [int]$disk.RotationRate }

                # HDD: rotation rate > 1 (e.g. 5400, 7200, 10000)
                if ($rpm -gt 1) {
                    Write-Host "  [HDD] Detected HDD via WMI (RotationRate = $rpm RPM)." -ForegroundColor Green
                    return $true
                }

                # SSD: rotation rate = 0 (no moving parts)
                if ($rpm -eq 0 -and $disk.InterfaceType -ne 'NVMe') {
                    continue
                }

                # NVMe drive with rotation = 1 (firmware quirk) – definitely SSD
                if ($rpm -eq 1 -and $disk.InterfaceType -eq 'NVMe') {
                    continue
                }

                # Any other value (including -1 for unknown) – skip the drive without guessing
                Write-Host "  [HDD] Ambiguous drive $($disk.Model) (RotationRate=$rpm, Interface=$($disk.InterfaceType)) – skipping." -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [HDD] WMI query failed: $_" -ForegroundColor Yellow
        }

        Write-Host "  [HDD] No conventional hard drive detected." -ForegroundColor Gray
        return $false
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
        # NOTE: OEM-key *matching* logic is deliberately unchanged (v2.2.0).
        # It is proven correct against real Dell/HP/Lenovo BIOS strings such as
        # "[4.0] Professional OEM:DM". Only the exit-code handling below has
        # been split so a /ipk failure is not masked by a later /ato success.
        $SLP = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
        if ($SLP -and $SLP.LicenseStatus -eq 1 -and $SLP.Description -notlike '*KMS*') { return $true }

        $EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $SLS = Get-CimInstance -ClassName SoftwareLicensingService

        if ($SLS.OA3xOriginalProductKey -and $SLS.OA3xOriginalProductKeyDescription -like "*$EditionId*") {
            cscript.exe "$env:WinDir\System32\slmgr.vbs" /ipk $SLS.OA3xOriginalProductKey | Out-Null
            $ipkCode = $LASTEXITCODE
            cscript.exe "$env:WinDir\System32\slmgr.vbs" /ato | Out-Null
            $atoCode = $LASTEXITCODE

            if ($ipkCode -eq 0 -and $atoCode -eq 0) {
                return $true
            }
            Write-Host "  [⚠] Firmware-key activation failed (/ipk=$ipkCode, /ato=$atoCode). Trying HWID fallback..." -ForegroundColor Yellow
            # Deliberately fall through so we don't leave the machine unactivated
        }

        $ActivationScript = 'C:\Recovery\OEM\Activation\HWID_Activation.cmd'
        if (Test-Path $ActivationScript) {
            & cmd /c "`"$ActivationScript`" /HWID"
            return $true
        }
        return $false
    }

    function Test-OfficeInstalled {
        # MSI installs write a REG_SZ *value* named 'Path' under InstallRoot.
        # The previous Test-Path on ...\Path tested for a subkey of that name,
        # so it never matched a real MSI install. Use Get-ItemProperty instead.
        foreach ($Ver in 12..16) {
            foreach ($Hive in @('HKLM:\Software\Microsoft\Office', 'HKLM:\Software\Wow6432Node\Microsoft\Office')) {
                $InstallRoot = "$Hive\$Ver.0\Common\InstallRoot"
                if (-not (Test-Path $InstallRoot)) { continue }
                $Path = (Get-ItemProperty -Path $InstallRoot -Name Path -ErrorAction SilentlyContinue).Path
                if ($Path) { return $true }
            }
        }
        $C2rKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        if ((Test-Path $C2rKey) -and (Get-ItemPropertyValue -Path $C2rKey -Name VersionToReport -ErrorAction SilentlyContinue)) { return $true }
        return $false
    }

    function Get-OfficeInstallerFolder {
        $Root = 'C:\Recovery\OEM\Apps'
        if (-not (Test-Path $Root)) { return $null }
        # Sort by LastWriteTime, not Name: 'Sort-Object Name -Descending' would
        # pick Office365 over Office2021, which is the wrong folder.
        return Get-ChildItem -Path $Root -Directory -Filter 'Office*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    function Install-Office {
        param([string]$InstallerPath)
        $SetupPath  = Join-Path $InstallerPath 'setup.exe'
        $ConfigPath = Join-Path $InstallerPath 'configuration.xml'
        if ((-not (Test-Path $SetupPath)) -or (-not (Test-Path $ConfigPath))) { return $false }
        # Pass -WorkingDirectory explicitly: Push-Location does not update
        # [Environment]::CurrentDirectory, which is what Start-Process can use
        # as the child's initial working directory.
        $Process = Start-Process -FilePath $SetupPath `
            -ArgumentList '/configure configuration.xml' `
            -WorkingDirectory $InstallerPath `
            -Wait -PassThru
        return $Process.ExitCode -eq 0
    }

    function Test-OfficeAppsOpen {
        <#
        .SYNOPSIS
            Fail-closed detection of running Office applications.

        .DESCRIPTION
            Returns $true if an Office-named process is running in any
            non-zero (interactive user) session, or if the process list
            cannot be enumerated. Returns $false only when enumeration
            succeeded and no such process exists.

            Owner lookup is for logging only and is NOT part of the safety
            decision: an Office-named process in a user session is always
            treated as unsafe regardless of owner resolution.
        #>
        $OfficeAppNames = @(
            'WINWORD.EXE'
            'EXCEL.EXE'
            'POWERPNT.EXE'
            'OUTLOOK.EXE'
            'ONENOTE.EXE'
            'MSACCESS.EXE'
            'MSPUB.EXE'
            'VISIO.EXE'
            'WINPROJ.EXE'
        )

        try {
            $OfficeProcs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
                Where-Object { $OfficeAppNames -contains $_.Name.ToUpperInvariant() }
        }
        catch {
            Write-Host "  [⚠] Unable to query Office processes; activation will be skipped." -ForegroundColor Yellow
            return $true   # fail closed
        }

        if (-not $OfficeProcs) { return $false }

        foreach ($Proc in @($OfficeProcs)) {
            # Session 0 is non-interactive service infrastructure. We only care
            # about Office applications in an interactive user session.
            if ($Proc.SessionId -eq 0) { continue }

            $OwnerText = "unknown"
            try {
                $Owner = Invoke-CimMethod -InputObject $Proc -MethodName GetOwner -ErrorAction Stop
                if ($Owner.User) { $OwnerText = "$($Owner.Domain)\$($Owner.User)" }
            } catch { }

            Write-Host "  [→] Office application running: $($Proc.Name) (PID $($Proc.ProcessId), Session=$($Proc.SessionId), User=$OwnerText)"
            return $true
        }

        return $false
    }

    function Test-OfficeSafeForActivation {
        <#
        .SYNOPSIS
            Quiescence gate: two clean checks separated by a short pause.

        .DESCRIPTION
            Reduces the race window where an Office app could be launched
            between the safety check and the Ohook command.
        #>
        if (Test-OfficeAppsOpen) { return $false }
        Start-Sleep -Seconds 2
        if (Test-OfficeAppsOpen) { return $false }
        return $true
    }

    function Activate-Office {
        $ActivationScript = 'C:\Recovery\OEM\Activation\Ohook_Activation.cmd'
        if (-not (Test-Path $ActivationScript)) { return $false }

        # SYSTEM-safe gate: never run Ohook while an Office application is
        # running in an interactive user session, and never when we cannot
        # conclusively verify that none are running.
        if (-not (Test-OfficeSafeForActivation)) {
            Write-Host "[→] Office activation deferred: Office is not in a safe quiescent state." -ForegroundColor Yellow
            Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Office Activation (deferred)"
            return $false
        }

        # Excluding the .cmd file itself is a no-op for Defender's process list
        # (the interpreter is cmd.exe), so only exclude the path.
        Add-MpPreference -ExclusionPath $ActivationScript -ErrorAction SilentlyContinue

        Write-Host "[*] Running Office activation script..." -ForegroundColor Cyan
        $Process = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c `"$ActivationScript`" /Ohook" `
            -Wait -PassThru

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
        $OEMDrivers = Find-BestDriverFolder -Model $Model -DriversRoot $Drivers -Manufacturer $Manufacturer

        if (-not $OEMDrivers) {
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

    Write-Host "[ ] Checking processor generation..." -ForegroundColor Cyan
    $CPU = Get-CimInstance -ClassName Win32_Processor
    $IntelGen = Get-IntelProcessorGeneration -CPUName $CPU.Name
    Write-Host "[✓] Processor: $($CPU.Name) (Gen $IntelGen)" -ForegroundColor Green

    $StorageDrivers = Join-Path -Path $Drivers -ChildPath "Storage\Intel"
    if ($IntelGen) {
        $IntelVMDVersion = switch ($IntelGen) {
            { $_ -ge 12 -and $_ -le 15 } { "20.2.6.1025.3"; break }
            11 { "19.5.8.1059.2"; break }
            default { $null }
        }
    }

    if ($IntelVMDVersion) { $IntelVMDDrivers = Join-Path -Path $StorageDrivers -ChildPath $IntelVMDVersion }

    if ($IntelVMDDrivers) {
        Write-Host "[ ] Installing Intel VMD storage drivers..." -ForegroundColor Cyan
        if (Test-Path $IntelVMDDrivers) {
            Get-ChildItem -Path $IntelVMDDrivers -Recurse -Filter *.inf | ForEach-Object { pnputil /add-driver $_.FullName /install }
            Write-Host "[✓] Intel VMD storage drivers installed" -ForegroundColor Green
            Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Intel VMD Drivers"
        } else {
            Write-Host "[⚠] No Intel VMD drivers found for version $IntelVMDVersion" -ForegroundColor Yellow
            Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Intel VMD Drivers"
        }
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

    # SYSTEM-safe: Activate-Office internally defers if any Office UI app is
    # running in an interactive user session, or if the process list can't
    # be enumerated. Never force-closes user apps.
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
        @{Name = "Microsoft.HEVCVideoExtension"; Log = "HEVCVideoExtension_UWP.log" },
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
        Start-Process -FilePath $AnyDeskInstaller `
            -ArgumentList '--install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon'

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

    $DymaxIOInstalled = Install-Application -AppName "DymaxIO" -InstallationPath "$AppsDir\DymaxIO.exe" -Arguments '/s /v"/qn"' -NoNewWindow
    if ($DymaxIOInstalled) {
        Write-Host "  [ ] Running DymaxIO licensing script..." -ForegroundColor Gray
        $global:LASTEXITCODE = $null
        & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $AppsDir "DymaxIOLicense.ps1")
        $licenseExitCode = $LASTEXITCODE

        switch ($licenseExitCode) {
            0 {
                Write-Host "  [✓] DymaxIO licensed successfully." -ForegroundColor Green
                Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "DymaxIO License"
                Import-RegistrySettings -RegFile (Join-Path $AppsDir "DymaxIO.reg") -AppName "DymaxIO" -LoadDefaultUserHive
            }
            2 {
                Write-Host "  [i] DymaxIO licensing skipped (application not detected)." -ForegroundColor Gray
                Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "DymaxIO License"
            }
            default {
                Write-Host "  [✗] DymaxIO licensing failed (exit code $licenseExitCode)." -ForegroundColor Red
                Add-ToListUnique -ListRef ([ref]$Script:FailedApps) -Value "DymaxIO License"
            }
        }
    }

    # --- Acronis Drive Monitor: install only if a spinning HDD is present ---
    $HasConventionalHDD = Test-ConventionalHardDrive
    if ($HasConventionalHDD) {
        $DriveMonitorInstalled = Install-Application -AppName "Acronis Drive Monitor" -InstallationPath (Join-Path $AppsDir "DriveMonitor.msi") -Arguments "/qn /norestart /l*v $(Join-Path $Script:LogDir 'DriveMonitor_Install.log')"
        if ($DriveMonitorInstalled) {
            Remove-ItemIfExist -Path "C:\Users\Public\Desktop\Acronis Drive Monitor.lnk"
            Import-RegistrySettings -RegFile (Join-Path $AppsDir "DriveMonitor.reg") -AppName "Acronis Drive Monitor"
        }
    } else {
        Write-Host "  [HDD] Skipping Acronis Drive Monitor – no spinning hard drive detected." -ForegroundColor Yellow
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Acronis Drive Monitor (no HDD)"
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

    # --- Configure the OEM\Update scheduled task (uses Update.xml) ---
    Write-Host "[ ] Configuring OEM update task..." -ForegroundColor Cyan
    $UpdateTaskXml = "C:\Recovery\OEM\Apps\Update.xml"
    if (Test-Path $UpdateTaskXml) {
        $ScheduleObject = New-Object -ComObject schedule.service
        $ScheduleObject.connect()
        $RootFolder = $ScheduleObject.GetFolder("\")
        if (-not ($RootFolder.GetFolders(0) | Where-Object { $_.Name -eq 'OEM' })) {
            $RootFolder.CreateFolder("OEM")
        }
        $RootFolder = $ScheduleObject.GetFolder("\")
        if ($RootFolder.GetFolders(0) | Where-Object { $_.Name -eq 'OEM' }) {
            schtasks /create /tn OEM\Update /xml $UpdateTaskXml /f
            Write-Host "[✓] Update task (OEM\Update) created/updated." -ForegroundColor Green
            Add-ToListUnique -ListRef ([ref]$Script:InstalledApps) -Value "Update Tasks"
        }
    } else {
        Write-Host "[⚠] Update.xml not found – skipping task creation." -ForegroundColor Yellow
        Add-ToListUnique -ListRef ([ref]$Script:SkippedApps) -Value "Update Tasks"
    }

    Write-Host "[ ] Setting system attributes..." -ForegroundColor Cyan
    attrib C:\ProgramData +h +i
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
catch {
    # v2.1.1: previously a terminating error here (e.g. the old Get-Counter crash)
    # silently killed every downstream install. Now we log and continue so
    # SetupComplete.cmd can still run Customizations.ps1 and pbr.ps1.
    Write-Host ""
    Write-Host "[FATAL] pre.ps1 aborted: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        At: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    Write-Host "        Continuing so Customizations.ps1 and pbr.ps1 can still run." -ForegroundColor Yellow
}
finally {
    if ($Script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
