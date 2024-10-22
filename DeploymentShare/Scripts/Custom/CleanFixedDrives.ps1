# Clean all non USB drives
Get-Disk | Where-Object { $_.Bustype -Ne "USB" } | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
