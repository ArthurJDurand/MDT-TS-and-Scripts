# MDT-TS-and-Scripts
MDT Task Sequences and Custom Scripts to
1) Deploy 64-bit Windows 10 Pro and 64-bit Windows 11 Pro
2) Extract OEM customizations and drivers
3) Install third party software


Prerequisites!
For simplicity you may name your deployment server "SERVER" and create a user account named "Network User" (without quotes) with password "p@$$w0rd" (without quotes) and with administrative privileges!
Before using this repository install the latest version of the following!
Microsoft Windows Assessment and Deployment Kit for Windows 11 --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--
Windows PE Addon for the Windows ADK  --> https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install <--
Microsoft Windows Software Development Kit for Windows 11 --> https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/ <--
Microsoft Deployment Toolkit --> https://www.microsoft.com/en-us/download/details.aspx?id=54259 <--
KB4564442 for MDT --> https://support.microsoft.com/en-us/topic/windows-10-deployments-fail-with-microsoft-deployment-toolkit-on-computers-with-bios-type-firmware-70557b0b-6be3-81d2-556f-b313e29e2cb7 <--

You will need to create a new deployment share before using this repository!
For simplicity create your deployment share in the default location (C:\DeploymentShare)
After creating your deployment share, copy the contents of the DeploymentShare folder (from this repository) into your deployment share folder replacing existing files!


Please edit the following files inside the Control folder in your deployment share
Bootstrap.ini - If your deployment server is not named SERVER, and if the user account is not Network User, and the password is not p@$$w0rd - edit DeployRoot, UserID, UserPassword and UserDomain. You can use a local or domain user account as UserID. You can use your deployment server's network name and add ".local" (without quates) as the UserDomain.
CustomSettings.ini
Medias.xml - For simplicity create the folder structure :C:\Deploy\MDT", otherwise create your own folder structure for an offline media set which you can copy to a USB flash drive. If you created your own folder structure instead of "C:\Deploy\MDT" - make sure your folder structure corresponds with Root in Medias.xml.
Settings.xml - Make sure that UNCPath and PhysicalPath corresponds with your deployment share's network and local path. Replace "C:\DeploymentShare" at Boot.x86.ExtraDirectory and Boot.x64.ExtraDirectory with the local path to your deployment share if necessary.


Next you'll need to download my Windows 10 and Windows 11 lite touch images and place it inside the appropriate folder in the Operating Systems folder in your deployment share or use your own! If you choose to use your own Windows 10 and 11 images, place the appropriate install.wim files in Win10Prox64 and Win11Prox64 folders in the Operating Systems folder of your deployment share! If you did not modify your own images in Audit Mode, please remove the line containing CopyProfile from the unattend.xml located in the WIN10PROX64 and WIN11PROX64 folders in the Control folder from your deployment share!

My Windows 10 and 11 Pro images
I did not add any third party software to my images!
I only added the optional component NETFX 3.5 and installed the en-GB optional language features!
I installed the latest updates!
I preinstalled Microsoft Office 365 Retail!
I did not modify the image in any other way!
You can download my Images from my shared OneDrive folder --> https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6 <--


Custom scripts ran as part of the task sequence during OS deployment
CopyOEM.wsf (in the Scripts folder in your deployment share) - Copies the contents of the $OEM$ folder from the deployment share as part of the task sequence during OS deployment for more information see --> https://techcommunity.microsoft.com/t5/windows-blog-archive/copying-oem-files-and-folders-with-mdt-2012-update-1/ba-p/706642 <--
PowerShell scripts in the Custom folder inside the Scripts folder of your deployment share! Please edit the PowerShell scripts according to your needs.

$OEM$ folder
The unattend.xml of the OS being deployed expects to find and run SetupComplete.cmd located in C:\Windows\Setup\Scripts.
The $OEM$ folder contains everything including the SetupComplete.cmd file that will be copied to C:\Windows\Setup\Scripts during OS deployment.
You may modify the contents of the $OEM$ folder as you desire.


