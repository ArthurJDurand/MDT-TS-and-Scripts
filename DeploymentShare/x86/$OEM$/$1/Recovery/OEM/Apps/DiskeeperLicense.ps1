<#
.SYNOPSIS
    Applies enterprise licensing to Diskeeper performance optimization software.

.DESCRIPTION
    Enterprise deployment script that configures Diskeeper licensing through:
    - HOSTS file modifications to block license validation
    - Registry imports for license configuration
    - Binary patching of Diskeeper installation
    - Service management and controlled retry logic

.PREREQUISITES:
    - Diskeeper installation
    - 7-Zip in default location
    - DiskeeperPatch.7z in OEM Apps directory

.NOTES
    Uses 3-attempt retry for persistent Diskeeper services
    Creates HOSTS file backup before modification
    Exit Codes: 0=Success, 1=Failure, 2=Skipped (not installed)
    Version: 2.1.0 (Hardened)
#>

# Function to find installed applications (32‑bit aware)
function Get-InstalledApplication {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )

    $App = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -match $AppName }
    if ($App) { return $App }
    return $null
}

# Function to safely modify HOSTS file with backup
function Set-HostEntriesSafe {
    param ([hashtable]$Entries)
    
    $HostsFile = "$env:windir\System32\drivers\etc\hosts"
    $BackupFile = "$HostsFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    try {
        # Create backup
        Copy-Item $HostsFile $BackupFile -Force -ErrorAction Stop
        
        # Read current content
        $CurrentContent = Get-Content $HostsFile -ErrorAction Stop
        
        # Remove existing entries for our domains
        $FilteredContent = $CurrentContent | Where-Object {
            $line = $_.Trim()
            -not ($Entries.Keys | Where-Object { $line -match $_ })
        }
        
        # Add new entries
        $NewEntries = $Entries.GetEnumerator() | ForEach-Object {
            "$($_.Value)`t$($_.Key)"
        }
        
        # Write back with proper encoding
        @($FilteredContent) + $NewEntries | Set-Content $HostsFile -Encoding ASCII -ErrorAction Stop
        
        Write-Host "  [✓] HOSTS file updated safely" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  [✗] Failed to update HOSTS file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Enhanced function to stop Diskeeper completely
function Stop-DiskeeperCompletely {
    $ServiceName = "Diskeeper"
    $ProcessName = "DkService"
    
    Write-Host "[ ] Stopping Diskeeper service and processes..." -ForegroundColor Cyan
    
    # Stop service
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "  [ ] Stopping $ServiceName service..." -ForegroundColor Gray
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        # Wait for service to stop
        Start-Sleep -Seconds 5
    }
    
    # Force kill any remaining processes
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "  [ ] Stopping $ProcessName processes..." -ForegroundColor Gray
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    
    # Double-check and wait
    Start-Sleep -Seconds 2
    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        Write-Host "  [!] Diskeeper processes still running, forcing termination..." -ForegroundColor Yellow
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    
    Write-Host "  [✓] Diskeeper stopped completely" -ForegroundColor Green
}

