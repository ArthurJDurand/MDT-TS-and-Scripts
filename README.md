# MDT-TS-and-Scripts  
  
  
  
MDT Task Sequences and Custom Scripts to  
  
1) Deploy 64-bit Windows 10 Pro and 64-bit Windows 11 Pro  
2) Extract OEM customizations and drivers  
3) Install third party software
  
  
  
Skills and experience required!  
The most important prerequisite is knowledge and expertise in the following areas  
Microsoft Windows Server and Desktop Editions of Microsoft Windows!  
Networking!  
Deploying Desktop Editions of Microsoft Windows!  
Windows ADK!  
MDT!  
The software mentioned below in the Prerequisites section!  
  
  
  
Prerequisites  
  
  
A Server running Windows Server OS with at least the DHCP Server and WDS Server Roles installed and configured!  
or a desktop PC running a desktop edition of Windows like Windows 10 or Windows 11!  
  
If you have a server  
Add and configure the DHCP Server and WDS Server Roles  
I have added my Windows Server DHCP configuration backup in the Prerequisites folder of this repository, you can just import my DHCP config and edit the DCHP scope to suit your network environment!  
Import your boot images contained in the Boot folder of your deployment share into WDS Server!  
  
  
Otherwise use your desktop PC as a Deployment Server  
I included AOMEI PXE Boot (Free edition) in the Prerequisites folder of this repository, you can just install it on your Windows Desktop Edition if you don't have a Server!  
Install AOMEI PXE Boot server and browse to the boot images contained in the Boot folder of your deployment share, use the appropriate image to PXE boot into from the PC you want to deploy WIndows to!  
  
For simplicity you may name your deployment server "SERVER" and create a user account named "Network User" (without quotes) with password "p@$$w0rd" (without quotes) and with administrative privileges!  
  
  
Before using this repository install the latest version of the following!  
  
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Windows PE Addon for the Windows ADK --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--  
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--  
KB4564442 for MDT --> https://support.microsoft.com/en-us/topic/windows-10-deployments-fail-with-microsoft-deployment-toolkit-on-computers-with-bios-type-firmware-70557b0b-6be3-81d2-556f-b313e29e2cb7 <--  
  
  
You will need to create a new deployment share before using this repository!  
For simplicity create your deployment share in the default location (C:\DeploymentShare)  
After creating your deployment share, copy the contents of the DeploymentShare folder from this repository into your deployment share folder replacing existing files!  
Please note that due to file size and bandwidth limitation of GitHub, the Boot images, Out-of-Box drivers and Operating System Images is missing from this repository! Download the DeploymentShare (which contains the missing content) from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and extract then copy the contents of the DeploymentShare folder from my shared OneDrive folder into your deployment share folder replacing existing files!  
  
Please edit the following files inside the Control folder in your deployment share  
  
Bootstrap.ini - If your deployment server is not named SERVER, and if the user account is not Network User, and the password is not p@$$w0rd - edit DeployRoot, UserID, UserPassword and UserDomain. You can use a local or domain user account as UserID. You can use your deployment server's network name and add ".local" (without quates) as the UserDomain.  
CustomSettings.ini  
Medias.xml - For simplicity create the folder structure “C:\Deploy\MDT", otherwise create your own folder structure for an offline media set which you can copy to a USB flash drive. If you created your own folder structure instead of "C:\Deploy\MDT" - make sure your folder structure corresponds with Root in Medias.xml.  
Settings.xml - Make sure that UNCPath and PhysicalPath corresponds with your deployment share's network and local path. Replace "C:\DeploymentShare" at Boot.x86.ExtraDirectory and Boot.x64.ExtraDirectory with the local path to your deployment share if necessary.  
WIN1XPROX64\Unattend.xml - Edit the locales and time zone to match your locales and time zone.  
  
  
Next, you'll need to download my Windows 10 and Windows 11 lite touch images and place it inside the appropriate folder in the Operating Systems folder in your deployment share or use your own! If you choose to use your own Windows 10 and 11 images, place the appropriate install.wim files in Win10Prox64 and Win11Prox64 folders in the Operating Systems folder of your deployment share! If you did not modify your own images in Audit Mode, please remove the line containing CopyProfile from the unattend.xml located in the WIN10PROX64 and WIN11PROX64 folders in the Control folder from your deployment share!  
  
