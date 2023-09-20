$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter

if (!([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    [String]$UpdateSource = ($DeployVolumeLetter.DriveLetter).ToString() + ":\Updates\Win10\x86\*"
}

if (Test-Path \\SERVER\Shared\Updates\Win10\x86\*)
{
    $UpdateSource = "\\SERVER\Shared\Updates\Win10\x86\*"
}

if (!([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
{
    [String]$WindowsImage = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\"
    [String]$ScratchDir = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\Scratch"
    [String]$Updates = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\Updates"
}

if ((Test-Path $UpdateSource) -and (!([string]::IsNullOrWhiteSpace($WindowsVolumeLetter))))
{
    New-Item $ScratchDir -itemType Directory
    New-Item $Updates -itemType Directory
    Copy-Item -Path $UpdateSource -Destination $Updates -Recurse
    & DISM.exe /Image:$WindowsImage /Add-Package /PackagePath:$Updates /ScratchDir:$ScratchDir
    Remove-Item $Updates -Force -Recurse
    Remove-Item $ScratchDir -Force -Recurse
}
