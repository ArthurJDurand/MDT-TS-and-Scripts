$Disk = Get-Disk | Where-Object -FilterScript {$_.Bustype -Ne "USB"}

if (!([string]::IsNullOrWhiteSpace($Disk)))
{
    $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
}
