if (!(Test-Path C:\Recovery\OEM\Apps))
{
    New-Item C:\Recovery\OEM\Apps -itemType Directory
}

if (Test-Path C:\Recovery\OEM\Apps\Update.ps1)
{
    Remove-Item C:\Recovery\OEM\Apps\Update.ps1 -Force
}

Invoke-WebRequest https://api.onedrive.com/v1.0/shares/s!AgS7zfLQOVekkIlY1dF4vzEON6-MZA/root/content -OutFile C:\Recovery\OEM\Apps\Update.ps1
Unblock-File -Path C:\Recovery\OEM\Apps\Update.ps1
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File C:\Recovery\OEM\Apps\Update.ps1" -Wait
