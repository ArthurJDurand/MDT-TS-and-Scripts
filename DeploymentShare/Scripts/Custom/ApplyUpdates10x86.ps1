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
        New-Item -Path $ScratchDir -ItemType Directory -Force
        New-Item -Path $Updates -ItemType Directory -Force

        # Copy update packages from source to Updates directory
        Copy-Item -Path "$UpdateSource\*" -Destination $Updates -Recurse

        # Add update packages to Windows image
        & DISM.exe /Image:$WindowsImage /Add-Package /PackagePath:$Updates /ScratchDir:$ScratchDir

        # Clean up directories
        Remove-Item -Path $Updates -Force -Recurse
        Remove-Item -Path $ScratchDir -Force -Recurse
    }
}
