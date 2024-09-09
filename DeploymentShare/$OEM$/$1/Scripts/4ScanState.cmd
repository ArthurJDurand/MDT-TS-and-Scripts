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
devmgmt.msc
attrib C:\Recovery +h +s
IF %PROCESSOR_ARCHITECTURE% == x86 (IF NOT DEFINED PROCESSOR_ARCHITEW6432 goto bit32)
goto bit64
:bit32
powershell.exe -ExecutionPolicy Bypass -File "%~dp0\ScanStatex86.ps1" -Verb RunAs
goto cont
:bit64
powershell.exe -ExecutionPolicy Bypass -File "%~dp0\ScanStatex64.ps1" -Verb RunAs
:cont
pause
if exist %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 powershell -ExecutionPolicy bypass -File %SystemDrive%\Recovery\OEM\Apps\pbr.ps1 -Verb RunAs
shutdown /r
(goto) 2>nul & del "%~f0"
