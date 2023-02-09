#Gigabyte Technology FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"
$Customizations = 'C:\Recovery\OEM\Customizations.7z'
$Destination = 'C:\'
Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\System32\oobe\info\backgrounds\backgrounddefault.jpg" -Type ExpandString -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Gigabyte" -Force
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\System32\oobe\info\backgrounds\backgrounddefault.jpg" -Force
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

if ($Model -like '*AERO*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\AERO.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\gigabyte\GIGABYTE-1920x1080-Black.jpg" -Type ExpandString -Force
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Gigabyte" -Force
    reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
    Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\gigabyte\GIGABYTE-1920x1080-Black.jpg" -Force
    reg UNLOAD HKLM\temp
}

if (Test-Path C:\OEMLOGO)
{
    attrib C:\OEMLOGO +h
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
