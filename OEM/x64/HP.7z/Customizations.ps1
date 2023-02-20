#HP Inc. FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Where-Object {$_.Product -ne 'Not Available'} | Select-Object -ExpandProperty Product
if (-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct)))
{
    $Model = $BaseBoardProduct
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | Where-Object {$_.Version -ne 'System Version' -and $_.Version -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Version
if (-not ([string]::IsNullOrWhiteSpace($ProductVersion)))
{
    $Model = $ProductVersion
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | Where-Object {$_.Model -ne 'System Product Name' -and $_.Model -ne 'To be filled by O.E.M.'} | Select-Object -ExpandProperty Model
if (-not ([string]::IsNullOrWhiteSpace($SystemModel)))
{
    $Model = $SystemModel
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*EliteBook*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\EliteBook.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Copy-Item -Path C:\Windows\Panther\unattend.xml -Destination C:\Recovery\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP\Lights_Mainstream_6827x3840.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP\Lights_Mainstream_6827x3840.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*OMEN*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\OMEN.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*Pavilion*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Pavilion.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*ProBook*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ProBook.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Copy-Item -Path C:\Windows\Panther\unattend.xml -Destination C:\Recovery\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP\Lights_Mainstream_6827x3840.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP\Lights_Mainstream_6827x3840.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*Spectre*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Spectre.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*Victus*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Victus.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if (($Model -like '*ZBook*') -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ZBook.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Copy-Item -Path C:\Windows\Panther\unattend.xml -Destination C:\Recovery\OEM -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP\Shape_4K.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP\Shape_4K.jpg" -Force
    reg UNLOAD HKLM\temp
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Windows\OEM)))
{
    New-Item C:\Windows\OEM -itemType Directory
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell)))
{
    New-Item C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -itemType Directory
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*OMEN*') -or ($Model -like '*Victus*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\OMENCommandlCenter\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
    Copy-Item C:\Recovery\OEM\Apps\OMENCommandlCenter\TaskbarLayoutModification.xml -Destination C:\Windows\OEM -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*OMEN*') -or ($Model -like '*Victus*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\OMENCommandlCenter\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if ((!(Test-Path C:\Windows\System32\oobe\info\OOBE.xml)) -and ($OSCaption -like "*Windows 11*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Win11.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
if ((!(Test-Path C:\Windows\System32\oobe\info\OOBE.xml)) -and ($OSCaption -like "*Windows 10*"))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\HP.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Start-Process attrib.exe -ArgumentList "C:\ProgramData +h" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\system.sav\HP-LOGOS\OOBE.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "HP" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\HP Backgrounds\backgroundDefault.jpg" -Force
    reg UNLOAD HKLM\temp
}

if (Test-Path C:\system.sav)
{
    attrib C:\system.sav +h
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
