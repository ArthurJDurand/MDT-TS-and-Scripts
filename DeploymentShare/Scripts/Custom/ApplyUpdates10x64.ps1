<#
.SYNOPSIS
    Applies Windows 10 x64 updates to Windows image during MDT task sequence deployment.

.DESCRIPTION
    Dynamically sources update packages from network share or deployment media,
    copies them to temporary directories, and integrates into Windows image using DISM.
    Handles both .cab and .msu update package formats for Windows 10 x64 systems.

.NOTES
    - Requires DISM tool availability
    - Supports network share (\\SERVER\Shared\Updates\Win10\x64) and deployment media fallback
    - Automatically cleans up temporary files after update integration
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: SYSTEM DETECTION
# =========================================================

# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# =========================================================
# PHASE 2: SOURCE PATH RESOLUTION
# =========================================================

# Define the Windows update source path
$UpdateSource = if (Test-Path "\\SERVER\Shared\Updates\Win10\x64") {
    "\\SERVER\Shared\Updates\Win10\x64"
} else {
    $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
    if ($DeploymentDriveLetter) {
        Join-Path -Path "${DeploymentDriveLetter}:" -ChildPath "Updates\Win10\x64"
    } else {
        $null
    }
}

# =========================================================
# PHASE 3: UPDATE PREPARATION
# =========================================================

# Update the Windows image if update packages are present in the update source
if ($WindowsDriveLetter -and $UpdateSource) {
    $WindowsImage = "${WindowsDriveLetter}:"
    $ScratchDir = Join-Path -Path "${WindowsDriveLetter}:" -ChildPath "Scratch"
    $Updates = Join-Path -Path "${WindowsDriveLetter}:" -ChildPath "Updates"

    if ((Test-Path "$UpdateSource\*.msu") -or (Test-Path "$UpdateSource\*.cab")) {
        # Create necessary directories
        New-Item -Path $ScratchDir -ItemType Directory -Force | Out-Null
        New-Item -Path $Updates -ItemType Directory -Force | Out-Null

        # =========================================================
        # PHASE 4: PACKAGE TRANSFER
        # =========================================================

        # Copy update packages from source to Updates directory
        do {
            robocopy $UpdateSource $Updates *.cab *.msu /ZB
        } while ($LASTEXITCODE -ne 0)

        # =========================================================
        # PHASE 5: UPDATE INTEGRATION
        # =========================================================

        # Add update packages to Windows image
        & DISM.exe /Image:$WindowsImage\ /Add-Package /PackagePath:$Updates /ScratchDir:$ScratchDir

        # =========================================================
        # PHASE 6: CLEANUP
        # =========================================================

        # Clean up directories
        Remove-Item -Path $Updates -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $ScratchDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# =========================================================
# SCRIPT COMPLETION
# =========================================================
