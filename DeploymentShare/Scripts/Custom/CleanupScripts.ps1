$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter

if (!([string]::IsNullOrWhiteSpace($WindowsVolumeLetter)))
{
    [String]$SMSTaskSequence = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\_SMSTaskSequence"
    [String]$MININT = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\MININT"
    [String]$LTIBootstrap = ($WindowsVolumeLetter.DriveLetter).ToString() + ":\LTIBootstrap.vbs"
    Remove-Item $SMSTaskSequence -Force -Recurse
    Remove-Item $MININT -Force -Recurse
    Remove-Item $LTIBootstrap -Force
}
