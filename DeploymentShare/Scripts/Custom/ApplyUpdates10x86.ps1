# ApplyUpdates10x86.ps1
# ----------------------
# Purpose:
# This script applies 32-bit (x86) Windows updates to a Windows image during a task sequence 
# in MDT (Microsoft Deployment Toolkit). It ensures that systems are kept up-to-date 
# with the latest patches and packages during deployment.

# Features:
# - Dynamically identifies the Windows partition using its file system label.
# - Locates update source paths:
#   - Primary source: Network path (`\\SERVER\Shared\Updates\Win10\x86`).
#   - Fallback source: Deployment media drive labeled "Deploy".
# - Validates the presence of `.cab` or `.msu` update packages in the specified source directory.
# - Efficiently copies updates to a temporary directory on the Windows drive.
# - Integrates updates into the Windows image using the DISM tool.
# - Ensures clean removal of temporary directories and files after updates are applied.

# Key Components:
# - Utilizes PowerShell cmdlets to dynamically resolve required paths.
# - Employs `robocopy` for resilient and reliable file transfers.
# - Leverages the DISM tool to add update packages to the Windows image.
# - Implements a structured cleanup mechanism to maintain the deployment environment's stability.

# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# Define the Windows update source path
$UpdateSource = if (Test-Path "\\SERVER\Shared\Updates\Win10\x86") {
    "\\SERVER\Shared\Updates\Win10\x86"
} else {
    $DeploymentDriveLetter = (Get-Volume | Where-Object { $_.FileSystemLabel -Like "Deploy" }).DriveLetter
    if ($DeploymentDriveLetter) {
        Join-Path -Path "${DeploymentDriveLetter}:" -ChildPath "Updates\Win10\x86"
    } else {
        $null
    }
}

# Update the Windows image if update packages are present in the update source
if ($WindowsDriveLetter -and $UpdateSource) {
    $WindowsImage = "${WindowsDriveLetter}:"
    $ScratchDir = Join-Path -Path "${WindowsDriveLetter}:" -ChildPath "Scratch"
    $Updates = Join-Path -Path "${WindowsDriveLetter}:" -ChildPath "Updates"

    if ((Test-Path "$UpdateSource\*.msu") -or (Test-Path "$UpdateSource\*.cab")) {
        # Create necessary directories
        New-Item -Path $ScratchDir -ItemType Directory -Force | Out-Null
        New-Item -Path $Updates -ItemType Directory -Force | Out-Null

        # Copy update packages from source to Updates directory
        do {
            robocopy $UpdateSource $Updates *.cab *.msu /ZB
        } while ($LASTEXITCODE -ne 0)

        # Add update packages to Windows image
        & DISM.exe /Image:$WindowsImage\ /Add-Package /PackagePath:$Updates /ScratchDir:$ScratchDir

        # Clean up directories
        Remove-Item -Path $Updates -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $ScratchDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}
