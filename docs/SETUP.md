# Setup Guide

Complete walkthrough for installing, configuring, and deploying with the MDT Zero-Touch Deployment share. Covers both deployment paths — Windows Server with DHCP + WDS, and a Windows desktop with AOMEI PXE Boot.

---

## Table of Contents

- [Before You Begin](#before-you-begin)
- [Requirements](#requirements)
- [Path A — Server Deployment](#path-a--server-deployment)
- [Path B — Desktop Deployment](#path-b--desktop-deployment)
- [Prepare the Deployment Host](#prepare-the-deployment-host)
- [Create the Deployment Share](#create-the-deployment-share)
- [Merge the Repository](#merge-the-repository)
- [Configure the Deployment Share](#configure-the-deployment-share)
- [Prepare Network Shares](#prepare-network-shares)
- [Generate Boot Images](#generate-boot-images)
- [Import Boot Images](#import-boot-images)
- [First Deployment](#first-deployment)
- [Post-Deployment](#post-deployment)
- [Offline Media](#offline-media)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting Quick Reference](#troubleshooting-quick-reference)

---

## Before You Begin

### Time estimate

| Phase | First-time setup |
|---|---|
| Software installation | 45–90 min |
| Prerequisite fixes | 5–15 min |
| Role configuration (server or desktop) | 20–45 min |
| Deployment share creation | 10–15 min |
| Merge repository into deployment share | 5–15 min |
| Configuration file edits | 15–30 min |
| Network share preparation | 20–60 min |
| Boot image generation | 15–30 min |
| First test deployment | 30–60 min |

Expect a full first-time setup to take **3–5 hours** including a first deployment.

### Skills assumed

- Windows Server or Windows desktop administration
- Networking fundamentals (DHCP, DNS, SMB, subnetting)
- Familiarity with WinPE, DISM, `unattend.xml`, and WIM concepts
- Working knowledge of MDT and the Windows ADK

If any of these are unfamiliar, work through Microsoft's own MDT documentation first. This guide assumes working knowledge and does not teach MDT fundamentals.

### Before you start, get a Windows image

This project requires a Windows `install.wim` (or an ISO containing one) to import into MDT. You have two options:

- **Build your own** with UUPDump and audit mode — see the companion repository [MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) and [docs/WINDOWS-MEDIA.md](WINDOWS-MEDIA.md)
- **Use an existing image** you have on hand (Microsoft ISO, VLSC, or a pre-built image from your organization)

You also need OEM payload archives (`Dell.7z`, `HP.7z`, and so on) for the manufacturers you intend to support. These are built by the companion repository [MDT-OEM-Extensibility](https://github.com/ArthurJDurand/MDT-OEM-Extensibility).

Have the OS image and OEM archives ready before you begin the deployment share steps.

---

## Requirements

### Hardware

| Component | Minimum | Recommended |
|---|---|---|
| Deployment host CPU | 2 cores | 4+ cores |
| Deployment host RAM | 8 GB | 16 GB |
| Deployment host disk | 200 GB free | 500 GB+ on SSD |
| Target machine | Any x64 machine with UEFI or BIOS and PXE (or USB boot) | Physical hardware |
| Network | Wired Ethernet, same subnet | Gigabit switch |

VMs are fine for the deployment host. Physical hardware is strongly recommended for target machines when validating driver injection, VMD, or WinRE.

### Software on the deployment host

Install in this order:

1. **Windows ADK for Windows 11** — select at minimum the Deployment Tools feature
2. **Windows PE Addon for the ADK** — required to build WinPE boot images
3. **Windows SDK for Windows 11** — only the .NET and tooling features are needed
4. **Microsoft Deployment Toolkit** — default install location is `C:\Program Files\Microsoft Deployment Toolkit`
5. **PowerShell 7** — installs alongside PowerShell 5.1
6. **7-Zip** — install to the default location `C:\Program Files\7-Zip\`

Download links are in the [README](../README.md).

### Prerequisite fixes

The repository ships `Prerequisites\All MDT Fixes 2025.exe`. This is a self-extracting archive containing:

- ADK and WinPE Addon fixes required for modern Windows builds
- MDT template patches
- The fix for KB4564442 (server-side deployment reliability)
- The fix for the HTA Script Error on Windows Server

**Run this before touching the deployment share.** Its patches are required for modern Windows builds and for reliable WDS-based deployment.

```powershell
& "C:\path\to\MDT-Zero-Touch-Deployment\Prerequisites\All MDT Fixes 2025.exe"
```

Extract to the default location offered by the archive. It typically targets `C:\Program Files\Microsoft Deployment Toolkit`.

### Network topology (server path)

- Deployment server on a static IP outside the DHCP scope (e.g. `192.168.1.200`)
- DHCP scope serving PXE clients (e.g. `192.168.1.101–199`)
- DNS resolves the server hostname (`SERVER` by default) from client machines

### Network topology (desktop path)

- Deployment workstation on a static IP or DHCP reservation
- AOMEI PXE Boot running as a service or scheduled task
- No DHCP server or WDS role required — AOMEI handles PXE responses

---

## Path A — Server Deployment

Follow this path if you have Windows Server available.

### A.1 — Rename the host

Rename the server to `SERVER` (all uppercase, no quotes):

```powershell
Rename-Computer -NewName "SERVER" -Restart
```

Reconnect after the reboot.

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
- Uncheck **User must change password at next logon**
- Check **User cannot change password**
- Check **Password never expires**

**Member Of tab:**
- Click **Add…**, type `Administrators`, confirm
- Select the `Users` group and click **Remove**
- Click **OK**

> **Security note.** `p@$$w0rd` is a known password published in this repository. It is acceptable only on isolated lab networks. For any production or internet-adjacent environment, use a strong unique password and update `Control\Bootstrap.ini` accordingly.

### A.3 — Configure a static IP address

Assign a static IP on your LAN. Example for a `192.168.1.0/24` network:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.200 -PrefixLength 24 -DefaultGateway 192.168.1.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.1, 8.8.8.8
```

Replace `Ethernet` with your actual adapter alias (check with `Get-NetAdapter`). Choose an address outside the DHCP scope.

### A.4 — Install the DHCP and WDS roles

Two options:

**Manual:**

```powershell
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Install-WindowsFeature -Name WDS -IncludeManagementTools
```

**From the repository template:**

The repository ships `Prerequisites\for Windows Server\Configs\DeploymentConfigTemplate.xml`. Run:

```powershell
Install-WindowsFeature -ConfigurationFilePath "C:\path\to\DeploymentConfigTemplate.xml"
```

Replace the path with the actual location.

### A.5 — Authorize DHCP in Active Directory (domain-joined only)

```powershell
Add-DhcpServerInDC -DnsName SERVER -IPAddress 192.168.1.200
```

Skip this on workgroup servers.

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

Do **not** set Option 060 (PXE Client) when DHCP and WDS are on the same host. WDS responds on the same port.

Optionally import the repository's DHCP config:

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
5. In **Server Properties** → **PXE Response** tab, choose:
   - **Respond to all client computers (known and unknown)** — easiest for lab
   - **Respond only to known client computers** — requires pre-staging

Optionally import the repository's WDS config:

```powershell
Import-WdsServer -Path "C:\path\to\WDS Server.xml" -OverwriteExisting
```

### A.8 — Continue to shared steps

Skip ahead to [Prepare the Deployment Host](#prepare-the-deployment-host).

---

## Path B — Desktop Deployment

Follow this path if you only have a Windows desktop edition.

### B.1 — Rename the host

Same as Path A step A.1:

```powershell
Rename-Computer -NewName "SERVER" -Restart
```

### B.2 — Create the deployment service account

Same as Path A step A.2.

### B.3 — Configure a static IP address (recommended)

Same as Path A step A.3, or use a DHCP reservation.

### B.4 — Install AOMEI PXE Boot

From `Prerequisites\for Desktop Editions of Windows\AOMEI PXE Boot Free 1.5\`, run `PXEBoot.exe`.

AOMEI PXE Boot serves the boot image to PXE clients over the network. You will point it at the LiteTouch boot WIM after generating it.

### B.5 — Continue to shared steps

Skip ahead to [Prepare the Deployment Host](#prepare-the-deployment-host).

---

## Prepare the Deployment Host

These steps are identical for both paths.

### 1. Run the MDT Fixes bundle

In the repository's `Prerequisites\` folder, run `All MDT Fixes 2025.exe` and extract to the default location (usually `C:\Program Files\Microsoft Deployment Toolkit`). This applies ADK fixes, WinPE Addon updates, and MDT template patches that modern Windows builds require.

Verify the MDT installation is intact:

```powershell
Test-Path "C:\Program Files\Microsoft Deployment Toolkit\Bin\Microsoft.BDD.PSSnapIn.dll"
```

### 2. Install the remaining software

If not already done, install:

- Windows ADK for Windows 11
- Windows PE Addon
- Windows SDK
- Microsoft Deployment Toolkit
- PowerShell 7
- 7-Zip

### 3. Clone the repository

Clone to a working location, **not** into your deployment share yet:

```powershell
git clone https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment.git C:\Source\MDT-Zero-Touch-Deployment
```

### 4. Prepare your Windows image

Have your Windows `install.wim` ready. If you need to build one, see the companion repository [MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) and [docs/WINDOWS-MEDIA.md](WINDOWS-MEDIA.md).

### 5. Prepare your OEM archives

Have your OEM payload archives ready. These are built by the companion repository [MDT-OEM-Extensibility](https://github.com/ArthurJDurand/MDT-OEM-Extensibility). You will place them on the network shares in [Prepare Network Shares](#prepare-network-shares).

---

## Create the Deployment Share

1. Open **Deployment Workbench** (Start → Microsoft Deployment Toolkit → Deployment Workbench).
2. Right-click **Deployment Shares** → **New Deployment Share**.
3. **Path:** `C:\DeploymentShare`
4. **Share name:** `DeploymentShare$`
5. **Descriptive name:** `MDT Deployment Share`
6. Accept all remaining defaults.
7. Click **Finish**.

Do **not** modify anything inside the share yet. Close Deployment Workbench.

---

## Merge the Repository

Copy the contents of `C:\Source\MDT-Zero-Touch-Deployment\DeploymentShare` into `C:\DeploymentShare`, merging folders:

```powershell
robocopy "C:\Source\MDT-Zero-Touch-Deployment\DeploymentShare" "C:\DeploymentShare" /E /COPY:DAT /R:2 /W:5
```

When Windows asks to merge or replace, choose **Merge** for folders and **Replace** for individual files.

After this, `C:\DeploymentShare` contains:

- `Boot\Addon\x64\` and `Boot\Addon\x86\` — bundled 7-Zip for both boot images
- `Control\` — configuration files and the three task sequence folders (`WIN10PROX64`, `WIN10PROX86`, `WIN11PROX64`)
- `Scripts\` and `Scripts\Custom\` — MDT bootstrap scripts and the task sequence scripts
- `Templates\` — stock MDT unattend templates
- `Tools\x64\` and `Tools\x86\` — BGInfo and the MDT utility library
- `x64\$OEM$\` — x64 OEM content, Apps framework, activation, layout
- `x86\$OEM$\` — x86 OEM content
- Plus the standard MDT folders created by the wizard

### Re-open Deployment Workbench

Close and reopen the Workbench so it reloads the share contents. You should see:

- **Operating Systems** — empty (you will import your WIM)
- **Task Sequences** — `WIN10PROX64`, `WIN10PROX86`, `WIN11PROX64`
- **Applications** — empty
- **Packages** — empty
- **Out-of-box Drivers** — empty

### Import your Windows image

1. In Deployment Workbench, expand your deployment share.
2. Right-click **Operating Systems** → **Import Operating System**.
3. Choose **Full set of source files** (if importing from an ISO) or **Custom image file** (if importing a pre-built WIM).
4. Browse to your Windows source (ISO mount or extracted folder) or WIM.
5. Name the OS entry to match the expected names:
   - `Windows 10 Pro (64-bit)`
   - `Windows 10 Pro (32-bit)`
   - `Windows 11 Pro (64-bit)`
6. Finish the wizard.

Then open each task sequence under **Task Sequences** and point it at the correct OS entry. The task sequences shipped in this repo assume OS names that match the default naming; if you named yours differently, edit the `Install Operating System` step in each task sequence.

---

## Configure the Deployment Share

Open the `Control\` folder inside your deployment share and edit the following files.

### 1. `Bootstrap.ini`

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
| `DeployRoot` | Your server hostname is not `SERVER`, or your share name is not `DeploymentShare$` |
| `UserID` | You created a deployment account with a different name |
| `UserPassword` | You chose a different password |
| `UserDomain` | Your server is domain-joined and you want to use a domain account |
| `KeybordLocale` | You want a non-US keyboard layout. **Note: this key is misspelled** in the default config; MDT expects `KeyboardLocale` |

**Security reminder.** `Bootstrap.ini` stores credentials in plaintext. Never commit a real `Bootstrap.ini` to a public repository. Use a least-privilege deployment account and restrict share permissions.

### 2. `CustomSettings.ini`

Controls zero-touch behavior. Defaults:

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

Controls the deployment share itself.

Default contents assume:

- Physical path: `C:\DeploymentShare`
- UNC path: `\\SERVER\DeploymentShare$`
- Boot.x64.ExtraDirectory: `C:\DeploymentShare\Boot\Addon\x64`
- Boot.x86.ExtraDirectory: `C:\DeploymentShare\Boot\Addon\x86`

**Update these to match your environment:**

- `PhysicalPath` — your share's local path
- `UNCPath` — your server's UNC path
- `Boot.x86.ExtraDirectory` and `Boot.x64.ExtraDirectory` — your local share path plus `\Boot\Addon\x86` (or `x64`)

The `Boot.x64.ExtraDirectory` and `Boot.x86.ExtraDirectory` paths are critical. The repository ships 7-Zip at `Boot\Addon\x64\Program Files\7-Zip\` and `Boot\Addon\x86\Program Files\7-Zip\`, which are copied into the WinPE boot images so the boot images can extract `.7z` archives during deployment.

### 4. `Medias.xml`

Controls offline media generation. Default root: `C:\Deploy\MDT`. If you use a different folder, update the `<Root>` element.

See [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md) for the full offline media workflow.

### 5. Task Sequence unattend files

The task sequences live under `Control\WIN10PROX64\`, `Control\WIN10PROX86\`, and `Control\WIN11PROX64\`, each with a `ts.xml` (the sequence definition) and an `Unattend.xml` (the OS answer file).

Edit the following in each file to match your locale and time zone:

- `Control\WIN10PROX64\Unattend.xml`
- `Control\WIN10PROX86\Unattend.xml`
- `Control\WIN11PROX64\Unattend.xml`

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

Replace with your own locale and time zone. A full list of time zone IDs is available via `Get-TimeZone -ListAvailable` on any Windows machine.

### 6. OEM-specific configuration

Edit the OEM files at `x64\$OEM$\$1\Recovery\OEM\`:

- `pre.ps1` — any deployment-specific settings, including the hardcoded AnyDesk password
- `Activation\HWID_Activation.cmd` — Windows activation fallback (usually no changes needed)
- `LGPO\Backup\` — replace with your own group policy backup if desired

The framework files under `Apps\` are covered in [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md).

---

## Prepare Network Shares

Create and populate the network shares the scripts expect.

### `\\SERVER\Shared`

Contains updates, driver packs, WinRE images, servicing components, and ScanState.

```
\\SERVER\Shared\
├── OEM\
│   ├── x64\
│   │   ├── Acer.7z
│   │   ├── ASUS.7z
│   │   ├── Dell.7z
│   │   ├── Dynabook.7z
│   │   ├── Gigabyte.7z
│   │   ├── HP.7z
│   │   ├── Huawei.7z
│   │   ├── Lenovo.7z
│   │   ├── Microsoft.7z
│   │   ├── MSI.7z
│   │   └── Proline.7z
│   └── x86\
│       └── ... (x86 archives, if you support 32-bit hardware)
├── DriverPacks\
│   ├── Dell Latitude 5430 12th Gen Intel.7z
│   ├── HP EliteBook 840 G9.7z
│   └── ... (one .7z per supported model)
├── Updates\
│   ├── Win10\
│   │   ├── x64\
│   │   └── x86\
│   └── Win11\
├── WindowsRE\
│   ├── Win10\
│   │   ├── x64\winre.wim
│   │   └── x86\winre.wim
│   └── Win11\
│       └── x64\winre.wim
├── Servicing\
│   └── Microsoft-OneCore-DirectX-Database-FOD-Package\
├── ScanState\
│   ├── amd64\
│   └── x86\
└── Drivers\
    └── WinPE\
        └── Storage\
            └── Intel\
                └── x64\
                    ├── 19.5.8.1059.2\
                    └── 20.2.6.1025.3\
```

Share permissions: `Network User` — Read.

### `\\SERVER\Shared\OEM`

The OEM app archives live at `\\SERVER\Shared\OEM\` in the structure shown above. The `ExtractOEMApps*.ps1` scripts read from this folder.

Build these archives with the companion repository [MDT-OEM-Extensibility](https://github.com/ArthurJDurand/MDT-OEM-Extensibility). See [docs/OEM.md](OEM.md) for the archive naming conventions, `.7z` splitting, and how the scripts select the right archive per vendor.

---

## Generate Boot Images

Boot images are what PXE clients download. They contain WinPE plus the drivers and scripts needed to start the deployment.

### 1. Verify the boot image feature packs

The repository's `Control\Settings.xml` already lists the correct WinPE feature packs. The critical ones are:

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

### 2. Verify the boot add-on directories

Confirm that both bundled 7-Zip installations exist:

```powershell
Test-Path "C:\DeploymentShare\Boot\Addon\x64\Program Files\7-Zip\7z.exe"
Test-Path "C:\DeploymentShare\Boot\Addon\x86\Program Files\7-Zip\7z.exe"
```

Both should return `True`. These are what get injected into the boot images so the task sequence can extract `.7z` archives.

If either folder is empty, re-copy from `C:\Source\MDT-Zero-Touch-Deployment\DeploymentShare\Boot\Addon\`.

### 3. Configure driver injection into the boot image

Under **Deployment Share** → **Properties** → **Windows PE** tab:

- **Platform x64** → **Drivers and Patches** tab → set **Selection Profile** to `All Drivers`
- **Platform x86** → same setting (only if you plan to deploy to 32-bit hardware)

### 4. Update the deployment share

Right-click the deployment share in Deployment Workbench and select **Update Deployment Share**.

Choose:

- **Completely regenerate the boot images** — on the first run
- **Optimize the boot image updating process** — on subsequent runs

This step takes **15–30 minutes**. It builds:

- `C:\DeploymentShare\Boot\LiteTouchPE_x64.wim`
- `C:\DeploymentShare\Boot\LiteTouchPE_x86.wim`

### 5. Verify

```powershell
Get-ChildItem "C:\DeploymentShare\Boot\*.wim"
```

Both files should exist.

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

Deployment proceeds automatically. Expect 20–60 minutes for a full deployment.

### 3. What happens during deployment

Refer to the Deployment Flow diagram in the [README](../README.md#deployment-flow). The task sequence runs these phases in order:

- Initialization
- Validation
- State Capture
- Preinstall
- Install
- Postinstall
- State Restore
- OOBE (`SetupComplete.cmd` → `pre.ps1` → `Customizations.ps1` → `pbr.ps1`)

### 4. Verify the logs

After deployment, on the target machine:

| Log location | Contents |
|---|---|
| `C:\MININT\SMSOSD\OSDLOGS\` | MDT deployment logs (may be deleted by cleanup) |
| `C:\ProgramData\OEM\Logs\` | OEM setup logs (`pre_*.log`, `SetupComplete.log`, `PBR_Deployment.log`) |
| `C:\Windows\Temp\DeploymentLogs\` | Post-deployment summaries |

Look for `[ERROR]` or `[FATAL]` entries.

---

## Post-Deployment

Once the OS is deployed and OOBE completes, log into the new machine with a local admin account and finalize the image.

### 1. Apply Windows Updates

Settings → Windows Update → **Check for updates**. Include **Optional updates** → **Driver updates**. Reboot as needed until no updates remain.

### 2. Apply OEM updates

Use the OEM Support Assistant (Dell Command Update, HP Support Assistant, Lenovo System Update, and so on) to install OEM-specific drivers and BIOS updates.

### 3. Run the post-deployment scripts

Scripts are in `C:\Scripts\` on the deployed machine. Run them in numerical order:

| Script | Purpose |
|---|---|
| `0CleanWindowsUpdates.cmd` | Clean the Windows component store after updates |
| `0Install-AnyDesk.cmd` | Install AnyDesk interactively (x64 only) |
| `0KeepAwake.cmd` | Prevent sleep during maintenance |
| `1Firstrun.cmd` | Interactive first pass: Windows Update, OEM utilities, GPU software |
| `2Secondrun.cmd` | Interactive second pass after restart: final updates and marker decisions |
| `3OEMDriversExport.cmd` | Export drivers to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB |
| `4ScanState.cmd` | Capture the PBR provisioning package and populate `C:\Recovery\AutoApply` |

Restart when the scripts instruct you to.

### 4. Export drivers back to the deployment share

If `3OEMDriversExport.cmd` produced a `.7z` file, copy it to `\\SERVER\Shared\DriverPacks` so the same model can be deployed faster next time.

---

## Offline Media

For deployments without a server or network, you can generate a bootable USB flash drive from your deployment share. The media set is **not shipped in this repository** — you create it on demand with Deployment Workbench.

Summary:

1. Create a media set in Deployment Workbench (default path `C:\Deploy\MDT`)
2. Update the media content — MDT copies the boot image, OS images, task sequences, and scripts
3. Format a USB flash drive as **FAT32**, label it **`DEPLOY`**, mark active
4. Copy the media content from `C:\Deploy\MDT\Content\` to the USB root
5. Copy the OEM payload from `\\SERVER\Shared\` to the USB root

The generated media uses SWM-split images so it fits on FAT32, which is required for UEFI boot on most hardware.

Full walkthrough: [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md).

---

## Verification Checklist

### Deployment host

- [ ] Hostname is `SERVER`
- [ ] Deployment account `Network User` exists and is a member of `Administrators`
- [ ] Account password is set, user cannot change password, password never expires
- [ ] Static IP is configured outside the DHCP scope
- [ ] ADK, WinPE Addon, SDK, MDT, PowerShell 7, and 7-Zip are installed
- [ ] `Prerequisites\All MDT Fixes 2025.exe` has been run
- [ ] Deployment share exists at `C:\DeploymentShare` and is shared as `DeploymentShare$`
- [ ] Repository `DeploymentShare/` contents have been merged into `C:\DeploymentShare`
- [ ] The Windows image has been imported into MDT
- [ ] Task sequences point to the imported OS entry
- [ ] `Control\Bootstrap.ini` has been edited
- [ ] `Control\CustomSettings.ini` has been edited
- [ ] `Control\Settings.xml` has been edited with the correct paths
- [ ] `Control\Medias.xml` has been edited if using a non-default media path
- [ ] Task sequence unattend files have been edited with the correct locale and time zone
- [ ] `x64\$OEM$\$1\Recovery\OEM\pre.ps1` has been edited (AnyDesk password)
- [ ] Boot images have been regenerated
- [ ] Boot images have been imported into WDS (or AOMEI PXE Boot)
- [ ] `\\SERVER\Shared` exists and contains the expected subfolders
- [ ] `\\SERVER\Shared\OEM` exists and contains `x64` and `x86` subfolders

### Target machine

- [ ] PXE boots into LiteTouch WinPE
- [ ] Task sequence picker appears (or is skipped)
- [ ] Windows OS installs without errors
- [ ] OEM drivers are applied during install
- [ ] Updates are injected into the offline image
- [ ] Recovery partition is created
- [ ] OOBE completes without errors
- [ ] `C:\ProgramData\OEM\Logs\` contains logs with no `[FATAL]` entries
- [ ] Windows is activated (if OEM firmware key is present)
- [ ] Office is installed and activated (if Office installer is present)
- [ ] LGPO policies are applied
- [ ] Framework convergence markers are written (`SYSTEM_DONE` and eventually `USER_DONE`)

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
| Deployment fails at "Install Operating System" | WIM missing or index wrong | Task sequence step, `OperatingSystems.xml` |
| Deployment completes but no drivers | OEM driver pack not found for the model | `C:\ProgramData\OEM\Logs\pre_*.log`, search for "No driver folder found" |
| Windows not activated | OEM firmware key missing or mismatched edition | `slmgr /dlv` on the target machine |
| Office not activated | Office app was running during Ohook gate | `C:\ProgramData\OEM\Logs\pre_*.log`, search for "Office activation deferred" |
| 7-Zip not found in WinPE | Boot image missing `Boot\Addon\x64` content | Verify `Boot.x64.ExtraDirectory` in `Settings.xml` |

### Where to get help

- **GitHub Discussions** — [github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions)
- **GitHub Issues** — [github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues)

When asking for help, include:

- Deployment host OS and role (server or desktop)
- Target machine make, model, CPU generation, BIOS version
- Which task sequence was used
- The exact error message and the relevant log excerpt
- Whether the failure is reproducible
