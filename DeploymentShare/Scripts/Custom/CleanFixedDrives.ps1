$Disk = Get-Disk | Where-Object -FilterScript {$_.Bustype -Ne "USB"}

if (-not ([string]::IsNullOrWhiteSpace($Disk)))
{
    $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
}
