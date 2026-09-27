@echo off
setlocal EnableExtensions

set "INSTALLER=%SystemDrive%\Recovery\OEM\Apps\AnyDesk.exe"
set "TARGET_DIR=C:\Program Files\AnyDesk"
set "ANYDESK_EXE=%TARGET_DIR%\anydesk.exe"
set "PASSWORD=p@$$w0rd"

if not exist "%INSTALLER%" (
    echo ERROR: Installer not found at "%INSTALLER%"
    exit /b 1
)

echo Launching AnyDesk silent installer...
start "" /wait "%INSTALLER%" --install "%TARGET_DIR%" --start-with-win --silent --create-shortcuts --create-desktop-icon

:: Poll for the binary up to 60 seconds
set "TIMEOUT=60"
set "ELAPSED=0"
:loop
if exist "%ANYDESK_EXE%" goto installed
if %ELAPSED% geq %TIMEOUT% goto timeout
timeout /t 2 /nobreak >nul
set /a ELAPSED+=2
goto loop

:timeout
echo ERROR: AnyDesk installation timed out.
exit /b 1

:installed
echo AnyDesk installed successfully.

:: Set permanent password
echo %PASSWORD% | "%ANYDESK_EXE%" --set-password
if %errorlevel% neq 0 (
    echo WARNING: Failed to set AnyDesk password (exit code %errorlevel%).
    exit /b 1
)
echo AnyDesk password configured successfully.
exit /b 0
