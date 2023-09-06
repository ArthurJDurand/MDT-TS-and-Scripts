# MDT-TS-and-Scripts  
  
  
  
## MDT Task Sequences and Custom Scripts to  
  
1) Deploy 64-bit Windows 10 Pro and 64-bit Windows 11 Pro  
2) Extract OEM customizations and drivers  
3) Install third party software
  
  
  
### Skills and experience required!  
  
The most important prerequisite is knowledge and expertise in the following areas  
Microsoft Windows Server and Desktop Editions of Microsoft Windows!  
Networking!  
Deploying Desktop Editions of Microsoft Windows!  
Windows ADK!  
MDT!  
  
  
  
## Prerequisites  
  
A Server running Windows Server OS with at least the DHCP Server and WDS Server Roles installed and configured!  
or a desktop PC running a desktop edition of Windows like Windows 10 or Windows 11!  
  
Or    
  
A desktop PC running any Desktop Edition of Windows  
  
  
  
### If you have a server running a Windows Server Operating System  
  
Rename your server's hostname to "SERVER" (without quotes)!  
Create a user account named "Network User" (without quotes) in Computer Management under Local Users and Groups > Users, set the password as "p@$$w0rd" - [lowercase p, at sign, dollar sign, dollar sign, lowercase w, zero, lowercase r, lowercase d] (without quotes), and set the following!  
On 'General' tab, remove check mark on 'User must change password at next logon'  
Set check mark on 'User cannot change password'  
Set check mark on 'Password never expires'  
On 'Member of' tab, remove the 'Users' group and add the 'Administrators' group and confirm by clicking on ok!  
Look at the scope/range of your DHCP router and set the scope/range to e.g., 192.168.1.101-199 or whatever suits your network environment (reserve some IP addresses for static IP addresses and for the deployment server to respond to PXE requests!  
Configure your server to use a static IP address on your current subnet (choose a static IP address within your current subnet and outside of the scope/range of your DHCP enabled router/server, e.g., 192.168.1.200!  
Turn off password protected sharing in Advanced Network Sharing Settings!  
Download or clone this repository  --> https://github.com/ArthurJDurand/MDT-TS-and-Scripts.git <--
Download my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and merge the contents from my OneDrive folder with this repository!  
Download and install the following  
PowerShell 7 --> https://learn.microsoft.com/en-us/shows/it-ops-talk/how-to-install-powershell-7 <--  
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Windows PE Addon for the Windows ADK --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--  
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--  
Run the self extracting archive "MDT Templates" from the Prerequisites folder contained in this repository and extract the contents to the default location specified by the self extracting archive!  
Add and configure the DHCP Server and WDS Server Roles by running the following command in PowerShell 7  
Install-WindowsFeature -ConfigurationFilePath <path_to_DeploymentConfigTemplate.xml>  
(Replace <path_to_DeploymentConfigTemplate.xml> with the path to the "DeploymentConfigTemplate.xml" file contained in this repository in "Prerequisites\for Windows Server\Configs")!  
Import my DHCP Serve config by running the following command in PowerShell 7  
Import-DhcpServer -File <path_to_DHCP Server.xml>  
(Replace <path_to_DHCP Server.xml> with the path to the "DHCP Server.xml" file contained in this repository in "Prerequisites\for Windows Server\Configs") and edit the IPv4 Server Options and DCHP scope to suit your network environment!  
Import my WDS Server config by running the following command in PowerShell 7  
Import-WdsServer -Path <path_to_WDS Server.xml> -OverwriteExisting  
(Replace <path_to_WDS Server.xml> with the path to the "WDS Server.xml" file contained in this repository in "Prerequisites\for Windows Server\Configs")!  
Import both boot images (LiteTouchPE_x64.wim and LiteTouchPE_x86.wim) contained in the "DeploymentShare\Boot" folder of your deployment share into the WDS Server!  
Open the Deployment Workbench (Microsoft Deployment Toolkit), and create a new deployment share in the default location (C:\DeploymentShare) then close the Deployment Workbench!  
Merge the contents from this repository and my shared OneDrive folder with the deployment share you created in the previous step!  
Create the folder structure "C:\Deploy\MDT" for offline media  
Share the "Shared" folder from my shared OneDrive folder so that Everyone can read and write to the shared folder (verify read and write access for "Everyone" in both sharing and security permissions)!  
PXE boot your client and deploy Windows!  
  
  
### If you have a desktop PC running a Desktop Edition of Windows  
  
Rename your desktop PC to "SERVER" (without quotes)!  
Create a user account named "Network User" (without quotes) in Computer Management under Local Users and Groups > Users, set the password as "p@$$w0rd" - [lowercase p, at sign, dollar sign, dollar sign, lowercase w, zero, lowercase r, lowercase d] (without quotes), and set the following!  
On 'General' tab, remove check mark on 'User must change password at next logon'  
Set check mark on 'User cannot change password'  
Set check mark on 'Password never expires'  
On 'Member of' tab, remove the 'Users' group and add the 'Administrators' group and confirm by clicking on ok!  
Turn off password protected sharing in Advanced Network Sharing Settings!  
Download or clone this repository  --> https://github.com/ArthurJDurand/MDT-TS-and-Scripts.git <--
Download my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <-- and merge the contents from my OneDrive folder with this repository!  
Download and install the following  
PowerShell 7 --> https://learn.microsoft.com/en-us/shows/it-ops-talk/how-to-install-powershell-7 <--  
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Windows PE Addon for the Windows ADK --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--  
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--  
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--  
Run the self extracting archive "MDT Templates" in the Prerequisites folder contained in this repository and extract the contents to the default location specified by the self extracting archive!  
Install AOMEI PXE Boot server from the "for Desktop Editions of Windows" folder within the Prerequisites folder contained in this repository!  
Open the Deployment Workbench (Microsoft Deployment Toolkit), and create a new deployment share in the default location (C:\DeploymentShare) then close the Deployment Workbench!  
Merge the contents from this repository and my shared OneDrive folder with the deployment share you created in the previous step!  
Create the folder structure "C:\Deploy\MDT" for offline media  
Open AOMEI PXE Boot and select the appropriate boot image (LiteTouchPE_x64.wim or LiteTouchPE_x86.wim contained in the "DeploymentShare\Boot" folder of your deployment share) to boot serve to PXE clients!  
Share the "Shared" folder from my shared OneDrive folder so that Everyone can read and write to the shared folder (verify read and write access for "Everyone" in both sharing and security permissions)!  
PXE boot your client and deploy Windows!  
  
  
### Offline Media  
  
Update your Media in Deployment Workbench (Microsoft Deployment Toolkit)!  
You may create an offline media set that you can copy to a USB flash drive!  
Please format a USB flash drive with the FAT32 file system and label the flash drive "DEPLOY" (without quotes), then set the partition as active!  
Copy the contents of your Media Set (Default location C:\Deploy\MDT\Content) to the root of the USB flash drive labeled DEPLOY!  
Copy the contents of the Shared folder to the root of the USB flash drive labeled "DEPLOY"!  
  
To deploy Windows from Offline Media e.g., a USB flash drive, follow the steps above 'If you have a desktop PC running a Desktop Edition of Windows', then Format a USB flash drive as FAT32 and label the volume "Deploy" (without quotes), then set the partition as active!  
Copy the contents of your offline media (C:\Deploy\MDT\Content) to the root of your USB flash drive labeled Deploy!  
Copy the OEM folder containing OEM apps to the root of the flash drive!  
Copy the folder containing the updates to the root of your USB flash drive!  
  
  

## After OS deployment  
  
create a user account on the client PC that the OS was deployed to!  
Apply updates and drivers via Windows Update (including Optional Driver updates)!  
Use bundled OEM Support/Update apps to install OEM drivers and updates!  
Use the following scripts in "C:\Scripts" to clean up the image after updates and driver installs - capture drivers to a network share or USB flash drive labeled DEPLOY (for reuse on same model) - create a provisioned package for push-button reset!  
1CleanImage.cmd - Cleans up the Windows image after Windows Updates!  
2CleanupDriverStore - Cleans up the Driver Store!  
3OEMDriversExport - Captures the Drivers, creating a 7z archve and copies the drivers to a network share ("\\\\SERVER\Shared\DriverPacks") or to a USB flash drive labeled "DEPLOY"!  
4ScanState - Creates a provisioned package for push-button reset!  
  
  
  
## For experts  
  
  
### Please edit the following files inside the Control folder in your deployment share if/as necessary  
  
Bootstrap.ini - If your deployment server is not named SERVER, and/or if the user account is not Network User, and/or the password is not p@$$w0rd - edit "DeployRoot", "UserID", "UserPassword" and "UserDomain". You can use a local or domain user account as UserID. You can use your deployment server's network name and add ".local" (without quates) as the UserDomain!  
CustomSettings.ini  
Medias.xml - If you created your own folder structure for offline media instead of "C:\Deploy\MDT" - edit "Root" to correspond with the folder structure you created for offline media!  
Settings.xml - If your deployment share is not located in the default location ("C:\DeploymentShare") and/or the network path to your deployment share is not "\\\\SERVER\DeploymentShare$" - edit "UNCPath" and "PhysicalPath" to correspond with your deployment share's network and local path. Also replace "C:\DeploymentShare" at "Boot.x86.ExtraDirectory" and "Boot.x64.ExtraDirectory" with the local path to your deployment share!  
WIN10PROX64\Unattend.xml - Edit the locales and time zone to match your locales and time zone!  
WIN11PROX64\Unattend.xml - Edit the locales and time zone to match your locales and time zone!  
  
  
### Technical Details about my deployment share  

    
#### My Windows 10 and 11 Pro images  
  
I did not add any third-party software to my images!  
I only added the optional component NETFX 3.5 and installed the en-GB optional language features!  
I installed the latest updates!  
I preinstalled Microsoft Office 365 Retail!  
I did not modify the image in any other way!  
You can download my Images from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <--
  
  
#### Custom scripts ran as part of the task sequence during OS deployment  
  
CopyOEM.wsf (in the Scripts folder in your deployment share) - Copies the contents of the "$OEM$" folder from the deployment share as part of the task sequence during OS deployment for more information see --> https://techcommunity.microsoft.com/t5/windows-blog-archive/copying-oem-files-and-folders-with-mdt-2012-update-1/ba-p/706642 <--  
The following PowerShell scripts in the Custom folder (inside the Scripts folder of your deployment share)  
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
  
  
#### "$OEM$" folder  
  
The unattend.xml of the OS being deployed expects to find and run "SetupComplete.cmd" located in "C:\Windows\Setup\Scripts"!  
The "$OEM$" folder contains everything including the "SetupComplete.cmd" file that will be copied to "C:\Windows\Setup\Scripts" during OS deployment!  
The following PowerShell scripts in "DeploymentShare\\$OEM$\\$1\Scripts" may need to be modified!  
OEMDriversExport.ps1 - This script expects 7-Zip to be installed and expects a folder named DriverPacks on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY to copy exported drivers archived in the .7z format to!  
ScanWindowsImage64.ps1 - Cleaning up the driver store in Windows 11 breaks the Microsoft-OneCore-DirectX-Database-FOD-Package. This script expects a folder named Servicing (that contains the Microsoft-OneCore-DirectX-Database-FOD-Package) on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY, then look for the offline components! The necessary offline servicing components (Microsoft-OneCore-DirectX-Database-FOD-Package) is included in this repository inside the Servicing folder, just copy the Servicing folder included in this repository to the network share "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY!  
ScanStatex64.ps1 - This script expects a folder named ScanState (that contains the ScanState tool) on a network share at "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY, then copies the appropriate ScanState tool to a Temp folder on the System Drive of the Deployed OS! The ScanState tool is included in this repository as a .7z archive, just extract to the network share "\\\\SERVER\Shared" or on the root of a USB flash drive labeled DEPLOY!  
You may modify the contents of the "$OEM$" folder as you desire!  
  
  
#### OEM Apps  
  
Copy the contents of the OEM folder (from my shared OneDrive folder) to a network share at "\\\\SERVER\OEM" or to a folder named OEM on a USB flash drive labeled DEPLOY!  
OEM gets extracted to the deployed OS as part of the task sequence during OS deployment!  
If you place OEM apps archives in a different network share, please edit DeploymentShare\Scripts\Custom\ExtractOEMAppsx64.ps1 accordingly!  
I used Dell's extensibility points as base for all OEM apps and customizations!  
I only included necessary OEM apps without additional bloatware!  
  
  
#### Local Group Policies  
  
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
If you do not wish to enforce any group policies, just delete the LGPO folder and delete the following code from the pre.ps1 PowerShell script (located at "DeploymentShare\\$OEM$\\$1\Recovery\OEM")!  
'& C:\Recovery\OEM\LGPO\LGPO.exe /g C:\Recovery\OEM\LGPO\Backup'  
  
  
### Please feel free and contribute by assisting me in improving any/all scripts contained in this repository and by adding original resources to the OEM Apps and Customizations contained in this repository!  
  
Perhaps a PowerShell script can be included to run as part of the task sequence during OS deployment that sets the target edition of Windows according to the OEM license (e.g. Home Single Language)! To activate OEM Home Single Language edition "DeploymentShare\\$OEM$\\$1\Recovery\OEM\pre.ps1" should be modified not just to activate Pro OEM, and local group policies that get applied should be limited to Pro edition!  
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
  
