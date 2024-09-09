# Function to get installed application by name
function Get-InstalledApplication {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $registryPaths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction Stop | Where-Object { $_.DisplayName -match $AppName }
        if ($App) {
            return $App
        }
    }
}

# Function to set entries in the HOSTS file
function Set-HostEntries {
    param (
        [hashtable]$Entries
    )
    
    $HostsFile = "$env:windir\System32\drivers\etc\hosts"
    $NewLines = @()
    $Hosts = Get-Content -Path $HostsFile

    foreach ($Line in $Hosts) {
        $Hits = [regex]::Split($Line, "\s+")
        if ($Hits.Count -eq 2) {
            $Key = $Hits[1]
            if ($Entries.ContainsKey($Key)) {
                $NewLines += "$($Entries[$Key])    $Key"
                Write-Host "Replacing HOSTS entry for $Key"
                $Entries.Remove($Key)
            } else {
                $NewLines += $Line
            }
        } else {
            $NewLines += $Line
        }
    }

    foreach ($Entry in $Entries.GetEnumerator()) {
        Write-Host "Adding HOSTS entry for $($Entry.Key)"
        $NewLines += "$($Entry.Value)    $($Entry.Key)"
    }

    Write-Host "Saving $HostsFile"
    $NewLines | Set-Content -Path $HostsFile -Encoding ASCII
}

# Main script to license DymaxIO if installed
$DymaxIO = Get-InstalledApplication -AppName 'DymaxIO'
if ($DymaxIO) {
    $7Zip = "C:\Program Files\7-Zip\7z.exe"
    $DymaxIOPatch = "C:\Recovery\OEM\Apps\DymaxIOPatch.7z"
    $DymaxIOReg = "C:\Recovery\OEM\Apps\DymaxIOLicense.reg"
    $Destination = "C:\Program Files\Condusiv Technologies\DymaxIO"

    if ((Test-Path $7Zip) -and (Test-Path $DymaxIOPatch) -and (Test-Path $DymaxIOReg)) {
        do {
            # Define HOSTS file entries
            $Entries = @{
                'esmaccess.condusiv.com' = "0.0.0.0"
                'ctlic.condusiv.com' = "0.0.0.0"
            }
            Set-HostEntries -Entries $Entries

            # Attempt to stop DymaxIO service
            Stop-Service -Name "DymaxIO" -NoWait
            Start-Sleep -Seconds 30

            $DymaxIOProcess = Get-Process -Name "DymaxIOService" -ErrorAction SilentlyContinue
            if ($DymaxIOProcess) {
                Stop-Process -Name "DymaxIOService" -Force
                Stop-Service -Name "DymaxIO"
            }

            # Import the DymaxIO license registry file and extract the patch
            reg import $DymaxIOReg
            & $7Zip x -o"$Destination" $DymaxIOPatch -y

            # If the last command failed, stop the service again
            if ($LASTEXITCODE -ne 0) {
                Stop-Service -Name "DymaxIO"
            }
        } while ($LASTEXITCODE -ne 0)
    }

    # Start the DymaxIO service
    Start-Service -Name "DymaxIO"
}