# Main script execution
try {
    Write-Host "Starting Diskeeper licensing process..." -ForegroundColor Cyan
    
    # Check if Diskeeper is installed
    Write-Host "[ ] Checking for Diskeeper installation..." -ForegroundColor Cyan
    $Diskeeper = Get-InstalledApplication -AppName 'Diskeeper'
    if (-not $Diskeeper) {
        Write-Host "[ℹ] Diskeeper not installed, skipping licensing" -ForegroundColor Gray
        exit 2
    }
    Write-Host "  [✓] Diskeeper found: $($Diskeeper.DisplayName)" -ForegroundColor Green

    # Define paths
    $7Zip = "C:\Program Files\7-Zip\7z.exe"
    $DiskeeperPatch = "C:\Recovery\OEM\Apps\DiskeeperPatch.7z"
    $Destination = "C:\Program Files\Condusiv Technologies\Diskeeper"

    # Validate required files
    Write-Host "[ ] Validating required files..." -ForegroundColor Cyan
    $missingFiles = @()
    if (-not (Test-Path $7Zip)) { $missingFiles += "7-Zip" }
    if (-not (Test-Path $DiskeeperPatch)) { $missingFiles += "Diskeeper Patch" }
    
    if ($missingFiles) {
        Write-Host "[✗] Missing required files: $($missingFiles -join ', ')" -ForegroundColor Red
        Write-Host "    Please ensure all prerequisites are met." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  [✓] All required files present" -ForegroundColor Green

    # Step 1: Update HOSTS file
    Write-Host "[ ] Updating HOSTS file to block license validation..." -ForegroundColor Cyan
    $Entries = @{
        'esmaccess.condusiv.com' = "0.0.0.0"
        'ctlic.condusiv.com'     = "0.0.0.0"
    }
    
    if (-not (Set-HostEntriesSafe -Entries $Entries)) {
        exit 1
    }

    # Step 2: Controlled retry logic (max 3 attempts)
    Write-Host "[ ] Applying Diskeeper license patch..." -ForegroundColor Cyan
    $maxAttempts = 3
    $attempt = 1
    $success = $false
    
    while ($attempt -le $maxAttempts -and -not $success) {
        Write-Host "  [ ] Attempt $attempt of $maxAttempts..." -ForegroundColor Gray
        
        # Stop Diskeeper completely
        Stop-DiskeeperCompletely
        
        # Extract patch
        Write-Host "    [ ] Applying binary patch..." -ForegroundColor Gray
        & "$7Zip" x "$DiskeeperPatch" -o"$Destination" -y | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Host "    [✓] Patch applied successfully" -ForegroundColor Green
        } else {
            Write-Host "    [✗] Patch extraction failed (attempt $attempt, exit code $LASTEXITCODE)" -ForegroundColor Yellow
            $attempt++
            if ($attempt -le $maxAttempts) { 
                Write-Host "    [ ] Waiting before retry..." -ForegroundColor Gray
                Start-Sleep -Seconds 10 
            }
        }
    }
    
    # Step 3: Additional registry modifications & restart service
    if ($success) {
        Write-Host "[ ] Configuring registry settings..." -ForegroundColor Cyan
        $RegistryPath = "HKLM:\SOFTWARE\Diskeeper Corporation\Diskeeper"
        
        # Ensure the registry key exists
        if (-not (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force -ErrorAction SilentlyContinue | Out-Null }
        
        # Apply settings
        Set-ItemProperty -Path $RegistryPath -Name "IsTrialware" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "OfflineActRetCode" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "OriginatorID" -Value "1" -Type String -Force
        Set-ItemProperty -Path $RegistryPath -Name "RID" -Value "1" -Type String -Force
        
        $UserSettings = "$RegistryPath\UserSettings"
        if (-not (Test-Path $UserSettings)) { New-Item -Path $UserSettings -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $UserSettings -Name "AutoCheckForUpdates" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $UserSettings -Name "ActivateOnFirstStartup" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $UserSettings -Name "CheckForUpdate" -Value 0 -Type DWord -Force
        
        $Promotion = "$RegistryPath\Promotion"
        if (-not (Test-Path $Promotion)) { New-Item -Path $Promotion -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $Promotion -Name "PublicType" -Value 2 -Type DWord -Force
        
        Write-Host "  [✓] Registry settings applied" -ForegroundColor Green

        # Restart service
        Write-Host "[ ] Starting Diskeeper service..." -ForegroundColor Cyan
        try {
            Start-Service -Name "Diskeeper" -ErrorAction Stop
            # Verify service actually started
            $serviceStatus = (Get-Service -Name "Diskeeper" -ErrorAction SilentlyContinue).Status
            if ($serviceStatus -eq 'Running') {
                Write-Host "  [✓] Service started successfully" -ForegroundColor Green
            } else {
                Write-Host "  [!] Service status is '$serviceStatus' (expected Running)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [✗] Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "[✓] Diskeeper licensed successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[✗] Failed to license Diskeeper after $maxAttempts attempts" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "[✗] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
