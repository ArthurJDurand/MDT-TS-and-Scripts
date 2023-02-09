$DeployVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Deploy"} | select Driveletter
if (-not ([string]::IsNullOrWhiteSpace($DeployVolumeLetter)))
{
    $SourcePath = ($DeployVolumeLetter.DriveLetter).ToString() + ":\Servicing"
}

if (Test-Path \\SERVER\Shared\Servicing)
{
    $SourcePath = "\\SERVER\Shared\Servicing"
}

if ((Test-Path $SourcePath) -and (!(Test-Path C:\Temp\Servicing)))
{
    New-Item C:\Temp\Servicing -itemType Directory
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 11*") -and (Test-Path $SourcePath))
{
    Copy-Item -Path $SourcePath\Win11\* -Destination C:\Temp\Servicing -Force -Recurse
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($OSCaption -like "*Windows 10*") -and (Test-Path $SourcePath))
{
    Copy-Item -Path $SourcePath\Win10\x64\* -Destination C:\Temp\Servicing -Force -Recurse
}

if (Test-Path C:\Temp\Servicing\*)
{
    Repair-WindowsImage -Online -RestoreHealth -Source C:\Temp\Servicing\Windows -LimitAccess
} else {
    Repair-WindowsImage -Online -RestoreHealth
}

if (Test-Path C:\Temp\Servicing)
{
    Remove-Item C:\Temp\Servicing -Force -Recurse
}

if( (Get-ChildItem C:\Temp | Measure-Object).Count -eq 0)
{
    Remove-Item C:\Temp -Force -Recurse
}

Remove-Item $PSCommandPath -Force
