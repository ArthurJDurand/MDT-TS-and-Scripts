$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter

if (-not ([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    [String]$UpdateSource = ($DeployVolumeLetter.DriveLetter).ToString() + ":\Updates\Win11\*"
}

if (Test-Path \\SERVER\Shared\Updates\Win11\*)
{
    $UpdateSource = "\\SERVER\Shared\Updates\Win11\*"
}

if (-not ([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
{
    [String]$WindowsImage = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\"
    [String]$ScratchDir = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\Scratch"
    [String]$Updates = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\Updates"
}

if (Test-Path $UpdateSource)
{
    New-Item $ScratchDir -itemType Directory
    New-Item $Updates -itemType Directory
    Copy-Item -Path $UpdateSource -Destination $Updates -Recurse
    & DISM.exe /Image:$WindowsImage /Add-Package /PackagePath:$Updates /ScratchDir:$ScratchDir
    Remove-Item $Updates -Force -Recurse
    Remove-Item $ScratchDir -Force -Recurse
}
