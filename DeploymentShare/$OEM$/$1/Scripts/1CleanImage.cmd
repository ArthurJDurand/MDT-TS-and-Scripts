@echo off
:: BatchGotAdmin
:-----------------------------------------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )
:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    cscript "%temp%\getadmin.vbs"
    exit /B
:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"
:-----------------------------------------------------------------------
schtasks.exe /Delete /TN AddCredentials /F
rd %SystemDrive%\_SMSTaskSequence /s /q
rd %SystemDrive%\MININT /s /q
del "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" /f /q
del %SystemDrive%\LTIBootstrap.vbs /f /q
rd C:\ProgramData\Updates /s /q
net stop wuauserv
ren %systemroot%\SoftwareDistribution SoftwareDistribution.old
net start wuauserv
rd %systemroot%\SoftwareDistribution.old /s /q
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
start /wait cleanmgr /sageset
start /wait cleanmgr /sagerun
pause
(goto) 2>nul & del "%~f0"
