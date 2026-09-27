<#
.SYNOPSIS
    Automates configuration of Windows Recovery Environment (WinRE) with comprehensive partition management
    and conditional Intel VMD driver injection.

.DESCRIPTION
    Configures WinRE by detecting system partitions, managing drive letters, deploying recovery images,
    injecting required VMD storage drivers (only if they were loaded during WinPE), and updating registry settings.

.NOTES
    - Requires administrative privileges for disk and registry operations
    - Assumes standard partition labeling: 'System', 'Recovery', 'Windows'
    - Automatically cleans up temporary drive letter assignments
    - VMD injection occurs only if a marker file indicates VMD drivers were loaded in WinPE
    - Fallback WinRE image path: \\SERVER\Shared\WindowsRE\[Win10|Win11]\[x86|x64]\winre.wim
    - Target OS architecture is detected via SysWOW64 folder (robust offline)
    - Working directory is on the OS volume to avoid low space on RAM disk
    - All drive letters are dynamically discovered via volume labels; no hardcoded letters
#>

# =========================================================
# FUNCTION: Get-OSGUID
# =========================================================
function Get-OSGUID {
    param ([Parameter(Mandatory)][string]$BCDStorePath)

    $BCDInfo = bcdedit /store $BCDStorePath /enum /v
    $BCDInfoLines = $BCDInfo -split "`r?`n"
    $InsideBootLoaderSection = $false

    foreach ($Line in $BCDInfoLines) {
        $Line = $Line.Trim()
        if ($Line -like "*Windows Boot Loader*") {
            $InsideBootLoaderSection = $true
            continue
        }
        if ($InsideBootLoaderSection -and $Line -like "*identifier*") {
            if ($Line -match "^identifier\s+({[a-f0-9\-]+})$") {
                return $Matches[1]
            }
        }
    }
    return $null
}

