<#
.SYNOPSIS
    RustDesk OOBE configuration – fixed argument counts.
.DESCRIPTION
    - Writes direct-server and auto-update into RustDesk2.toml (offline).
    - Starts service, waits for IPC.
    - Sets permanent password via --password (IPC, no --silent).
    - Sets D3D rendering + hwcodec via --option (IPC, no --silent).
.NOTES
    For OOBE (SYSTEM). Uses Windows PowerShell 5.1 syntax.
#>

$ErrorActionPreference = 'Stop'

# ================= USER CONFIGURATION =================
$ServiceName          = 'rustdesk'
$PrimaryConfigPath    = 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml'
$FallbackConfigPath   = 'C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config\RustDesk2.toml'
$RustDeskExe          = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
$PermanentPassword    = 'P@$$w0rd'
$RenderType           = 'd3d'        # 'd3d' or 'd3d11'
$ServiceReadyTimeout  = 120          # seconds to wait for IPC
$MaxRetries           = 5
$RetryDelaySeconds    = 5
# =====================================================

Write-Host "`n[ ] Configuring RustDesk for OOBE..." -ForegroundColor Cyan

# ---------- 1. Verify RustDesk ----------
if (-not (Test-Path $RustDeskExe)) {
    Write-Host "  [✗] RustDesk not found at $RustDeskExe" -ForegroundColor Red
    exit 2
}

# ---------- 2. Wait for service ----------
Write-Host "  [ ] Waiting for RustDesk service..." -ForegroundColor Yellow
$serviceExists = $false
for ($i = 0; $i -lt 15; $i++) {
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        $serviceExists = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $serviceExists) {
    Write-Host "  [⚠] Service not registered – password/options will fail." -ForegroundColor Yellow
}

# ---------- 3. Kill UI, stop service ----------
Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    try {
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
        }
        Write-Host "  [✓] Service stopped." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Could not stop service – editing anyway." -ForegroundColor Yellow
    }
}

# ---------- 4. Determine config file ----------
$usedConfigPath = $null
if (Test-Path $PrimaryConfigPath) {
    $usedConfigPath = $PrimaryConfigPath
} elseif (Test-Path $FallbackConfigPath) {
    Write-Host "  [i] Using fallback config: $FallbackConfigPath" -ForegroundColor DarkGray
    $usedConfigPath = $FallbackConfigPath
} else {
    $configDir = Split-Path $PrimaryConfigPath -Parent
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    New-Item -ItemType File -Path $PrimaryConfigPath -Force | Out-Null
    $usedConfigPath = $PrimaryConfigPath
    Write-Host "  [✓] Created new config file." -ForegroundColor Green
}

# ---------- 5. Offline TOML: only confirmed keys ----------
Write-Host "  [ ] Writing confirmed TOML keys..." -ForegroundColor Yellow
$configOk = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $raw = Get-Content $usedConfigPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $lines = @('[options]')
        } else {
            $lines = $raw -split "`r?`n"
        }

        # Ensure [options] section
        $optIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[options\]') { $optIdx = $i; break }
        }
        if ($optIdx -eq -1) {
            $lines += '[options]'
            $optIdx = $lines.Count - 1
        }

        $sectEnd = $lines.Count
        for ($i = $optIdx + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[.*\]') { $sectEnd = $i; break }
        }

        $desired = @{
            'direct-server'      = "'Y'"
            'allow-auto-update'  = "'Y'"
            'auto-update'        = "'Y'"
        }

        $updated = @()
        $found = @{}
        foreach ($line in $lines[($optIdx+1)..($sectEnd-1)]) {
            if ($line -match '^\s*([^=]+?)\s*=\s*(.+)$') {
                $key = $Matches[1].Trim()
                if ($desired.ContainsKey($key)) {
                    $updated += "$key = $($desired[$key])"
                    $found[$key] = $true
                    continue
                }
            }
            $updated += $line
        }
        foreach ($k in $desired.Keys) {
            if (-not $found[$k]) { $updated += "$k = $($desired[$k])" }
        }

        $newLines = $lines[0..$optIdx] + $updated
        if ($sectEnd -lt $lines.Count) { $newLines += $lines[$sectEnd..($lines.Count-1)] }

        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($usedConfigPath, $newLines, $utf8)
        Write-Host "  [✓] TOML updated: direct-server, allow-auto-update." -ForegroundColor Green
        $configOk = $true
        break
    } catch {
        if ($attempt -ge 3) {
            Write-Host "  [✗] TOML update failed: $($_.Exception.Message)" -ForegroundColor Red
        } else {
            Start-Sleep -Seconds 2
        }
    }
}

# ---------- 6. Start service ----------
if ($service) {
    try {
        Write-Host "  [ ] Starting service..." -ForegroundColor Yellow
        Start-Service -Name $ServiceName -ErrorAction Stop
        (Get-Service $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        Write-Host "  [✓] Service is Running." -ForegroundColor Green
    } catch {
        Write-Host "  [✗] Service start failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------- 7. Wait for IPC readiness ----------
if ($service) {
    Write-Host "  [ ] Waiting for IPC readiness..." -ForegroundColor Yellow
    $ready = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $ServiceReadyTimeout) {
        $testProc = Start-Process -FilePath $RustDeskExe -ArgumentList @('--get-id', '--silent') -WindowStyle Hidden -PassThru -Wait -ErrorAction SilentlyContinue
        if ($testProc -and $testProc.ExitCode -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if (-not $ready) {
        Write-Host "  [✗] IPC not ready after $ServiceReadyTimeout s." -ForegroundColor Red
        exit 3
    }
    Write-Host "  [✓] IPC responsive." -ForegroundColor Green
}

# ---------- 8. Helper for IPC commands ----------
function Invoke-RustDeskIPC {
    param([string[]]$Arguments, [string]$Description)
    Write-Host "    [ ] $Description..." -ForegroundColor DarkGray
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $proc = Start-Process -FilePath $RustDeskExe -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
            if ($proc.ExitCode -eq 0) {
                Write-Host "    [✓] $Description succeeded (attempt $attempt)." -ForegroundColor Green
                return $true
            } else {
                Write-Host "    [!] $Description failed (exit $($proc.ExitCode), attempt $attempt)." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "    [!] $Description exception: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds $RetryDelaySeconds
    }
    Write-Host "    [✗] $Description failed after $MaxRetries attempts." -ForegroundColor Red
    return $false
}

# ---------- 9. Set permanent password (NO --silent) ----------
$passwordResult = Invoke-RustDeskIPC -Arguments @('--password', $PermanentPassword) -Description "Setting permanent password"

# ---------- 10. Set D3D rendering + hwcodec (NO --silent) ----------
$renderResult = Invoke-RustDeskIPC -Arguments @('--option', 'rendertype', $RenderType) -Description "Setting rendertype=$RenderType"
$hwcodecResult = Invoke-RustDeskIPC -Arguments @('--option', 'hwcodec', 'Y') -Description "Enabling hardware codec"

# ---------- 11. Cleanup ----------
Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ---------- 12. Summary ----------
Write-Host "`n✅ RustDesk configuration completed!" -ForegroundColor Green
Write-Host "  Password set      : $passwordResult"
Write-Host "  Render set        : $renderResult"
Write-Host "  HW codec set      : $hwcodecResult"
Write-Host "  TOML updated      : $configOk"

if ($passwordResult -and $renderResult -and $hwcodecResult -and $configOk) {
    exit 0
} else {
    exit 1
}
