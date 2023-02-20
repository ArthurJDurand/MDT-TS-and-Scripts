#Acer Inc. FEB 2023

$WinRAR = "C:\Program Files\WinRAR\WinRAR.exe"
$OEM = 'C:\Recovery\OEM\OEM.7z'
$Destination = 'C:\OEM'
Start-Process $Winrar -ArgumentList "x -o+ `"$OEM`" $Destination" -NoNewWindow -Wait

$Customizations = 'C:\Recovery\OEM\Customizations\Acer.7z'
$Destination = 'C:\Windows\'
Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait

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

if ($Model -like '*Aspire*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Aspire.7z'
    $Destination = 'C:\Windows\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if ($Model -like '*Nitro*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Nitro.7z'
    $Destination = 'C:\Windows\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if ($Model -like '*Travelmate*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\Travelmate.7z'
    $Destination = 'C:\Windows\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
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
If (($Model -like '*Nitro*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\NitroSense\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Nitro*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\NitroSense\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Predator*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\PredatorSense\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*Predator*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\PredatorSense\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\OEM\Preload\DPOP\OEMResource\Logo\Acer\OEM_OOBE.png" -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\Web\Wallpaper\acer01.jpg" -Type ExpandString -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "Acer" -Force
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\Web\Wallpaper\acer01.jpg" -Force
reg UNLOAD HKLM\temp

if (Test-Path C:\OEM)
{
    attrib C:\OEM +h
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