# =========================================================
# FUNCTION: Get-TargetOSInfo
# =========================================================
function Get-TargetOSInfo {
    param([string]$WindowsDriveLetter)

    $HivePath = "${WindowsDriveLetter}:\Windows\System32\config\SOFTWARE"
    if (-not (Test-Path $HivePath)) { return $null }

    if (Test-Path 'HKLM:\TargetOS') {
        reg unload HKLM\TargetOS 2>$null
    }

    reg load HKLM\TargetOS $HivePath | Out-Null
    try {
        $BuildNumber = (Get-ItemProperty -Path 'HKLM:\TargetOS\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
    } finally {
        reg unload HKLM\TargetOS | Out-Null
    }

    if (-not $BuildNumber) { return $null }

    $IsWin11 = ([int]$BuildNumber -ge 22000)

    if (Test-Path "${WindowsDriveLetter}:\Windows\SysWOW64") {
        $ArchFolder = 'x64'
        $Is64Bit = $true
    } else {
        $ArchFolder = 'x86'
        $Is64Bit = $false
    }

    return @{
        OS      = if ($IsWin11) { "Win11" } else { "Win10" }
        Arch    = $ArchFolder
        Is64Bit = $Is64Bit
    }
}

# =========================================================
# FUNCTION: Get-VMDDriverSourcePath
# =========================================================
function Get-VMDDriverSourcePath {
    param([string]$DriverVersion)

    $UNCBase = "\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\$DriverVersion"
    if (Test-Path $UNCBase) { return $UNCBase }

    $DeployDrive = (Get-Volume | Where-Object { $_.FileSystemLabel -eq "DEPLOY" }).DriveLetter | Select-Object -First 1
    if ($DeployDrive) {
        $USBCandidate = "${DeployDrive}:\Drivers\WinPE\Storage\Intel\x64\$DriverVersion"
        if (Test-Path $USBCandidate) { return $USBCandidate }
    }
    return $null
}

# =========================================================
# FUNCTION: Copy-FileWithRetry
# =========================================================
function Copy-FileWithRetry {
    param(
        [string]$SourcePath,
        [string]$DestinationDir,
        [string]$FileName,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    do {
        $attempt++
        Write-Host "Copying $FileName (attempt $attempt of $MaxRetries)..."
        robocopy (Split-Path $SourcePath -Parent) $DestinationDir $FileName /ZB | Out-Null
        if ($LASTEXITCODE -lt 8) {
            Write-Host "Copy succeeded."
            return $true
        }
        Write-Host "Copy failed with exit code $LASTEXITCODE. Retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    } while ($attempt -lt $MaxRetries)

    Write-Host "Copy failed after $MaxRetries attempts." -ForegroundColor Red
    return $false
}

# =========================================================
# FUNCTION: Ensure-DriveLetter
#   Given a volume label, ensures that the volume has a drive letter
#   and returns the letter. If assignment fails, returns $null.
# =========================================================
function Ensure-DriveLetter {
    param(
        [string]$VolumeLabel,
        [int]$DiskNumber,
        [int]$PartitionNumber
    )

    # First try to get existing drive letter
    $vol = Get-Volume -FileSystemLabel $VolumeLabel -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vol -and $vol.DriveLetter) {
        # Verify the drive is actually accessible
        if (Test-Path "$($vol.DriveLetter):\") {
            return $vol.DriveLetter
        }
    }

    # If we have partition info, assign a new letter
    if ($PSBoundParameters.ContainsKey('PartitionNumber') -and $PSBoundParameters.ContainsKey('DiskNumber')) {
        $AvailableLetter = 67..90 | ForEach-Object { [char]$_ } | Where-Object { $_ -notin (Get-Volume).DriveLetter } | Select-Object -First 1
        if (-not $AvailableLetter) { return $null }

        # Try Set-Partition
        try {
            Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $AvailableLetter -ErrorAction Stop
            Start-Sleep -Seconds 3
            if (Test-Path "${AvailableLetter}:\") {
                return $AvailableLetter
            }
        } catch {
            Write-Host "Set-Partition failed: $_" -ForegroundColor Yellow
        }

        # Fallback to diskpart
        Write-Host "Falling back to diskpart for drive letter assignment..." -ForegroundColor Yellow
        $dpScript = @"
select disk $DiskNumber
select partition $PartitionNumber
assign letter=$AvailableLetter
"@
        $dpScript | diskpart | Out-Null
        Start-Sleep -Seconds 3
        if (Test-Path "${AvailableLetter}:\") {
            return $AvailableLetter
        }
    }

    return $null
}

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: HARDWARE DETECTION
# =========================================================

$OSDiskNumber = (Get-Disk | Where-Object { $_.BootFromDisk -eq $true }).Number | Select-Object -First 1
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter | Select-Object -First 1
$SystemPartitionNumber = (Get-Volume -FileSystemLabel System | Get-Partition).PartitionNumber | Select-Object -First 1
$RecoveryPartitionNumber = (Get-Volume -FileSystemLabel Recovery | Get-Partition).PartitionNumber | Select-Object -First 1

if (-not $WindowsDriveLetter) {
    Write-Host "ERROR: Windows volume not found." -ForegroundColor Red
    exit 1
}

# Determine target OS version and architecture early
$TargetOSInfo = Get-TargetOSInfo -WindowsDriveLetter $WindowsDriveLetter
if (-not $TargetOSInfo) {
    Write-Host "ERROR: Could not determine target OS information from registry." -ForegroundColor Red
    exit 1
}
Write-Host "Target OS: $($TargetOSInfo.OS), Architecture: $($TargetOSInfo.Arch)"

# =========================================================
# PHASE 2: DRIVE LETTER ASSIGNMENT
# =========================================================

# System partition
$SystemDriveLetter = Ensure-DriveLetter -VolumeLabel "System" -DiskNumber $OSDiskNumber -PartitionNumber $SystemPartitionNumber
if (-not $SystemDriveLetter) {
    Write-Host "ERROR: Could not assign drive letter to System partition." -ForegroundColor Red
    exit 1
}

# Recovery partition
$RecoveryDriveLetter = Ensure-DriveLetter -VolumeLabel "Recovery" -DiskNumber $OSDiskNumber -PartitionNumber $RecoveryPartitionNumber
if (-not $RecoveryDriveLetter) {
    Write-Host "ERROR: Could not assign drive letter to Recovery partition." -ForegroundColor Red
    exit 1
}

# =========================================================
# PHASE 3: SOURCE WINRE IMAGE RESOLUTION
# =========================================================

$SourceWinREImage = $null

# 3a. Check OS volume first
$CandidatePaths = @(
    "${WindowsDriveLetter}:\Windows\System32\Recovery\winre.wim",
    "${WindowsDriveLetter}:\Recovery\WindowsRE\winre.wim"
)
foreach ($Candidate in $CandidatePaths) {
    if (Test-Path $Candidate) {
        $SourceWinREImage = $Candidate
        break
    }
}

# 3b. Fallback to network/USB if not found
if (-not $SourceWinREImage) {
    Write-Host "WinRE not found on OS volume. Checking fallback locations..." -ForegroundColor Yellow

    $OSFolder = $TargetOSInfo.OS
    $ArchFolder = $TargetOSInfo.Arch

    $UNCPath = "\\SERVER\Shared\WindowsRE\$OSFolder\$ArchFolder\winre.wim"
    if (Test-Path $UNCPath) {
        $SourceWinREImage = $UNCPath
    } else {
        $DeployDrive = (Get-Volume | Where-Object { $_.FileSystemLabel -eq "DEPLOY" }).DriveLetter | Select-Object -First 1
        if ($DeployDrive) {
            $USBCandidate = "${DeployDrive}:\WindowsRE\$OSFolder\$ArchFolder\winre.wim"
            if (Test-Path $USBCandidate) {
                $SourceWinREImage = $USBCandidate
            }
        }
    }
}

if (-not $SourceWinREImage) {
    Write-Host "WinRE source image not found anywhere. Cannot proceed." -ForegroundColor Red
    exit 1
}

# =========================================================
# PHASE 4: PREPARE TEMPORARY WORKING COPY
# =========================================================

$TempWorkDir = "${WindowsDriveLetter}:\Temp\WinREWork"
if (Test-Path $TempWorkDir) {
    Remove-Item -Path $TempWorkDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $TempWorkDir -ItemType Directory -Force | Out-Null
$WorkingWinREImage = Join-Path $TempWorkDir "winre.wim"

if (-not (Copy-FileWithRetry -SourcePath $SourceWinREImage -DestinationDir $TempWorkDir -FileName "winre.wim")) {
    Write-Host "Failed to copy WinRE source image." -ForegroundColor Red
    exit 1
}

# Verify copy integrity
$SourceHash = (Get-FileHash -Path $SourceWinREImage -Algorithm SHA256).Hash
$WorkingHash = (Get-FileHash -Path $WorkingWinREImage -Algorithm SHA256).Hash
if ($SourceHash -ne $WorkingHash) {
    Write-Host "Hash mismatch after copy. Retrying once more..." -ForegroundColor Yellow
    Remove-Item $WorkingWinREImage -Force
    if (-not (Copy-FileWithRetry -SourcePath $SourceWinREImage -DestinationDir $TempWorkDir -FileName "winre.wim")) {
        Write-Host "Unable to copy image correctly." -ForegroundColor Red
        exit 1
    }
    $WorkingHash = (Get-FileHash -Path $WorkingWinREImage -Algorithm SHA256).Hash
    if ($SourceHash -ne $WorkingHash) {
        Write-Host "Hash verification failed after retry. Aborting." -ForegroundColor Red
        exit 1
    }
}

# =========================================================
# PHASE 5: VMD DRIVER INJECTION (conditional)
# =========================================================

$VMDMarkerFile = Join-Path $env:TEMP "VMD_Loaded.txt"
$InjectVMD = $false

if ((Test-Path $VMDMarkerFile) -and $TargetOSInfo.Is64Bit) {
    $DriverVersion = (Get-Content $VMDMarkerFile -Raw).Trim()
    if ($DriverVersion) {
        $InjectVMD = $true
        Write-Host "VMD marker found. Version: $DriverVersion"
    }
} else {
    Write-Host "No VMD injection needed (marker absent or target OS is 32-bit)."
}

if ($InjectVMD) {
    $DriverSource = Get-VMDDriverSourcePath -DriverVersion $DriverVersion

    if ($DriverSource) {
        if (-not (Get-ChildItem $DriverSource -Recurse -Filter *.inf -ErrorAction SilentlyContinue)) {
            Write-Host "No INF files found in VMD driver folder. Skipping injection." -ForegroundColor Yellow
        } else {
            $TempDriverDir = Join-Path $TempWorkDir "VMD_Drivers"
            New-Item -Path $TempDriverDir -ItemType Directory -Force | Out-Null
            robocopy $DriverSource $TempDriverDir /S /ZB /J | Out-Null

            $DismLog = Join-Path $TempWorkDir "dism_driver.log"
            Write-Host "Injecting VMD drivers..."
            $DismOutput = & dism.exe /Add-Driver /Image:$TempWorkDir /Driver:$TempDriverDir /Recurse /LogPath:$DismLog 2>&1
            $DismExit = $LASTEXITCODE

            $Failed = $DismOutput | Select-String -Pattern "Error|failed" -Quiet

            if ($DismExit -eq 0 -and -not $Failed) {
                Write-Host "VMD drivers injected successfully."
            } else {
                Write-Host "VMD injection may have failed. Check $DismLog" -ForegroundColor Yellow
            }

            Remove-Item -Path $TempDriverDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "VMD driver source not found for version $DriverVersion. Continuing without injection." -ForegroundColor Yellow
    }
}

# =========================================================
# PHASE 6: DEPLOY TO RECOVERY PARTITION
# =========================================================

if ($RecoveryDriveLetter) {
    $DestinationWinREImage = "${RecoveryDriveLetter}:\Recovery\WindowsRE\winre.wim"
    $WindowsREDir = "${RecoveryDriveLetter}:\Recovery\WindowsRE"
    New-Item -Path $WindowsREDir -ItemType Directory -Force | Out-Null

    if (-not (Copy-FileWithRetry -SourcePath $WorkingWinREImage -DestinationDir $WindowsREDir -FileName "winre.wim")) {
        Write-Host "Failed to copy WinRE image to recovery partition." -ForegroundColor Red
        exit 1
    }

    $FinalHash = (Get-FileHash -Path $DestinationWinREImage -Algorithm SHA256).Hash
    $WorkingHash2 = (Get-FileHash -Path $WorkingWinREImage -Algorithm SHA256).Hash
    if ($FinalHash -ne $WorkingHash2) {
        Write-Host "Deployed image hash mismatch. Aborting." -ForegroundColor Red
        exit 1
    }

    # =========================================================
    # PHASE 7: WINRE CONFIGURATION
    # =========================================================

    Write-Host "Configuring WinRE..."
    & "${WindowsDriveLetter}:\Windows\System32\reagentc.exe" /setreimage /path "${RecoveryDriveLetter}:\Recovery\WindowsRE" /target "${WindowsDriveLetter}:\Windows"

    $SystemDriveLetter = (Get-Volume -FileSystemLabel System).DriveLetter | Select-Object -First 1
    if ($SystemDriveLetter) {
        $BCDStore = (Get-ChildItem -Path "${SystemDriveLetter}:" -Recurse -Filter "BCD" -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } | Select-Object -First 1).FullName

        if (Test-Path $BCDStore) {
            $OSGUID = Get-OSGUID -BCDStorePath $BCDStore
            if ($OSGUID) {
                Remove-Item -Path "${WindowsDriveLetter}:\Recovery\WindowsRE" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "${WindowsDriveLetter}:\Recovery\ReAgentOld.xml" -Force -ErrorAction SilentlyContinue
                & "${WindowsDriveLetter}:\Windows\System32\reagentc.exe" /enable /osguid $OSGUID
            }
        }
    }

    # =========================================================
    # PHASE 8: REGISTRY UPDATE (using dism)
    # =========================================================

    try {
        $DismInfo = & dism.exe /Get-ImageInfo /ImageFile:$DestinationWinREImage /Index:1
        $VersionLine = $DismInfo | Select-String -Pattern "Version\s*:\s*([\d\.]+)"
        if ($VersionLine -and $VersionLine.Matches.Count -gt 0) {
            $NewVersion = $VersionLine.Matches[0].Groups[1].Value

            reg load HKLM\temp "${WindowsDriveLetter}:\Windows\System32\config\SOFTWARE" | Out-Null
            try {
                $WinREVersionKey = 'HKLM:\temp\Microsoft\Windows NT\CurrentVersion'
                if (Test-Path $WinREVersionKey) {
                    $CurrentVersion = (Get-ItemProperty -Path $WinREVersionKey -Name 'WinREVersion' -ErrorAction SilentlyContinue).WinREVersion
                    if ($CurrentVersion -ne $NewVersion) {
                        Set-ItemProperty -Path $WinREVersionKey -Name 'WinREVersion' -Value $NewVersion -Type String
                    }
                }
            } finally {
                reg unload HKLM\temp | Out-Null
            }
        }
    } catch {
        Write-Host "Registry update skipped (non-fatal)."
    }

    # =========================================================
    # PHASE 9: CLEANUP
    # =========================================================

    if ((Get-Volume -FileSystemLabel Recovery).DriveLetter) {
        Remove-PartitionAccessPath -DiskNumber $OSDiskNumber -PartitionNumber $RecoveryPartitionNumber -AccessPath "${RecoveryDriveLetter}:" -ErrorAction SilentlyContinue
    }
}

# Clean up working directory
Remove-Item -Path $TempWorkDir -Recurse -Force -ErrorAction SilentlyContinue

# =========================================================
# SCRIPT COMPLETION
# =========================================================
