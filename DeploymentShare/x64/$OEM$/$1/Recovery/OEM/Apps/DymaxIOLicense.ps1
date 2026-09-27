<#
.SYNOPSIS
    Applies enterprise licensing to DymaxIO performance optimization software.

.DESCRIPTION
    Enterprise deployment script that configures DymaxIO licensing through:
    - HOSTS file modifications to block license validation
    - Registry imports for license configuration
    - Binary patching of DymaxIO installation
    - Service management and controlled retry logic

.PREREQUISITES:
    - DymaxIO installation
    - 7-Zip in default location
    - DymaxIOPatch.7z and DymaxIOLicense.reg in OEM Apps directory

.NOTES
    Uses 3-attempt retry for persistent DymaxIO services
    Creates HOSTS file backup before modification
    Exit Codes: 0=Success, 1=Failure, 2=Skipped (not installed)
    Version: 2.1.0 (Hardened)
#>

# Function to find installed applications
function Get-InstalledApplication {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )

    $RegistryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $RegistryPaths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue | 
               Where-Object { $_.DisplayName -match $AppName }
        if ($App) {
            return $App
        }
    }

    $AppxPackage = Get-AppxPackage | Where-Object { $_.Name -match $AppName }
    if ($AppxPackage) {
        return $AppxPackage
    }

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

# Enhanced function to stop DymaxIO completely
function Stop-DymaxIOCompletely {
    $ServiceName = "DymaxIO"
    $ProcessName = "DymaxIOService"
    
    Write-Host "[ ] Stopping DymaxIO service and processes..." -ForegroundColor Cyan
    
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
        Write-Host "  [!] DymaxIO processes still running, forcing termination..." -ForegroundColor Yellow
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    
    Write-Host "  [✓] DymaxIO stopped completely" -ForegroundColor Green
}

# Main script execution
try {
    Write-Host "Starting DymaxIO licensing process..." -ForegroundColor Cyan
    
    # Check if DymaxIO is installed
    Write-Host "[ ] Checking for DymaxIO installation..." -ForegroundColor Cyan
    $DymaxIO = Get-InstalledApplication -AppName 'DymaxIO'
    if (-not $DymaxIO) {
        Write-Host "[ℹ] DymaxIO not installed, skipping licensing" -ForegroundColor Gray
        exit 2
    }
    Write-Host "  [✓] DymaxIO found: $($DymaxIO.DisplayName)" -ForegroundColor Green

    # Define paths
    $7Zip = "C:\Program Files\7-Zip\7z.exe"
    $DymaxIOPatch = "C:\Recovery\OEM\Apps\DymaxIOPatch.7z"
    $DymaxIOReg = "C:\Recovery\OEM\Apps\DymaxIOLicense.reg"
    $Destination = "C:\Program Files\Condusiv Technologies\DymaxIO"

    # Validate required files
    Write-Host "[ ] Validating required files..." -ForegroundColor Cyan
    $missingFiles = @()
    if (-not (Test-Path $7Zip)) { $missingFiles += "7-Zip" }
    if (-not (Test-Path $DymaxIOPatch)) { $missingFiles += "DymaxIO Patch" }
    if (-not (Test-Path $DymaxIOReg)) { $missingFiles += "DymaxIO Registry" }
    
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
    Write-Host "[ ] Applying DymaxIO license patch..." -ForegroundColor Cyan
    $maxAttempts = 3
    $attempt = 1
    $success = $false
    
    while ($attempt -le $maxAttempts -and -not $success) {
        Write-Host "  [ ] Attempt $attempt of $maxAttempts..." -ForegroundColor Gray
        
        # Stop DymaxIO completely
        Stop-DymaxIOCompletely
        
        # Import registry (simplified, using direct call, robust quoting)
        Write-Host "    [ ] Importing registry entries..." -ForegroundColor Gray
        reg import "$DymaxIOReg" > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    [✗] Registry import failed (attempt $attempt, exit code $LASTEXITCODE)" -ForegroundColor Yellow
            $attempt++
            if ($attempt -le $maxAttempts) { 
                Write-Host "    [ ] Waiting before retry..." -ForegroundColor Gray
                Start-Sleep -Seconds 10 
            }
            continue
        }
        
        Write-Host "    [✓] Registry entries imported" -ForegroundColor Green
        
        # Extract patch
        Write-Host "    [ ] Applying binary patch..." -ForegroundColor Gray
        & "$7Zip" x "$DymaxIOPatch" -o"$Destination" -y | Out-Null
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
    
    # Step 3: Restart service and verify
    if ($success) {
        Write-Host "[ ] Starting DymaxIO service..." -ForegroundColor Cyan
        try {
            Start-Service -Name "DymaxIO" -ErrorAction Stop
            # Verify service actually started
            $serviceStatus = (Get-Service -Name "DymaxIO" -ErrorAction SilentlyContinue).Status
            if ($serviceStatus -eq 'Running') {
                Write-Host "  [✓] Service started successfully" -ForegroundColor Green
            } else {
                Write-Host "  [!] Service status is '$serviceStatus' (expected Running)" -ForegroundColor Yellow
                # Not a fatal error for licensing, but worth noting
            }
        } catch {
            Write-Host "  [✗] Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
            # Still consider licensing successful, but log the warning
        }
        
        Write-Host "[✓] DymaxIO licensed successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[✗] Failed to license DymaxIO after $maxAttempts attempts" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "[✗] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
