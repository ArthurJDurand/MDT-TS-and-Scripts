@echo off

:LOCAL_SETTINGS
set diskpath=%~d0
set OSpath=W:

REM Fetching OS path dynamically
set vol=''
for /f "tokens=2 skip=2 delims==" %%b in ('wmic logicaldisk get caption /formaT:List') do (
	echo %%b
	pushd %%b
	cd \

	if exist Windows\System32\reagentc.exe (
	set vol=%%b
	goto OSDrivePath)
)
	 
:OSDrivePath
set OSpath=%vol%

:RecoveryPath_SET
set RecoveryPath=R:
if exist C:\Recovery\OEM\unattend.xml set OSpath=C:
:END_LOCAL_SETTINGS

:CREATE_FOLDERS
if not exist %OSpath%\Windows\OEM md %OSpath%\Windows\OEM
if not exist %OSpath%\Recovery\OEM\Apps\Logs mkdir %OSpath%\Recovery\OEM\Apps\Logs
if not exist %OSpath%\Windows\Setup\Scripts md %OSpath%\Windows\Setup\Scripts
:END_CREATE_FOLDERS

:CUSTOMIZATIONS
if exist %OSpath%\Recovery\OEM\SetupComplete.cmd copy %OSpath%\Recovery\OEM\SetupComplete.cmd %OSpath%\Windows\Setup\Scripts /y
if exist %OSpath%\Recovery\OEM\unattend.xml copy %OSpath%\Recovery\OEM\unattend.xml %OSpath%\Windows\Panther /y
:END_CUSTOMIZATIONS

:FINISHED
