#Lenovo Group Limited, FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Where-Object {$_.Version -ne 'System Version' -and $_.Version -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Version
if (-not ([string]::IsNullOrWhiteSpace($ProductVersion)))
{
    $Model = $ProductVersion
}

if ($Model -like '*IdeaPad*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\IdeaPad.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo3_Idea -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*Legion*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Legion.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo3_Idea -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*Thinkbook*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Thinkbook.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo2_Think -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*ThinkCentre*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ThinkCentre.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo2_Think -Force
    Copy-Item -Path C:\Windows\Panther\unattend.xml -Destination C:\Recovery\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\ThinkPad-ThinkCentre_wallpaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\ThinkPad-ThinkCentre_wallpaper.png" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*ThinkPad*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ThinkPad.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo2_Think -Force
    Copy-Item -Path C:\Windows\Panther\unattend.xml -Destination C:\Recovery\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\ThinkFamily_Wallpaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\ThinkFamily_Wallpaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*Flex*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Flex.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo3_Idea -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*V15*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\V15.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo3_Idea -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ($Model -like '*Yoga*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Yoga.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value Lenovo3_Idea -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

if (!(Test-Path C:\Windows\System32\oobe\info\OOBE.xml))
{
    $Customizations = 'C:\Recovery\OEM\Customizations.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\oobe\info\Lenovo_BrandIcon.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Lenovo" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Lenovo\LenovoWallPaper.jpg" -Force
    reg UNLOAD HKLM\temp
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
