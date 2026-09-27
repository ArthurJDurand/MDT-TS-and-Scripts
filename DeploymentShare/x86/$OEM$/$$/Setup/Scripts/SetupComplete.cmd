@echo off
:: Disable sleep when plugged in
powercfg /x -standby-timeout-ac 0

:: Install .NET 3.5 (Commented out)
rem DISM /Online /Enable-Feature /FeatureName:NetFx3 /All

:: Import Wi-Fi Profiles
if exist "%SystemRoot%\Setup\Scripts\Wi-Fi.xml" netsh wlan add profile filename="%SystemRoot%\Setup\Scripts\Wi-Fi.xml"
if exist "%SystemRoot%\Setup\Scripts\Wi-Fi-5GHz.xml" netsh wlan add profile filename="%SystemRoot%\Setup\Scripts\Wi-Fi-5GHz.xml"

:: Install Prerequisites
if exist "%SystemDrive%\Recovery\OEM\pre.ps1" powershell -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\pre.ps1"

:: Apply OEM Customizations
if exist "%SystemDrive%\Recovery\OEM\Customizations.ps1" powershell -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\Customizations.ps1"

:: Install OEM Apps
if exist "%SystemDrive%\Recovery\OEM\Apps\pbr.ps1" powershell -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\Apps\pbr.ps1"

:: Cleanup MDT Deployment Artifacts
if exist "%SystemDrive%\_SMSTaskSequence" rd "%SystemDrive%\_SMSTaskSequence" /s /q
if exist "%SystemDrive%\MININT" rd "%SystemDrive%\MININT" /s /q
if exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" del "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" /f /q
if exist "%SystemDrive%\LTIBootstrap.vbs" del "%SystemDrive%\LTIBootstrap.vbs" /f /q

:: Hide System Folders
attrib "%SystemDrive%\Recovery" +h +s
attrib "%SystemDrive%\Users\Default" +h +r
attrib "%SystemDrive%\Users\Default\AppData" +h
