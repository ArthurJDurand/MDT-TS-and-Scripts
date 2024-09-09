@echo off
start /wait /d %SystemDrive%\Recovery\OEM\Apps AnyDesk.exe --install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon
echo p@$$w0rd | "C:\Program Files (x86)\AnyDesk\anydesk.exe" --set-password
