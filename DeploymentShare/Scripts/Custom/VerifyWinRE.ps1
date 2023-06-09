$SystemDiskNumber = Get-Volume | Where {$_.FileSystemLabel -Like "System"} | Get-Partition | Select DiskNumber
$RecoveryVolumeLetter = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | select Driveletter
if ([string]::IsNullOrWhiteSpace($RecoveryVolumeLetter.Driveletter))
{
    $RecoveryVolume = Get-Volume | Where {$_.FileSystemLabel -Like "Recovery"} | Get-Partition | Select PartitionNumber
    Set-Partition $SystemDiskNumber.DiskNumber $RecoveryVolume.PartitionNumber -NewDriveLetter R
}

$SystemDiskNumber = Get-Volume | Where-Object { $_.FileSystemLabel -Like "System" } | Get-Partition | Select-Object -ExpandProperty DiskNumber
$RecoveryVolumeLetter = Get-Volume | Where-Object { $_.FileSystemLabel -Like "Recovery" } | Select-Object -ExpandProperty DriveLetter
if ([string]::IsNullOrWhiteSpace($RecoveryVolumeLetter))
{
    $RecoveryVolume = Get-Volume | Where-Object { $_.FileSystemLabel -Like "Recovery" } | Get-Partition | Select-Object -ExpandProperty PartitionNumber

    $driveLetters = [System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name[0] }

    if ($driveLetters -contains "R") {
        $availableDriveLetter = [char]('D'.. 'J' | Where-Object { $driveLetters -notcontains $_ } | Select-Object -First 1)
    }
    else {
        $availableDriveLetter = "R"
    }

    Set-Partition -DiskNumber $SystemDiskNumber -PartitionNumber $RecoveryVolume -NewDriveLetter $availableDriveLetter
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

$RecoveryVolumeLetter = Get-Volume | Where-Object { $_.FileSystemLabel -Like "Recovery" } | Select-Object -ExpandProperty DriveLetter
if (-not ([string]::IsNullOrWhiteSpace($RecoveryVolumeLetter)))
{
    $RecoveryDriveLetter = $RecoveryVolumeLetter + ":\"
    Get-Volume -DriveLetter $RecoveryVolumeLetter | Get-Partition | Remove-PartitionAccessPath -AccessPath $RecoveryDriveLetter
}
