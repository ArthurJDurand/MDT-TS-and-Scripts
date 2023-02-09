#Huawei Technologies Co., Ltd. FEB 2023

$PCManager = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'PC Manager' })
if ([string]::IsNullOrWhiteSpace($PCManager))
{
    $PCManager = (Get-ItemProperty HKLM:Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -Match 'PC Manager' })
}

if ([string]::IsNullOrWhiteSpace($PCManager))
{
    $PCM = Get-ChildItem -File C:\Recovery\OEM\Apps\PCM -Filter "*.exe" | Select-Object -ExpandProperty FullName
    Start-Process $PCM -Wait
}
