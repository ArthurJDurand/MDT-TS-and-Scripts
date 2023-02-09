@echo off​
powercfg /x -standby-timeout-ac 0
if exist %SystemDrive%\Recovery\OEM\pre.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\pre.ps1 -Verb RunAs
if exist %SystemDrive%\Recovery\OEM\Customizations.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\Customizations.ps1 -Verb RunAs
if not exist %SystemDrive%\Recovery\OEM\Apps\pbr.reg goto nopbrreg
if exist %SystemDrive%\Recovery\OEM\Apps\pbr.reg regedit /s %SystemDrive%\Recovery\OEM\Apps\pbr.reg
goto cont
:nopbrreg
if exist %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 -Verb RunAs
:cont