My Windows 10 and 11 Pro images  
I did not add any third-party software to my images!  
I only added the optional component NETFX 3.5 and installed the en-GB optional language features!  
I installed the latest updates!  
I preinstalled Microsoft Office 365 Retail!  
I did not modify the image in any other way!  
You can download my Images from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <--
  
  
  
Custom scripts ran as part of the task sequence during OS deployment  
  
CopyOEM.wsf (in the Scripts folder in your deployment share) - Copies the contents of the "$OEM$" folder from the deployment share as part of the task sequence during OS deployment for more information see --> https://techcommunity.microsoft.com/t5/windows-blog-archive/copying-oem-files-and-folders-with-mdt-2012-update-1/ba-p/706642 <--  
The following PowerShell scripts in the Custom folder inside the Scripts folder of your deployment share  
LoadStorageDriver.ps1 - Loads the latest Intel VMD storage driver required for some 10th and 11th Generation Intel Platforms as part of the task sequence during OS deployment!  
CleanFixedDrives.ps1 - Will wipe all internal drives on the target computer during as part of the task sequence during OS deployment!  
SetTargetOSDrive.ps1 - Sets the first/only NVMe SSD, or the first/only SATA SSD if no NVMe SSD, or the first/only drive as the target OS drive as part of the task sequence during OS deployment!  
CreateRecoveryPartition-BIOS.ps1 / CreateRecoveryPartition-UEFI.ps1 - Shrinks the Windows partition to 1GB in size and create the Recovery partition as part of the task sequence during OS deployment!  
FormatDataDrive.ps1 - Formats any one additional internal drive as a Data drive as part of the task sequence during OS deployment!  
VerifyWinRE.ps1 - Verifies that the WinPE Recovery environment was copied to the Recovery drive as part of the task sequence during OS deployment!  
ApplyUpdates10x64.ps1 / ApplyUpdates11.ps1 - Expects .cab/.msu update packages contained in a folder named Updates located on a network share at "\\\\SERVER\Shared", or on the root of a USB flash drive labeled DEPLOY, then copies and applies the update packages as part of the task sequence during OS deployment! The folder structure is included in this repository, just copy the folder named Updates included in this repository to a network share located at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY!  
ExtractOEMAppsx64.ps1 - Expects .7z archives located in a folder named x64 on a network share at "\\\\SERVER\OEM" or in a folder named x64 within a folder named OEM on a USB flash drive labeled DEPLOY, then extracts the OEM apps to the deployed OS as part of the task sequence during OS deployment!  
ExtractOEMDrivers.ps1 - Expects .7z archives located in a folder named DriverPacks on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY, then extracts OEM drivers as part of the task sequence during OS deployment!  
ApplyOEMDrivers.ps1 - Applies the extracted OEM drivers to the deployed OS as part of the task sequence during OS deployment!  
CleanupScripts.ps1 - Cleans up MDT scripts copied to the OS drive after OS deployment as part of the task sequence during OS deployment!
  
  
  
Please note that due to file size and bandwidth limitation of GitHub, the boot images is missing from this repository! You'll have to update your deployment share to recreate the boot images!
  
  
  
"$OEM$" folder  
  
The unattend.xml of the OS being deployed expects to find and run SetupComplete.cmd located in C:\Windows\Setup\Scripts.  
The "$OEM$" folder contains everything including the SetupComplete.cmd file that will be copied to C:\Windows\Setup\Scripts during OS deployment.  
You may modify the contents of the "$OEM$" folder as you desire.
  
  
  
OEM Apps  
  
