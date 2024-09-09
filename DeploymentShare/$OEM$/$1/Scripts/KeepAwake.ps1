# Keep the system awake
Add-Type -AssemblyName System.Windows.Forms
while ($true) {
    [System.Windows.Forms.SendKeys]::SendWait('+{F15}')
    Start-Sleep -Seconds 59
}
