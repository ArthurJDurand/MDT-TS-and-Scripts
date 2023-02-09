function setHostEntries([hashtable] $entries) {
    $hostsFile = "$env:windir\System32\drivers\etc\hosts"
    $newLines = @()

    $c = Get-Content -Path $hostsFile
    foreach ($line in $c) {
        $bits = [regex]::Split($line, "\s+")
        if ($bits.count -eq 2) {
            $match = $NULL
            ForEach($entry in $entries.GetEnumerator()) {
                if($bits[1] -eq $entry.Key) {
                    $newLines += ($entry.Value + '     ' + $entry.Key)
                    Write-Host Replacing HOSTS entry for $entry.Key
                    $match = $entry.Key
                    break
                }
            }
            if($match -eq $NULL) {
                $newLines += $line
            } else {
                $entries.Remove($match)
            }
        } else {
            $newLines += $line
        }
    }

    foreach($entry in $entries.GetEnumerator()) {
        Write-Host Adding HOSTS entry for $entry.Key
        $newLines += $entry.Value + '     ' + $entry.Key
    }

    Write-Host Saving $hostsFile
    Clear-Content $hostsFile
    foreach ($line in $newLines) {
        $line | Out-File -encoding ASCII -append $hostsFile
    }
}

$entries = @{
    'esm.condusiv.com' = "0.0.0.0"
    'esm.diskeeper.com' = "0.0.0.0"
};
setHostEntries($entries)

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"
$DKLicense = 'C:\Recovery\OEM\Apps\DKLicense.7z'
$DKPatch = 'C:\Recovery\OEM\Apps\DKPatch.7z'
$Destination = 'C:\Program Files\Condusiv Technologies\Diskeeper'
& Start-Process $Winrar -ArgumentList "x -o+ $DKLicense ""$Destination""" -NoNewWindow -Wait
& Start-Process cmd.exe -ArgumentList "/c C:\Recovery\OEM\Apps\DKLicense.cmd" -Wait
& Start-Process $Winrar -ArgumentList "x -o+ $DKPatch ""$Destination""" -NoNewWindow -Wait
