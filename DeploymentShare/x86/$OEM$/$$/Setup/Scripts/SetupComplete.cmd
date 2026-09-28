@echo off
setlocal EnableExtensions

:: =========================================================
:: SetupComplete.cmd
:: OEM Deployment Orchestrator (Hardened)
:: =========================================================

:: Log Configuration
set "LogDir=%ProgramData%\OEM\Logs"
set "LogFile=%LogDir%\SetupComplete.log"

if not exist "%LogDir%" mkdir "%LogDir%" >nul 2>&1

(
echo =========================================================
echo SetupComplete Started
echo Date: %DATE%
echo Time: %TIME%
echo Computer: %COMPUTERNAME%
echo =========================================================
)>>"%LogFile%"

:: Disable sleep while plugged in
echo [%DATE% %TIME%] Configuring power settings...>>"%LogFile%"
powercfg /x -standby-timeout-ac 0 >>"%LogFile%" 2>&1

:: Run Pre-Requisites
if exist "%SystemDrive%\Recovery\OEM\pre.ps1" (
    echo [%DATE% %TIME%] Running pre.ps1...>>"%LogFile%"
    powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\pre.ps1" >>"%LogFile%" 2>&1
    set "RC=%ERRORLEVEL%"
    echo [%DATE% %TIME%] pre.ps1 exit code: %RC%>>"%LogFile%"
)

:: Apply OEM Customizations
if exist "%SystemDrive%\Recovery\OEM\Customizations.ps1" (
    echo [%DATE% %TIME%] Running Customizations.ps1...>>"%LogFile%"
    powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\Customizations.ps1" >>"%LogFile%" 2>&1
    set "RC=%ERRORLEVEL%"
    echo [%DATE% %TIME%] Customizations.ps1 exit code: %RC%>>"%LogFile%"
)

:: Install OEM Applications
if exist "%SystemDrive%\Recovery\OEM\Apps\pbr.ps1" (
    echo [%DATE% %TIME%] Running pbr.ps1...>>"%LogFile%"
    powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SystemDrive%\Recovery\OEM\Apps\pbr.ps1" >>"%LogFile%" 2>&1
    set "RC=%ERRORLEVEL%"
    echo [%DATE% %TIME%] pbr.ps1 exit code: %RC%>>"%LogFile%"
)

:: MDT / Deployment Cleanup (safe post-OOBE)
echo [%DATE% %TIME%] Cleaning deployment artifacts...>>"%LogFile%"
if exist "%SystemDrive%\_SMSTaskSequence" rd /s /q "%SystemDrive%\_SMSTaskSequence" >>"%LogFile%" 2>&1
if exist "%SystemDrive%\MININT" rd /s /q "%SystemDrive%\MININT" >>"%LogFile%" 2>&1
if exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" del /f /q "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\LiteTouch.lnk" >>"%LogFile%" 2>&1
if exist "%SystemDrive%\LTIBootstrap.vbs" del /f /q "%SystemDrive%\LTIBootstrap.vbs" >>"%LogFile%" 2>&1

:: Set folder attributes on Default user profile (Recovery already secured above)
echo [%DATE% %TIME%] Setting folder attributes on Default profile...>>"%LogFile%"
if exist "%SystemDrive%\Users\Default" (
    attrib +h "%SystemDrive%\Users\Default" >>"%LogFile%" 2>&1
)
if exist "%SystemDrive%\Users\Default\AppData" (
    attrib +h "%SystemDrive%\Users\Default\AppData" >>"%LogFile%" 2>&1
)

(
echo =========================================================
echo SetupComplete Finished
echo Date: %DATE%
echo Time: %TIME%
echo =========================================================
)>>"%LogFile%"

endlocal
exit /b 0
