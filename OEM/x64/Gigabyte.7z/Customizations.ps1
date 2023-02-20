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
