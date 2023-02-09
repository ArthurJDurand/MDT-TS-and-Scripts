#Microsoft Corp. FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"
$Customizations = 'C:\Recovery\OEM\Customizations.7z'
$Destination = 'C:\Windows\'
Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\web\wallpaper\Surface\Surface.png" -Type ExpandString -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Surface" -Force
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\web\wallpaper\Surface\Surface.png" -Force
reg UNLOAD HKLM\temp

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
