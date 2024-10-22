# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# Cleanup MDT deployment scripts if Windows drive is present
if ($WindowsDriveLetter) {
    $PathsToRemove = @(
        "$($WindowsDriveLetter):\_SMSTaskSequence",
        "$($WindowsDriveLetter):\MININT",
        "$($WindowsDriveLetter):\LTIBootstrap.vbs"
    )
    foreach ($Path in $PathsToRemove) {
        if (Test-Path $Path) {
            Remove-Item $Path -Force -Recurse
        }
    }
}
