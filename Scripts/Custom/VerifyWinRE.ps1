$SystemDiskNumber = Get-Volume | Where {$_.FileSystemLabel -Like "System"} | Get-Partition | Select DiskNumber
$RecoveryVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | select Driveletter
if ([string]::IsNullOrWhiteSpace($RecoveryVolumeLetter.Driveletter))
{
    $RecoveryVolume = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | Get-Partition | Select PartitionNumber
    Set-Partition $SystemDiskNumber.DiskNumber $RecoveryVolume.PartitionNumber  -NewDriveLetter R
}

$WindowsVolumeLetter = Get-Volume -FileSystemLabel Windows | Select DriveLetter
$RecoveryVolumeLetter = Get-Volume -FileSystemLabel Recovery | Select DriveLetter
[String]$SrcWinRE = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Windows\System32\Recovery\Winre.wim"
[String]$AltSrcWinRE = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Recovery\WindowsRE\Winre.wim"
[String]$DstWinRE = ($RecoveryVolumeLetter.Driveletter).ToString() + ":\Recovery\WindowsRE"
[String]$Windows = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Windows"
[String]$reagentc = ($WindowsVolumeLetter.Driveletter).ToString() + ":\Windows\System32\reagentc.exe"

if (!(Test-Path $DstWinRE))
{
    New-Item $DstWinRE -itemType Directory
}

if (!(Test-Path $DstWinRE\Winre.wim) -and (Test-Path $SrcWinRE))
{
    Copy-Item $SrcWinRE -Destination $DstWinRE\
}

if (!(Test-Path $DstWinRE\Winre.wim) -and (Test-Path $AltSrcWinRE))
{
    Copy-Item $AltSrcWinRE -Destination $DstWinRE\
}

if (Test-Path $DstWinRE\Winre.wim)
{
    & $reagentc /setreimage /path $DstWinRE /target $Windows
}

Get-Volume -Drive R | Get-Partition | Remove-PartitionAccessPath -accesspath R:\
