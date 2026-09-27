# Setup Guide

Complete walkthrough for installing, configuring, and running the MDT-TS-and-Scripts deployment framework from scratch.

This guide covers both deployment paths:

- **Server path** — Windows Server with the DHCP and WDS roles
- **Desktop path** — Windows desktop PC with AOMEI PXE Boot

Both paths produce identical deployments. Choose the one that matches your infrastructure.

---

## Table of Contents

- [Before You Begin](#before-you-begin)
- [Requirements](#requirements)
- [Path A — Server Deployment](#path-a--server-deployment)
- [Path B — Desktop Deployment](#path-b--desktop-deployment)
- [Create and Populate the Deployment Share](#create-and-populate-the-deployment-share)
- [Configure the Deployment Share](#configure-the-deployment-share)
- [Generate Boot Images](#generate-boot-images)
- [Import Boot Images](#import-boot-images)
- [Prepare Network Shares](#prepare-network-shares)
- [First Deployment](#first-deployment)
- [Post-Deployment](#post-deployment)
- [Offline Media](#offline-media)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting Quick Reference](#troubleshooting-quick-reference)

---

## Before You Begin

### Time estimate

| Phase | First-time setup | Notes |
|---|---|---|
| Software installation | 45–90 min | ADK + WinPE Addon + MDT + SDK |
| Server/desktop role configuration | 20–45 min | DHCP/WDS or AOMEI |
| Deployment share creation | 10–15 min | MDT wizard |
| Merging repo + OneDrive content | 20–60 min | Depends on network speed |
| Configuration file edits | 15–30 min | Bootstrap.ini, CustomSettings.ini, Settings.xml |
| Boot image generation | 15–30 min | Depends on driver count |
| First test deployment | 30–60 min | PXE boot through OOBE |

Expect a full first-time setup to take **3–5 hours** including the first deployment.

### Skills assumed

- Comfortable with Windows Server or Windows desktop administration
- Understands DHCP, DNS, subnets, and SMB shares
- Familiar with WinPE, DISM, `unattend.xml`, and WIM concepts
- Has used (or is willing to learn) Microsoft Deployment Toolkit and the Windows ADK

If any of these are unfamiliar, work through Microsoft's own MDT documentation first. This guide assumes working knowledge and does not teach MDT fundamentals.

---

## Requirements

### Hardware

| Component | Minimum | Recommended |
|---|---|---|
| Deployment host CPU | 2 cores | 4+ cores |
| Deployment host RAM | 8 GB | 16 GB |
| Deployment host disk | 200 GB free | 500 GB+ free (SSD) |
| Target machine | Any x64 machine with UEFI or BIOS and PXE | Physical hardware |
| Network | Wired Ethernet, same subnet | Gigabit switch |

VMs work for the deployment host but **physical hardware is strongly recommended for target machines**, especially when validating driver injection, VMD, and WinRE behaviour.

### Software (all installations on the deployment host)

| Software | Version | Download |
|---|---|---|
| Windows ADK | Windows 11 ADK | [learn.microsoft.com/en-us/windows-hardware/get-started/adk-install](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) |
| Windows PE Addon | Matches ADK version | Same page as ADK |
| Windows SDK | Windows 11 SDK | [developer.microsoft.com/windows/downloads/windows-sdk](https://developer.microsoft.com/windows/downloads/windows-sdk/) |
| Microsoft Deployment Toolkit | 6.3.8456.1000 | [microsoft.com/en-us/download/details.aspx?id=54259](https://www.microsoft.com/en-us/download/details.aspx?id=54259) |
| PowerShell 7 | Latest | [learn.microsoft.com/en-us/shows/it-ops-talk/how-to-install-powershell-7](https://learn.microsoft.com/en-us/shows/it-ops-talk/how-to-install-powershell-7) |
| 7-Zip | Latest | [7-zip.org](https://www.7-zip.org/) — **required**, install to default path |

### Network topology (server path)

- Deployment server on a static IP outside the DHCP scope (e.g. `192.168.1.200`)
- DHCP scope configured to serve PXE clients (e.g. `192.168.1.101–199`)
- DNS resolves the server hostname (`SERVER` by default) from client machines

### Network topology (desktop path)

- Deployment workstation on a static IP or DHCP reservation
- AOMEI PXE Boot running as a service or scheduled task
- No DHCP server or WDS role required — AOMEI handles PXE responses

---

## Path A — Server Deployment

Follow this path if you have Windows Server available.

### A.1 — Rename the host

Rename the server to **`SERVER`** (all uppercase, no quotes).

```powershell
Rename-Computer -NewName "SERVER" -Restart
```

The server will reboot. Reconnect after the reboot.

> **Why `SERVER`?** The scripts and configuration files use `\\SERVER\...` paths by default. You can use a different hostname if you also update `Control\Bootstrap.ini` and `Control\Settings.xml`. See [Configure the Deployment Share](#configure-the-deployment-share).

### A.2 — Create the deployment service account

Open **Computer Management** → **Local Users and Groups** → **Users** → **New User**.

| Field | Value |
|---|---|
| User name | `Network User` |
| Full name | `Network User` |
| Description | Deployment service account |
| Password | `p@$$w0rd` (lowercase `p`, at, dollar, dollar, lowercase `w`, zero, lowercase `r`, lowercase `d`) |
| Confirm password | Same as above |

After clicking **Create**, open the account's **Properties**:

**General tab:**
- Uncheck: **User must change password at next logon**
- Check: **User cannot change password**
- Check: **Password never expires**

**Member Of tab:**
- Click **Add…**
- Type `Administrators` and confirm
- Select the **Users** group and click **Remove**
- Click **OK**

> **Security note.** `p@$$w0rd` is a known password published in this repository. It is acceptable only on isolated lab networks. For any production or internet-adjacent environment, use a strong unique password and update `Control\Bootstrap.ini` accordingly.

### A.3 — Configure a static IP address

Assign a static IP to the server on your LAN. Example for a `192.168.1.0/24` network:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.200 -PrefixLength 24 -DefaultGateway 192.168.1.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.1, 8.8.8.8
```

Replace `Ethernet` with your actual adapter alias (check with `Get-NetAdapter`).

Choose an address **outside** the DHCP scope of your router or DHCP server.

### A.4 — Install the DHCP and WDS roles

Two install options:

**Option 1 — Manual role installation:**

```powershell
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Install-WindowsFeature -Name WDS -IncludeManagementTools
```

**Option 2 — Import from the repository's config template:**

The repository includes a `DeploymentConfigTemplate.xml` under `Prerequisites\for Windows Server\Configs\`. Run:

```powershell
Install-WindowsFeature -ConfigurationFilePath "C:\path\to\DeploymentConfigTemplate.xml"
```

Replace the path with the actual location of the file after you clone the repository.

### A.5 — Authorize DHCP in Active Directory (domain-joined servers only)

If your server is domain-joined:

```powershell
Add-DhcpServerInDC -DnsName SERVER -IPAddress 192.168.1.200
```

If the server is standalone (workgroup), skip this step.

### A.6 — Configure DHCP scope

Open **DHCP Manager** (`dhcpmgmt.msc`) and create a scope:

- **Name:** `Deployment`
- **Start IP:** e.g. `192.168.1.101`
- **End IP:** e.g. `192.168.1.199`
- **Subnet mask:** `255.255.255.0` (or match your LAN)
- **Lease duration:** `1 day`
- **Router (003):** your gateway
- **DNS Servers (006):** your DNS servers

Then configure DHCP options for PXE:

- **Option 066 (Boot Server Host Name):** `192.168.1.200`
- **Option 067 (Bootfile Name):** `boot\x64\wdsnbp.com`

> If the DHCP server and WDS server are on the **same** host, do not set Option 060 (PXE Client). WDS will respond on the same port.

If you have a config file from the repository, import it:

```powershell
Import-DhcpServer -File "C:\path\to\DHCP Server.xml" -BackupPath "C:\DHCP-Backup"
```

Then open DHCP Manager and adjust the scope and options to match your network.

### A.7 — Configure WDS

Open **Windows Deployment Services** (`wdsmgmt.msc`):

1. Right-click **Servers** → **Add Server** → select the local server.
2. Right-click the server → **Configure Server**.
3. Choose **Integrated with Active Directory** (domain) or **Standalone server** (workgroup).
4. Set the **RemoteInstall** folder (default `C:\RemoteInstall`).
5. In **Server Properties** → **PXE Response** tab, choose one:
   - **Respond to all client computers (known and unknown)** — easiest for lab
   - **Respond only to known client computers** — requires pre-staging machines in AD

If you have a config file from the repository, import it:

```powershell
Import-WdsServer -Path "C:\path\to\WDS Server.xml" -OverwriteExisting
```

### A.8 — Disable password-protected sharing (optional but recommended for lab)

Control Panel → Network and Sharing Center → Advanced sharing settings → All Networks → **Turn off password protected sharing**.

Skip this on production networks — it weakens security.

### A.9 — Continue to shared steps

Skip ahead to [Create and Populate the Deployment Share](#create-and-populate-the-deployment-share).

---

## Path B — Desktop Deployment

Follow this path if you only have a Windows desktop edition (Windows 10 or 11).

### B.1 — Rename the host

Same as Path A step A.1:

```powershell
Rename-Computer -NewName "SERVER" -Restart
```

### B.2 — Create the deployment service account

Same as Path A step A.2. Full name `Network User`, password `p@$$w0rd`, member of `Administrators`, password never expires, user cannot change password.

### B.3 — Configure a static IP address (recommended)

Same as Path A step A.3. A static IP keeps the PXE boot address stable.

If your router handles DHCP and you cannot set a static IP, use a DHCP reservation instead.

### B.4 — Turn off password-protected sharing (optional, for lab)

Same as Path A step A.8.

### B.5 — Install AOMEI PXE Boot

From the repository's `Prerequisites\for Desktop Editions of Windows\` folder, run the AOMEI PXE Boot installer.

AOMEI PXE Boot serves the boot image to PXE clients over the network. You will point it at the LiteTouch boot WIM after you generate it.

### B.6 — Continue to shared steps

Skip ahead to [Create and Populate the Deployment Share](#create-and-populate-the-deployment-share).

---

## Create and Populate the Deployment Share

These steps are identical for both paths.

### 1. Install the remaining software

Install in this order:

1. **Windows ADK for Windows 11** — select at minimum the **Deployment Tools** feature
2. **Windows PE Addon for the ADK** — required to build WinPE boot images
3. **Windows SDK for Windows 11** — only the .NET and tooling features are needed
4. **Microsoft Deployment Toolkit** — default install location is `C:\Program Files\Microsoft Deployment Toolkit`
5. **PowerShell 7** — installs alongside PowerShell 5.1
6. **7-Zip** — install to the default location `C:\Program Files\7-Zip\`

### 2. Extract MDT Templates

In the repository's `Prerequisites\` folder, run the self-extracting archive `MDT Templates.exe` and extract to the default location suggested by the archive (usually `C:\Program Files\Microsoft Deployment Toolkit\Templates`).

### 3. Clone the repository

Clone to a working location, **not** to the deployment share yet:

```powershell
git clone https://github.com/ArthurJDurand/MDT-TS-and-Scripts.git C:\Source\MDT-TS-and-Scripts
```

### 4. Download the companion OneDrive folder

Open the [shared OneDrive folder](https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6) and download the entire contents. This contains:

- Windows 10 x64, Windows 10 x86, Windows 11 x64 WIM files
- OEM driver packs (`.7z` split archives)
- OEM app archives (`.7z` split archives)
- Update packages (`.cab` / `.msu`)
- Boot images (pre-built `LiteTouchPE_x64.wim`, `LiteTouchPE_x86.wim`)
- Supporting tools (`ScanState`, `Microsoft-OneCore-DirectX-Database-FOD-Package`)

Download to a temporary location, e.g. `C:\Source\OneDrive-Content`.

> **Disk space.** Expect **80–200 GB** depending on which OS images you download. Ensure the deployment host has enough free space before downloading.

### 5. Create the deployment share

Open **Deployment Workbench** (Start → Microsoft Deployment Toolkit → Deployment Workbench).

1. Right-click **Deployment Shares** → **New Deployment Share**
2. **Path:** `C:\DeploymentShare`
3. **Share name:** `DeploymentShare$`
4. **Descriptive name:** `MDT Deployment Share`
5. Accept all remaining defaults
6. Click **Finish**

Do **not** modify anything inside the share yet. Close Deployment Workbench.

### 6. Merge the repository into the deployment share

Copy the contents of `C:\Source\MDT-TS-and-Scripts` into `C:\DeploymentShare`, merging folders. When Windows asks to merge or replace, choose **Merge** for folders and **Replace** for individual files.

```powershell
robocopy "C:\Source\MDT-TS-and-Scripts" "C:\DeploymentShare" /E /COPY:DAT /R:2 /W:5
```

### 7. Merge the OneDrive content into the deployment share

Copy the contents of `C:\Source\OneDrive-Content` into `C:\DeploymentShare`, again merging.

```powershell
robocopy "C:\Source\OneDrive-Content" "C:\DeploymentShare" /E /COPY:DAT /R:2 /W:5
```

After this merge, your `C:\DeploymentShare` should contain the full set of files needed for a deployment: `Control\`, `Scripts\`, `Operating Systems\`, `Out-of-box Drivers\`, `Boot\`, `Task Sequences\`, `$OEM$\`, `Applications\`, `Packages\`, and the various `.xml` metadata files.

### 8. Re-open Deployment Workbench

Close and reopen the Deployment Workbench so it reloads the deployment share contents. You should see:

- **Operating Systems** — three entries (Win10 Pro x64, Win10 Pro x86, Win11 Pro x64)
- **Task Sequences** — three entries (`WIN10PROX64`, `WIN10PROX86`, `WIN11PROX64`)
- **Applications** — empty (add your own)
- **Packages** — empty
- **Out-of-box Drivers** — populated with the driver entries from `Drivers.xml`

---

## Configure the Deployment Share

Open the `Control\` folder inside your deployment share and edit the following files.

### 1. `Bootstrap.ini`

This file is used by WinPE **before** the deployment share is mounted. It stores the UNC path to the share and the credentials to access it.

Default contents:

```ini
[Settings]
Priority=Default

[Default]
DeployRoot=\\SERVER\DeploymentShare$
SkipBDDWelcome=NO
KeybordLocale=en-US

UserID=Network User
UserPassword=p@$$w0rd
UserDomain=server.local
```

**What to edit:**

| Setting | Change if… |
|---|---|
| `DeployRoot` | Your server hostname is not `SERVER` or your share name is not `DeploymentShare$` |
| `UserID` | You created a deployment account with a different name |
| `UserPassword` | You chose a different password |
| `UserDomain` | Your server is domain-joined and you want to use a domain account |
| `KeybordLocale` | (sic) You want a non-US keyboard layout. Note: this key is **misspelled** in the default config; MDT expects `KeyboardLocale` |

**Security reminder.** `Bootstrap.ini` stores credentials in **plaintext**. Never commit a real `Bootstrap.ini` to a public repository. Use a least-privilege deployment account and restrict share permissions.

### 2. `CustomSettings.ini`

This file controls the zero-touch behaviour of the deployment (which wizards to skip, computer naming, domain join, etc.).

Default contents control:

- `SkipTaskSequence=NO` — user picks the OS at boot
- `DeploymentType=NEWCOMPUTER`
- `SkipApplications=NO` — user picks applications
- `SkipDomainMembership=YES` — no domain join
- `SkipComputerName=YES` — auto-generated name
- `FinishAction=SHUTDOWN` — shuts down after deployment

**Common edits:**

| Goal | Change |
|---|---|
| Skip the task sequence picker | `SkipTaskSequence=YES` and set `TaskSequenceID=WIN11PROX64` |
| Force a computer name pattern | Add `OSDComputerName=PC-%SerialNumber%` under `[Default]` |
| Skip the applications picker | `SkipApplications=YES` |
| Join a domain | `SkipDomainMembership=NO`, `JoinDomain=yourdomain.local`, and set domain join credentials |
| Reboot instead of shutdown | `FinishAction=REBOOT` |

### 3. `Settings.xml`

This file controls the deployment share itself (UNC path, physical path, boot image settings, WinPE feature packs).

Default contents assume:

- Physical path: `D:\DeploymentShare`
- UNC path: `\\SERVER\DeploymentShare$`
- Boot.x64.ExtraDirectory: `D:\DeploymentShare\Boot\Addon\x64`
- Boot.x86.ExtraDirectory: `D:\DeploymentShare\Boot\Addon\x86`

**If your deployment share is not at `D:\DeploymentShare`**, update:

- `PhysicalPath`
- `Boot.x86.ExtraDirectory`
- `Boot.x64.ExtraDirectory`

**If your server hostname is not `SERVER`**, update `UNCPath`.

### 4. `Medias.xml`

This file controls offline media generation.

Default root: `D:\Deploy\MDT`

If you use a different folder for offline media, update the `<Root>` element. See [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md) for the full offline media workflow.

### 5. `Task Sequences\WIN10PROX64\Unattend.xml` and `Task Sequences\WIN11PROX64\Unattend.xml`

Edit the following in each file to match your locale and time zone:

```xml
<component name="Microsoft-Windows-International-Core-WinPE" ...>
  <InputLocale>en-US</InputLocale>
  <SystemLocale>en-US</SystemLocale>
  <UILanguage>en-US</UILanguage>
  <UserLocale>en-ZA</UserLocale>
</component>
```

And the time zone under `specialize` and `oobeSystem`:

```xml
<TimeZone>South Africa Standard Time</TimeZone>
```

Replace with your own locale and time zone identifiers. A full list of time zone IDs is available via `Get-TimeZone -ListAvailable` on any Windows machine.

---

## Generate Boot Images

Boot images are what PXE clients download. They contain WinPE plus the drivers and scripts needed to start the deployment.

### 1. Enable the right WinPE feature packs

The boot image must include the feature packs the scripts depend on. The repository's `Settings.xml` already lists the correct set:

- `winpe-dismcmdlets`
- `winpe-dot3svc`
- `winpe-enhancedstorage`
- `winpe-fonts-legacy`
- `winpe-fontsupport-winre`
- `winpe-mdac`
- `winpe-netfx`
- `winpe-platformid`
- `winpe-powershell`
- `winpe-rndis`
- `winpe-securebootcmdlets`
- `winpe-storagewmi`
- `dart8`

Do **not** remove `winpe-storagewmi` — `SetTargetOSDisk.ps1` depends on it.

### 2. Configure driver injection into the boot image

Under **Deployment Share** → **Properties** → **Windows PE** tab:

- **Platform x64** → **Drivers and Patches** tab → set **Selection Profile** to `All Drivers`
- **Platform x86** → same setting (only if you plan to deploy to 32-bit hardware)

### 3. Update the deployment share

Right-click the deployment share in Deployment Workbench and select **Update Deployment Share**.

Choose:

- **Completely regenerate the boot images** — on the first run
- **Optimize the boot image updating process** — on subsequent runs

This step takes **15–30 minutes**. It builds:

- `C:\DeploymentShare\Boot\LiteTouchPE_x64.wim`
- `C:\DeploymentShare\Boot\LiteTouchPE_x86.wim`

### 4. Verify

Confirm both files exist:

```powershell
Get-ChildItem "C:\DeploymentShare\Boot\*.wim"
```

---

## Import Boot Images

### Path A — WDS

1. Open **Windows Deployment Services** (`wdsmgmt.msc`)
2. Expand **Servers** → `SERVER` → **Boot Images**
3. Right-click **Boot Images** → **Add Boot Image**
4. Browse to `C:\DeploymentShare\Boot\LiteTouchPE_x64.wim`
5. Give it a descriptive name like `LiteTouch x64`
6. Repeat for `LiteTouchPE_x86.wim` if you plan to deploy to 32-bit hardware

### Path B — AOMEI PXE Boot

1. Open **AOMEI PXE Boot**
2. Select **Boot from custom image**
3. Browse to `C:\DeploymentShare\Boot\LiteTouchPE_x64.wim`
4. Start the PXE service

---

## Prepare Network Shares

The scripts read content from network shares at deployment time. Create and populate them before the first deployment.

### `\\SERVER\Shared`

Contains updates, driver packs, WinRE images, servicing components, and ScanState.

```
\\SERVER\Shared\
├── Updates\
│   ├── Win10\
│   │   ├── x64\
│   │   └── x86\
│   └── Win11\
├── DriverPacks\
│   └── *.7z
├── WindowsRE\
│   ├── Win10\
│   │   ├── x64\winre.wim
│   │   └── x86\winre.wim
│   └── Win11\
│       └── x64\winre.wim
├── Servicing\
│   └── Microsoft-OneCore-DirectX-Database-FOD-Package\
└── ScanState\
    └── (extracted ScanState tool)
```

Share permissions: **Everyone — Read**.

### `\\SERVER\OEM`

Contains OEM app archives.

```
\\SERVER\OEM\
├── x64\
│   ├── Dell.7z
│   ├── HP.7z
│   ├── Lenovo.7z
│   ├── Acer.7z
│   ├── ASUS.7z
│   ├── MSI.7z
│   └── ... (one .7z per supported vendor)
└── x86\
    └── ... (x86 archives, if any)
```

Share permissions: **Everyone — Read**.

### Share permissions on `\\SERVER\DeploymentShare$`

MDT creates this share when you create the deployment share. Confirm the deployment service account (`Network User`) has **Read** access at minimum. The account does **not** need Write access during deployment — writes happen on the target machine, not the share.

---

## First Deployment

### 1. Verify PXE response

On a target machine:

1. Enter BIOS/UEFI setup
2. Enable PXE boot / network boot
3. Ensure Secure Boot is either disabled or configured for your environment
4. Set network boot to the highest boot priority
5. Save and reboot

The machine should boot into **LiteTouch WinPE** within 30–60 seconds.

### 2. Walk through the wizard

If `CustomSettings.ini` still has `SkipTaskSequence=NO`, you will see the LiteTouch wizard:

1. **Welcome** — click **Next**
2. **Credentials** — leave blank (WinPE uses `Bootstrap.ini`)
3. **Task Sequence** — choose `Windows 11 Pro (64-bit)` or your preferred OS
4. **Computer Details** — set computer name if `SkipComputerName=NO`
5. **Applications** — select apps to install (if `SkipApplications=NO`)
6. **Summary** — click **Begin**

Deployment proceeds automatically from here. Expect 20–60 minutes for a full deployment.

### 3. What happens during deployment

Refer to the Deployment Flow diagram in the [README](../README.md#deployment-flow). The task sequence runs these phases in order:

- Initialization — gathers local rules
- Validation — checks hardware and BIOS/UEFI mode
- State Capture — captures user state if applicable
- Preinstall — wipes disks, partitions, creates recovery partitions
- Install — applies OS image, injects updates, extracts and applies OEM drivers
- Postinstall — configures WinRE, cleans up MDT scripts
- State Restore — installs apps, applies LGPO, restores user state
- OOBE — runs `SetupComplete.cmd` → `pre.ps1` → `Customizations.ps1` → `pbr.ps1`

### 4. Verify the logs

After deployment, on the target machine:

| Log location | Contents |
|---|---|
| `C:\MININT\SMSOSD\OSDLOGS\` | MDT deployment logs (may be deleted by cleanup) |
| `C:\ProgramData\OEM\Logs\` | OEM setup logs (`pre_*.log`, `SetupComplete.log`) |
| `C:\Windows\Temp\DeploymentLogs\` | Post-deployment summaries |

Look for `[ERROR]` or `[FATAL]` entries.

---

## Post-Deployment

Once the OS is deployed and OOBE completes, log into the new machine with a local admin account and finalize the image.

### 1. Apply Windows Updates

Settings → Windows Update → **Check for updates**. Include **Optional updates** → **Driver updates**.

Reboot as needed until no updates remain.

### 2. Apply OEM updates

Use the OEM Support Assistant (Dell Command Update, HP Support Assistant, Lenovo System Update, etc.) to install OEM-specific drivers and BIOS updates.

### 3. Run the cleanup scripts

Scripts are in `C:\Scripts\` on the deployed machine:

| Script | Purpose |
|---|---|
| `1CleanImage.cmd` | Clean up the Windows image after Windows Updates |
| `2CleanupDriverStore` | Clean the driver store |
| `3OEMDriversExport` | Capture and archive drivers as `.7z`, copy to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB |
| `4ScanState` | Create a push-button reset provisioned package |

Run them in numerical order.

### 4. Optional — Export drivers back to the deployment share

If `3OEMDriversExport` produced a `.7z` file, copy it to `\\SERVER\Shared\DriverPacks` so the same model can be deployed faster next time.

---

## Offline Media

For deployments without a server or network, you can build a bootable USB flash drive.

See [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md) for the full walkthrough. Summary:

1. Copy the `MDT` folder to `C:\Deploy\MDT`
2. Update the media set in Deployment Workbench
3. Format a USB flash drive as **FAT32**, label **`DEPLOY`**, mark active
4. Copy `C:\Deploy\MDT\Content\*` to the USB root
5. Copy the `Shared` folder to the USB root

---

## Verification Checklist

Before declaring the setup complete, verify each item.

### Deployment host

- [ ] Hostname is `SERVER`
- [ ] Deployment account `Network User` exists and is a member of `Administrators`
- [ ] Account password is set, user cannot change password, password never expires
- [ ] Static IP is configured outside the DHCP scope
- [ ] Password-protected sharing is disabled (lab only)
- [ ] Windows ADK, WinPE Addon, Windows SDK, MDT, PowerShell 7, and 7-Zip are installed
- [ ] MDT Templates self-extracting archive has been extracted
- [ ] Deployment share exists at `C:\DeploymentShare` and is shared as `DeploymentShare$`
- [ ] Repository contents have been merged into the deployment share
- [ ] OneDrive content has been merged into the deployment share
- [ ] `Control\Bootstrap.ini` has been edited with correct paths and credentials
- [ ] `Control\CustomSettings.ini` has been edited to match your naming and join policy
- [ ] `Control\Settings.xml` has been edited with the correct paths
- [ ] `Task Sequences\WIN1?PROX??\Unattend.xml` have been edited with the correct locale and time zone
- [ ] Boot images have been regenerated
- [ ] Boot images have been imported into WDS (or AOMEI PXE Boot)
- [ ] `\\SERVER\Shared` exists and contains `Updates`, `DriverPacks`, `WindowsRE`, `Servicing`, `ScanState`
- [ ] `\\SERVER\OEM` exists and contains `x64` and `x86` subfolders with `.7z` archives

### Target machine (first deployment)

- [ ] PXE boots successfully into LiteTouch WinPE
- [ ] Task sequence picker appears (or is skipped if configured)
- [ ] Windows OS installs without errors
- [ ] OEM drivers are applied during install
- [ ] Updates are injected into the offline image
- [ ] Recovery partition is created
- [ ] OOBE completes without errors
- [ ] `C:\ProgramData\OEM\Logs\` contains logs with no `[FATAL]` entries
- [ ] Windows is activated (if OEM firmware key is present)
- [ ] Office is installed and activated (if Office installer is present)
- [ ] LGPO policies are applied
- [ ] Desktop icons and regional settings are correct

---

## Troubleshooting Quick Reference

Full troubleshooting guide: [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md).

| Symptom | Likely Cause | First Thing to Check |
|---|---|---|
| PXE client hangs at "Contacting DHCP" | DHCP scope or Option 066/067 misconfigured | DHCP Manager options |
| PXE client downloads boot image then fails | Boot image incomplete or WDS not authorized | WDS event log |
| LiteTouch WinPE boots but no task sequence picker | `SkipTaskSequence=YES` in `CustomSettings.ini` | `Control\CustomSettings.ini` |
| Deployment fails at "Load WinPE Drivers" | VMD driver missing for the target CPU | `X:\MININT\SMSOSD\OSDLOGS\BDD.log` |
| Deployment fails at "Format and Partition Disk" | Wrong UEFI/BIOS detection, or disk in use | `X:\MININT\SMSOSD\OSDLOGS\ZTIDiskpart.log` |
| Deployment fails at "Install Operating System" | WIM missing or index wrong | `OperatingSystems.xml`, WIM path |
| Deployment completes but no drivers | OEM driver pack not found for the model | `C:\ProgramData\OEM\Logs\pre_*.log`, search for "No driver folder found" |
| Windows not activated | OEM firmware key missing or mismatched edition | `slmgr /dlv` on the target machine |
| Office not activated | Office app was running during Ohook gate | `C:\ProgramData\OEM\Logs\pre_*.log`, search for "Office activation deferred" |
| `Apps.ps1` or `Drivers.ps1` fails | Companion repo or Gist unavailable, or hash mismatch | Script's own log under `C:\ProgramData\OEM\Logs\` |
| 7-Zip not found | 7-Zip not installed at default path | `Test-Path "C:\Program Files\7-Zip\7z.exe"` |

### Where to get help

- **GitHub Discussions** — [github.com/ArthurJDurand/MDT-TS-and-Scripts/discussions](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/discussions)
- **GitHub Issues** — [github.com/ArthurJDurand/MDT-TS-and-Scripts/issues](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/issues)

When asking for help, include:

- Deployment host OS and role (server or desktop)
- Target machine make, model, CPU generation, BIOS version
- Which task sequence was used
- The exact error message and the relevant log excerpt
- Whether the failure is reproducible
