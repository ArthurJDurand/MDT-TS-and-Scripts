TITLE TEAM VLOCITY - DISKEEPER LICENSE REGISTRATOR
::==============================================================================
:: MAIN CONFIGURATION SETTINGS
cls
SetLocal EnableDelayedExpansion
:: Stop BenefitsPopup from Task
tasklist /fi "imagename eq BenefitsPopup.exe" | find /i /n "BenefitsPopup.exe" >nul
if %ERRORLEVEL%==0 taskkill /f /t /im BenefitsPopup.exe >nul
Timeout 2 >nul
:: Stop DKService
Net stop Diskeeper
SET user=
echo.
::Maintenance
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper" /f /v "IsTrialware" /t Reg_Dword /d "0" >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper" /f /v "OfflineActProxy" /t Reg_Sz /d "" >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper" /f /v "OfflineActRetCode" /t Reg_Dword /d "0" >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper" /v "OriginatorID" /t Reg_Sz /d "1" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper" /v "RID" /t Reg_Sz /d "1" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\UserSettings" /v "PACKey" /t Reg_Sz /d "%user%" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\UserSettings" /v "AutoCheckForUpdates" /t Reg_Dword /d "0" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\UserSettings" /v "ActivateOnFirstStartup" /t Reg_Dword /d "1" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\UserSettings" /v "CheckForUpdate" /t Reg_Dword /d "0" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\UserSettings" /v "ActivationReminderPattern" /t Reg_Sz /d "" /f >nul
Reg Add "HKLM\SOFTWARE\Diskeeper Corporation\Diskeeper\Promotion" /v "PublicType" /t Reg_Dword /d "2" /f >nul
for /f "eol=E tokens=*" %%F in ('reg query HKCR\CLSID /s /k /e /c /f MiscStatus /v Data /t REG_BINARY') do set status=1&reg delete %%F /f >nul
for /f "eol=E tokens=*" %%G in ('reg query HKLM\SOFTWARE\Classes\CLSID /s /k /e /c /f MiscStatus /v Data /t REG_BINARY') do set status=1&reg delete %%G /f >nul
Timeout 1 >nul
Net start Diskeeper 
Echo DISKEEPER LICENSE APPLIED.
Echo.
EndLocal
