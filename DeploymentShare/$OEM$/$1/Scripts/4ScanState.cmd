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
if not exist C:\Recovery\OEM\Logs md C:\Recovery\OEM\Logs
C:\Temp\ScanState\scanstate.exe /apps /ppkg C:\Recovery\Customizations\usmt.ppkg /i:C:\Temp\ScanState\OEMCustomizations.xml /config:C:\Temp\ScanState\Config_AppsAndSettings.xml /o /c /v:13 /l:C:\Recovery\OEM\Logs\ScanState.log
rd C:\Temp /s /q
pause
powercfg.exe /batteryreport
move battery-report.html %UserProfile%\Desktop
%UserProfile%\Desktop\battery-report.html
(goto) 2>nul & del "%~f0"
