#Dell Inc. FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"
$Customizations = 'C:\Recovery\OEM\Customizations.7z'
$Destination = 'C:\'
Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\OEM\OobeLogo.png" -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Dell\Win LtBlue 1920x1200.jpg" -Type ExpandString -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Dell" -Force
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Dell\Win LtBlue 1920x1200.jpg" -Force
reg UNLOAD HKLM\temp

$BaseBoardProduct = Get-WmiObject Win32_BaseBoard | Select Product
if ((-not ([string]::IsNullOrWhiteSpace($BaseBoardProduct))) -or ($BaseBoardProduct.Product -eq 'Not Available'))
{
    [String]$Model = ($BaseBoardProduct.Product).ToString()
}

$ProductVersion = Get-WmiObject -Class:Win32_ComputerSystemProduct | select Version
if ((-not ([string]::IsNullOrWhiteSpace($ProductVersion))) -or ($ProductVersion.Version -eq 'System Version') -or ($ProductVersion.Version -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($ProductVersion.Version).ToString()
}

$SystemModel = Get-WmiObject -Class:Win32_ComputerSystem | select Model
if ((-not ([string]::IsNullOrWhiteSpace($SystemModel))) -or ($SystemModel.Model -eq 'System Product Name') -or ($SystemModel.Model -eq 'To be filled by O.E.M.'))
{
    [String]$Model = ($SystemModel.Model).ToString()
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Windows\OEM)))
{
    New-Item C:\Windows\OEM -itemType Directory
}

if ((Test-Path C:\Recovery\OEM\LayoutModification.*) -and (!(Test-Path C:\Users\Default\AppData\Local\Microsoft\Windows\Shell)))
{
    New-Item C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -itemType Directory
}

If ($Model -like '*Precision*')
{
    regedit /s C:\Recovery\OEM\StoreContent\Precision.reg
}

If ($Model -like '*OptiPlex*')
{
    regedit /s C:\Recovery\OEM\StoreContent\Optiplex.reg
}

If ($Model -like '*Latitude*')
{
    regedit /s C:\Recovery\OEM\StoreContent\Latitude.reg
}

If ($Model -like '*XPS*')
{
    regedit /s C:\Recovery\OEM\StoreContent\XPS.reg
}

If (($Model -like '*Alienware*') -or ($Model -like '*Virt*'))
{
    regedit /s C:\Recovery\OEM\StoreContent\Alienware.reg
}

If (($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*'))
{
    regedit /s C:\Recovery\OEM\StoreContent\Inspiron.reg
}

If (($Model -like '*Vostro*') -or ($Model -like '*Cheng*'))
{
    regedit /s C:\Recovery\OEM\StoreContent\Vostro.reg
}

If ($Model -like '*Embedded*')
{
    regedit /s C:\Recovery\OEM\StoreContent\Embedded.reg
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DCU\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Precision*') -or ($Model -like '*OptiPlex*') -or ($Model -like '*Latitude*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DCU\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DDD\awuwp\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Alienware*') -or ($Model -like '*Virt*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DDD\awuwp\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DU\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*XPS*') -or ($Model -like '*Venue*') -or ($Model -like '*Inspiron*') -or ($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*') -or ($Model -like '*Vostro*') -or ($Model -like '*Cheng*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\DU\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

If (($Model -like '*G15*') -or ($Model -like '*G7*') -or ($Model -like '*G5*') -or ($Model -like '*G3*'))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\G.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\System32\OEM\OobeLogo.png" -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\Dell\dell_gaming_g_series_wallpaper_backlight_16x9_warm.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Dell" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\Dell\dell_gaming_g_series_wallpaper_backlight_16x9_warm.jpg" -Force
    reg UNLOAD HKLM\temp
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
