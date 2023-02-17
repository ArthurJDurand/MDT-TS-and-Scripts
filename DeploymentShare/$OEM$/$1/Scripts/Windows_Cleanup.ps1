# Written by Fabian Castagna
# Used as a complete windows cleanup tool
# 15-7-2016
function Delete-ComputerRestorePoints{
	[CmdletBinding(SupportsShouldProcess=$True)]param(  
	    [Parameter(
	        Position=0, 
	        Mandatory=$true, 
	        ValueFromPipeline=$true
		)]
	    $restorePoints
	)
	begin{
		$fullName="SystemRestore.DeleteRestorePoint"
		#check if the type is already loaded
		$isLoaded=([AppDomain]::CurrentDomain.GetAssemblies() | foreach {$_.GetTypes()} | where {$_.FullName -eq $fullName}) -ne $null
		if (!$isLoaded){
			$SRClient= Add-Type   -memberDefinition  @"
		    	[DllImport ("Srclient.dll")]
		        public static extern int SRRemoveRestorePoint (int index);
"@  -Name DeleteRestorePoint -NameSpace SystemRestore -PassThru
		}
	}
	process{
		foreach ($restorePoint in $restorePoints){
			if($PSCmdlet.ShouldProcess("$($restorePoint.Description)","Deleting Restorepoint")) {
		 		[SystemRestore.DeleteRestorePoint]::SRRemoveRestorePoint($restorePoint.SequenceNumber)
			}
		}
	}
}

Write-Host "Deleting System Restore Points"
	Get-ComputerRestorePoint | Delete-ComputerRestorePoints # -WhatIf

	Write-host "Checking to make sure you have Local Admin rights" -foreground yellow
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        Write-Warning "Please run this script as an Administrator!"
        If (!($psISE)){"Press any key to continue…";[void][System.Console]::ReadKey($true)}
        Exit 1
    }

Write-Host "Capture current free disk space on Drive C" -foreground yellow
    $FreespaceBefore = (Get-WmiObject win32_logicaldisk -filter "DeviceID='C:'" | select Freespace).FreeSpace/1GB

Write-host "Deleting Rogue folders" -foreground yellow
	if (test-path C:\_SMSTaskSequence) {remove-item -Path C:\_SMSTaskSequence -force -recurse}
    if (test-path C:\Config.Msi) {remove-item -Path C:\Config.Msi -force -recurse}
    if (test-path C:\dell) {remove-item -Path C:\dell -force -recurse}
    if (test-path C:\DRIVERS) {remove-item -Path C:\DRIVERS -force -recurse}
    if (test-path C:\drvtemp) {remove-item -Path C:\drvtemp -force -recurse}
	if (test-path C:\hpswsetup) {remove-item -Path C:\hpswsetup -force -recurse}
	if (test-path C:\Intel) {remove-item -Path C:\Intel -force -recurse}
	if (test-path C:\LTIBootstrap.vbs) {remove-item C:\LTIBootstrap.vbs -force}
	if (test-path C:\MININT) {remove-item -Path C:\MININT -force -recurse}
	if (test-path C:\PerfLogs) {remove-item -Path C:\PerfLogs -force -recurse}
	if (test-path C:\swsetup) {remove-item -Path C:\swsetup -force -recurse}
	if (test-path C:\Temp) {remove-item -Path C:\Temp -force -recurse}
	if (test-path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk") {remove-item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" -force}

Write-host "Removing Windows Updates Downloads" -foreground yellow
    Stop-Service wuauserv -Force -Verbose
	Stop-Service TrustedInstaller -Force -Verbose
    Remove-Item -Path "$env:windir\SoftwareDistribution\*" -Force -Recurse
    Start-Service wuauserv -Verbose
	Start-Service TrustedInstaller -Verbose

Write-host "Cleaning Windows Component Store" -foreground yellow
	Start-Process -FilePath DISM.exe -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup"  -WindowStyle Hidden -Wait

Write-host "Running Windows System Cleanup" -foreground yellow
    Start-Process -FilePath cleanmgr.exe -ArgumentList /sagerun  -WindowStyle Hidden -Wait

Write-host "Clearing All Event Logs" -foreground yellow
    wevtutil el | Foreach-Object {Write-Host "Clearing $_"; wevtutil cl "$_"}

Write-host "Disk Usage before and after cleanup" -foreground yellow
    $FreespaceAfter = (Get-WmiObject win32_logicaldisk -filter "DeviceID='C:'" | select Freespace).FreeSpace/1GB
    "Free Space Before: {0}" -f $FreespaceBefore
    "Free Space After: {0}" -f $FreespaceAfter

Remove-Item $PSCommandPath -Force
