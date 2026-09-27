<#
.SYNOPSIS
    Dynamically detects, locates, and loads required WinPE storage drivers.

.DESCRIPTION
    Loads Intel VMD storage drivers during WinPE execution when internal
    storage is not detected. If VMD drivers are loaded, a marker file is written
    so that subsequent scripts can know VMD is required and which version was used.

.NOTES
    - 100% WinPE-safe: uses registry + diskpart only; no WMI, CIM, or WS-Man
    - No console chatter (no Write-Host, no verbose output)
    - No forced silence (exit codes are preserved)
    - No exit commands (task sequence friendly)
#>

# ============================================================
# FUNCTION: Get-IntelProcessorGeneration
#   Pure string parser. Returns Intel generation (11-16) or $null.
#   Fully supports Xeon, Core Ultra, Core (non-i), and classic Core i.
# ============================================================
function Get-IntelProcessorGeneration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CPUName
    )

    $SeriesMap = @{
        '1' = 14   # Series 1 (Meteor Lake / Raptor Lake Refresh U)
        '2' = 15   # Series 2 (Lunar Lake / Arrow Lake)
        '3' = 16   # Future Series 3
    }

    $Name = ($CPUName -replace '\s+', ' ').Trim()
    $Name = $Name -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
    $Name = ($Name -replace '\s+', ' ').Trim()

    if ($Name -match '(?i)\bAMD\b') { return $null }
    if ($Name -notmatch '(?i)\bIntel\b') { return $null }

    if ($Name -match '(?i)\b(?<gen>1[1-9])(?:st|nd|rd|th)?\s+Gen\b') {
        $gen = [int]$Matches['gen']
        if ($gen -ge 11) { return $gen }
    }

    if ($Name -match '(?i)\bXeon\b.*?(\d{4,5})') {
        $model = $Matches[1]
        $gen = [int]$model.Substring(0,2)
        if ($gen -ge 11) { return $gen }
        return $null
    }

    if ($Name -match '(?i)\bCore\s+Ultra\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]
    }

    if ($Name -match '(?i)\bCore\s+[3579]\s+(?<sku>\d{3,4})[A-Z]*\b') {
        $seriesDigit = $Matches['sku'].Substring(0,1)
        return $SeriesMap[$seriesDigit]
    }

    if ($Name -match '(?i)\b(?:Pentium|Celeron|Atom|[NJ]\d{2,4})\b') {
        return $null
    }

    if ($Name -match '(?i)\bi[3579][- ](?<model>\d{4,5})[A-Z0-9]*\b') {
        $model = $Matches['model']
        $len   = $model.Length

        if ($len -eq 5) {
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
        elseif ($len -eq 4) {
            $gen = [int]$model.Substring(0,2)
            if ($gen -ge 11) { return $gen }
        }
    }

    return $null
}

# =========================================================
# FUNCTION: Get-WinPEDriverPath
#   Locates the driver share (UNC first, then all fixed drives)
# =========================================================
function Get-WinPEDriverPath {
    $UNCPath = "\\SERVER\Shared\Drivers\WinPE"
    if (Test-Path $UNCPath) {
        return $UNCPath
    }

    foreach ($Drive in Get-PSDrive -PSProvider FileSystem) {
        $Candidate = Join-Path $Drive.Root "Drivers\WinPE"
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    return $null
}

# =========================================================
# FUNCTION: Test-InternalStoragePresence
#   Returns $true if at least one disk is visible.
#   Uses native diskpart to avoid any WMI/Storage dependency.
# =========================================================
function Test-InternalStoragePresence {
    try {
        $output = "list disk" | diskpart 2>&1
        $diskCount = ($output | Where-Object { $_ -match '^\s*Disk\s+\d+\s+' }).Count
        return ($diskCount -gt 0)
    } catch {
        return $false
    }
}

# =========================================================
# MAIN EXECUTION
# =========================================================

# PHASE 1: Storage check
if (-not (Test-InternalStoragePresence)) {

    # PHASE 2: Driver source resolution
    $WinPEDrivers = Get-WinPEDriverPath

    if ($WinPEDrivers) {
        $StorageRoot = Join-Path $WinPEDrivers "Storage\Intel\x64"

        # PHASE 3: Processor detection (registry)
        $RegKey  = 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
        $CPUName = (Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue).ProcessorNameString
        $IntelGen = $null

        if ($CPUName) {
            $IntelGen = Get-IntelProcessorGeneration -CPUName $CPUName
        }

        # PHASE 4: Driver version selection
        $IntelVMDVersion = switch ($IntelGen) {
            { $_ -ge 12 } { "20.2.6.1025.3" }
            11            { "19.5.8.1059.2" }
            default       { $null }
        }

        if ($IntelVMDVersion) {
            $SourceDrivers = Join-Path $StorageRoot $IntelVMDVersion
            $TempDrivers   = Join-Path $env:TEMP "Drivers"

            if (Test-Path $SourceDrivers) {
                New-Item -Path $TempDrivers -ItemType Directory -Force | Out-Null

                robocopy $SourceDrivers $TempDrivers /S /ZB /J

                if ($LASTEXITCODE -lt 8 -and (Get-ChildItem $TempDrivers -Recurse -Filter *.inf -ErrorAction SilentlyContinue)) {

                    # PHASE 5: Driver loading
                    $LoadSuccess = $true
                    Get-ChildItem $TempDrivers -Recurse -Filter *.inf |
                        ForEach-Object {
                            drvload $_.FullName
                            if ($LASTEXITCODE -ne 0) { $LoadSuccess = $false }
                        }

                    if ($LoadSuccess) {
                        # Write marker file with version
                        $MarkerFile = Join-Path $env:TEMP "VMD_Loaded.txt"
                        Set-Content -Path $MarkerFile -Value $IntelVMDVersion -Force
                    }
                }

                Remove-Item $TempDrivers -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# SCRIPT COMPLETION
