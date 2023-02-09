@echo off​
powercfg /x -standby-timeout-ac 0
rem DISM /Online /Enable-Feature /FeatureName:NetFx3 /All
if exist %SystemDrive%\Recovery\OEM (
  takeown /F C:\Recovery\OEM /R /D Y /SKIPSL
  ICACLS C:\Recovery\OEM /T /C /L /Q /RESET
)
if not exist %SystemRoot%\OEM md %SystemRoot%\OEM
if not exist %SystemDrive%\Recovery\OEM\Apps\Logs md %SystemDrive%\Recovery\OEM\Apps\Logs
if exist %SystemRoot%\Setup\Scripts\Wi-Fi.xml netsh wlan add profile filename=%SystemRoot%\Setup\Scripts\Wi-Fi.xml
if exist %SystemDrive%\Recovery\OEM\pre.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\pre.ps1 -Verb RunAs
if exist %SystemDrive%\Recovery\OEM\Customizations.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\Customizations.ps1 -Verb RunAs
if not exist %SystemDrive%\Recovery\OEM\Apps\pbr.reg goto nopbrreg
if exist %SystemDrive%\Recovery\OEM\Apps\pbr.reg regedit /s %SystemDrive%\Recovery\OEM\Apps\pbr.reg
goto cont
:nopbrreg
if exist %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 -Verb RunAs
:cont
if exist %SystemDrive%\_SMSTaskSequence rd %SystemDrive%\_SMSTaskSequence /s /q
if exist %SystemDrive%\MININT rd %SystemDrive%\MININT /s /q
if exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" del "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" /f /q
if exist %SystemDrive%\LTIBootstrap.vbs del %SystemDrive%\LTIBootstrap.vbs /f /q
attrib C:\Recovery +h +s
attrib C:\Users\Default +h +r
attrib C:\Users\Default\AppData +h