OEM gets extracted to the deployed OS as part of the task sequence during OS deployment!  
OEM Apps should be archived using 7-Zip and placed in a folder named x64 on a network share at "\\\\SERVER\OEM" or in a folder named x64 within a folder named OEM on a USB flash drive labeled DEPLOY!  
If you place OEM apps in a different network share, please edit DeploymentShare\Scripts\Custom\ExtractOEMAppsx64.ps1 accordingly!  
This repository contains the scripts used to install OEM apps during the OOBE process of Windows Setup, apps for OEMs has been deleted due to GitHub size restrictions, you may download the complete archives from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <--  
I used Dell's extensibility points as base for all OEM apps and customizations!  
I only included necessary OEM apps without additional bloatware!
  
  
  
Local Group Policies  
  
"DeploymentShare\\$OEM$\\$1\Recovery\OEM\LGPO" sets the following local group policies  
Configure automatic updates - Enabled  
Enabling Windows Update Power Management to automatically wake up the system to install scheduled updates - Enabled  
Turn on recommended updates via Automatic Updates - Enabled  
Always automatically restart at the scheduled time - Enabled  
Configure auto-restart reminder notifications for updates - Enabled  
Turn off auto-restart for updates during active hours - Enabled  
Turn off hybrid sleep (on battery) - Disabled  
Turn off hybrid sleep (plugged in) - Disabled  
Turn off the hard disk (on battery) - Enabled  
Turn off the hard disk (plugged in) - Enabled  
Prevent AutoPlay from remembering user choices - Enabled  
Turn off Microsoft Defender Antivirus - Disabled  
Turn off routine remediation - Disabled  
Allow antimalware service to remain running always - Enabled  
Allow antimalware service to startup with normal priority - Enabled  
Configure detection for potentially unwanted applications - Enabled  
Configure the 'Block At First Sight Feature' - Enabled  
Join Microsoft MAPS - Enabled  
Configure extended cloud check - Enabled  
Select cloud protection level - Disabled  
You may set your own group policies on a computer with no group policies set, then use the LGPO tool to backup your group policies. After backing up your own group policies, delete the contents of the Backup folder in the LGPO folder, and copy your own backup into the same folder! For usage of the LGPO tool run "LGPO.exe /?" (without quotes in an elevated command prompt!  
If you do not wish to enforce any group policies, just delete the LGPO folder and delete the following code from the pre.ps1 PowerShell script  
& C:\Recovery\OEM\LGPO\LGPO.exe /g C:\Recovery\OEM\LGPO\Backup
  
  
  
Please feel free and contribute by assisting me in improving any/all scripts contained in this repository and by adding original resources to the OEM Apps and Customizations contained in this repository!
  
  
Perhaps a PowerShell script can be included to run as part of the task sequence during OS deployment that sets the target edition of Windows according to the OEM license (e.g. Home Single Language)! To activate OEM Home Single Language edition "DeploymentShare\\$OEM$\\$1\Recovery\OEM\pre.ps1" should be modified not just to activate Pro OEM, and local group policies that get applied should be limited to Pro edition.  
I am unable to find an easy solution to check and set the deployed OS to match the OEM license edition!
  
  
  
pre.ps1  
  
If the deployed Windows edition is set according to OEM license during OS deployment, "DeploymentShare\\$OEM$\\$1\Recovery\OEM\pre.ps1" should be edited to activate the non-pro edition by replacing the following  
$OPK = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey  
$OPKDesc = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKeyDescription  
if (($OPKDesc -like "*Professional*") -and (-not ([string]::IsNullOrWhiteSpace($OPKDesc))))  
{  
  cscript C:\Windows\System32\slmgr.vbs /ipk $OPK  
  cscript C:\Windows\System32\slmgr.vbs /ato  
}  
  
with  
  
$OPK = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey  
if (-not ([string]::IsNullOrWhiteSpace($OPKDesc)))  
{  
  cscript C:\Windows\System32\slmgr.vbs /ipk $OPK  
  cscript C:\Windows\System32\slmgr.vbs /ato  
}  
  
Limiting the local group policies to Pro edition by replacing the following line  
& C:\Recovery\OEM\LGPO\LGPO.exe /g C:\Recovery\OEM\LGPO\Backup  
with  
$OPKDesc = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKeyDescription  
if ($OPKDesc -like "*Professional*")  
{  
  & C:\Recovery\OEM\LGPO\LGPO.exe /g C:\Recovery\OEM\LGPO\Backup  
}  
  
  
  
Offline Media  
  
You may create an offline media set that you can copy to a USB flash drive!  
Please format a USB flash drive with the FAT32 partition style and label the flash drive "DEPLOY" (without quotes), then set the partition as active!  
Copy the Content of your Media Set (Default location C:\Deploy\MDT\Content) to the root of the USB flash drive labeled DEPLOY!  
Create the folder structure OEM\x64 on the USB flash drive labeled DEPLOY!  
Copy the OEM apps downloaded in .7z archive format - downloaded from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- to OEM\x64 on the USB flash drive labeled DEPLOY!  
Copy the Updates folder included in this repository containing any .cab and .msu updates (you'll have to download and add updates yourself) to the root of the USB flash drive labeled DEPLOY!
  
  
  
After OS deployment, create a user account on the PC that the OS was deployed to, log in and apply updates and drivers via Windows Update (including Optional Driver updates, and via OEM update apps!  
Use the Scripts in C:\Scripts on the PC that the OS was deployed to - to clean up the image after updates and driver installs - to capture drivers to a network share or USB flash drive labeled DEPLOY (for reuse on same model) - to create a provisioned package for push-button reset!  
Running the numbered .cmd scripts will run the accompanying PowerShell scripts, there is no need to run the PowerShell scripts separately!  
The following PowerShell scripts in C:\Scripts on the System Drive that contains the Deployed OS needs additional components or modification!  
OEMDriversExport.ps1 - This script expects 7-Zip to be installed and expects a folder named DriverPacks on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY to copy exported drivers archived in the .7z format to!  
ScanWindowsImage64.ps1 - Cleaning up the driver store in Windows 11 breaks the Microsoft-OneCore-DirectX-Database-FOD-Package. This script expects a folder named Servicing (that contains the Microsoft-OneCore-DirectX-Database-FOD-Package) on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY, then look for the offline components! The necessary offline servicing components (Microsoft-OneCore-DirectX-Database-FOD-Package) is included in this repository inside the Servicing folder, just copy the Servicing folder included in this repository to the network share "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY!  
ScanStatex64.ps1 - This script expects a folder named ScanState (that contains the ScanState tool) on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY, then copies the appropriate ScanState tool to a Temp folder on the System Drive of the Deployed OS! The ScanState tool is included in this repository as a .7z archive, just extract to the network share "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY!
  
  
  
Again, please feel free and contribute by assisting me in improving any/all scripts contained in this repository and by adding original resources to the OEM Apps and Customizations contained in this repository!! Let’s make this repository the most comprehensive and efficient add-on for repair technicians that are refurbishing/reimaging OEM desktop and laptop PCs!
  
  
  
To recap or simplify
  
If you have a server running Windows Server (assuming your server is not the default DHCP or DNS server)  
Rename your Server to "SERVER" (without quotes)!  
Create a user account named "Network User" (without quotes) in Computer Management under Local Users and Groups > Users, set the password as "p@$$w0rd" - [lowercase p, at sign, dollar sign, dollar sign, lowercase w, zero, lowercase r, lowercase d] (without quotes), and set the following  
On 'General' tab  
Remove check mark on 'User must change password at next logon'!  
Set check mark on 'User cannot change password'!  
Set check mark on 'Password never expires'!  
On 'Member of' tab  
Remove the 'Users' group and add the 'Administrators' group and confirm by clicking on ok!  
Look at the scope/range of your DHCP router and set the scope/range to e.g., 192.168.1.101-199 or whatever suits your network environment (reserve some IP addresses for static IP addresses and for the deployment server to respond to PXE requests!  
Configure your server to use a static IP address on your current subnet (choose a static IP address within your current subnet and outside of the scope/range of your DHCP enabled router/server, e.g., 192.168.1.200!  
Add and configure the DHCP Server and WDS Server Roles (Import my DHCP configuration backup contained in this repository and edit the scope to suit your network environment)!  
  
Install the following  
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Windows PE Addon for the Windows ADK --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--  
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--  
KB4564442 for MDT --> https://support.microsoft.com/en-us/topic/windows-10-deployments-fail-with-microsoft-deployment-toolkit-on-computers-with-bios-type-firmware-70557b0b-6be3-81d2-556f-b313e29e2cb7 <--  
  
Create a new MDT deployment share in the default location (C:\DeploymentShare)!  
After creating your deployment share, copy the contents of the DeploymentShare folder (from this repository) into your deployment share folder replacing existing files!  
Download the DeploymentShare folder that contains the Boot images, Out-of-Box Drivers and Operating System images from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and extract then copy the contents of the DeploymentShare folder from my shared OneDrive folder into your deployment share folder replacing existing files!  
Update your deployment share to create/recreate boot images!  
Import boot images into Windows Deployment Services under Boot Images!  
Download my OEM Apps archives from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and place it in a folder named x64 on a network share at "\\\\SERVER\OEM" or in a folder named x64 within a folder named OEM on a USB flash drive labeled DEPLOY!  
PXE boot your client and deploy Windows!    
  
If you have a desktop PC running a Desktop Edition of Windows  
Rename your desktop PC to "SERVER" (without quotes)!  
Create a user account named "Network User" (without quotes) in Computer Management under Local Users and Groups > Users, set the password as "p@$$w0rd" - [lowercase p, at sign, dollar sign, dollar sign, lowercase w, zero, lowercase r, lowercase d] (without quotes), and set the following!  
On 'General' tab  
Remove check mark on 'User must change password at next logon'  
Set check mark on 'User cannot change password'  
Set check mark on 'Password never expires'  
On 'Member of' tab  
Remove the 'Users' group and add the 'Administrators' group and confirm by clicking on ok!  
Install and AOMEI PXE Boot Server Free (contained in the Prerequisites folder in this repository)!   

Install the following  
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Windows PE Addon for the Windows ADK --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--  
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--  
KB4564442 for MDT --> https://support.microsoft.com/en-us/topic/windows-10-deployments-fail-with-microsoft-deployment-toolkit-on-computers-with-bios-type-firmware-70557b0b-6be3-81d2-556f-b313e29e2cb7 <--  
  
Create a new MDT deployment share in the default location (C:\DeploymentShare)!  
After creating your deployment share, copy the contents of the DeploymentShare folder (from this repository) into your deployment share folder replacing existing files!  
Download the DeploymentShare folder that contains the Boot images, Out-of-Box Drivers and Operating System images from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and extract then copy the contents of the DeploymentShare folder from my shared OneDrive folder into your deployment share folder replacing existing files!  
Update your deployment share to create/recreate boot images!  
Download my OEM Apps archives from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and place it in a folder named x64 on a network share at "\\\\SERVER\OEM" or in a folder named x64 within a folder named OEM on a USB flash drive labeled DEPLOY!  
Open AOMEI PXE Boot Server Free and browse to the folder containing the boot images of your deployment share (C:\DeploymentShare\Boot) and select the appropriate boot image (x64 for 64-bit)!  
PXE boot your client and deploy Windows!  
  
  
  
To deploy Windows from Offline Media e.g., a USB flash drive, follow the steps above 'If you have a desktop PC running a Desktop Edition of Windows', then 
Format a USB flash drive as FAT32 and label the volume "Deploy" (without quotes), then set the partition as active!  
Update your Media in MDT!  
Copy the contents of your offline media (C:\Deploy\MDT\Content) to the root of your USB flash drive labeled Deploy!  
Copy the OEM folder containing OEM apps to the root of the flash drive!  
Copy the folder containing the updates to the root of your USB flash drive!  
