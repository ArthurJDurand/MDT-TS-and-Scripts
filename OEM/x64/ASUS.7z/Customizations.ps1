#ASUSTek Computer Inc. FEB 2023

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

if ($Model -like '*ExpertBook*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\EB.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if ($Model -like '*ROG*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ROG.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if ($Model -like '*TUF*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\TUF.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if ($Model -like '*VivoBook*')
{
    $Customizations = 'C:\Recovery\OEM\Customizations\VB.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if (($Model -like '*UX481*') -or ($Model -like '*UX482*') -or ($Model -like '*UX582*') -or ($Model -like '*UX8402*'))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ZBPD.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

if (($Model -like '*ZenBook*') -and (!(Test-Path C:\Windows\ASUS\*)))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ZB.7z'
    $Destination = 'C:\'
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
If (($Model -like '*PRIME*') -or ($Model -like '*ROG*') -or ($Model -like '*TUF*') -and ($OSCaption -like "*Windows 11*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ArmouryCrate\LayoutModification.json -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

$OSCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption
If (($Model -like '*PRIME*') -or ($Model -like '*ROG*') -or ($Model -like '*TUF*') -and ($OSCaption -like "*Windows 10*"))
{
    Copy-Item C:\Recovery\OEM\Apps\ArmouryCrate\LayoutModification.xml -Destination C:\Users\Default\AppData\Local\Microsoft\Windows\Shell -Force
}

if (!(Test-Path C:\Windows\ASUS\*))
{
    $Customizations = 'C:\Recovery\OEM\Customizations\ASUS.7z'
    $Destination = 'C:\'
    Start-Process $Winrar -ArgumentList "x -o+ `"$Customizations`" $Destination" -NoNewWindow -Wait
}

Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name BrandIcon -Value "C:\Windows\ASUS\ASUSlogo.png" -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name DesktopBackground -Value "C:\Windows\ASUS\Wallpapers\ASUS.jpg" -Type ExpandString -Force
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes -Name ThemeName -Value "ASUS" -Force
reg LOAD HKLM\temp C:\Users\Default\ntuser.dat
Set-ItemProperty -Path "HKLM:\temp\Control Panel\Desktop" -Name WallPaper -Value "C:\Windows\ASUS\Wallpapers\ASUS.jpg" -Force
reg UNLOAD HKLM\temp

$HardwareType = Get-WmiObject -Class Win32_ComputerSystem -Property PCSystemType
If ($HardwareType.PCSystemType -eq 2)
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Store -Name StoreContentModifier -Value ASUS2_Notebook -Force
}

attrib C:\Users\Default +h +r
attrib C:\Users\Default\NTUSER.DAT +a +h +i
attrib C:\Users\Default\AppData +h
