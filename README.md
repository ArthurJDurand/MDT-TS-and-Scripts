```markdown
<div align="center">

# MDT Task Sequences & Custom Scripts

**Zero-touch deployment framework for Windows 10 & 11 Pro with dynamic OEM driver injection, Intel VMD storage support, offline update integration, and OEM customization.**

[![MDT](https://img.shields.io/badge/MDT-6.3.8456.1000-0078D4)](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)](https://www.microsoft.com/windows)
[![ADK](https://img.shields.io/badge/ADK-Windows%2011-0078D4)](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
[![Release](https://img.shields.io/github/v/release/ArthurJDurand/MDT-TS-and-Scripts?include_prereleases&sort=semver)](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/releases)
[![Last Commit](https://img.shields.io/github/last-commit/ArthurJDurand/MDT-TS-and-Scripts)](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/commits/main)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-ArthurJDurand-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/ArthurJDurand)

[Quick Start](#quick-start) · [Features](#features) · [Scripts Reference](#scripts-reference) · [Repository Structure](#repository-structure) · [Documentation](#documentation) · [Support](#support-this-project) · [Contributing](#contributing)

</div>

---

> [!IMPORTANT]
> **This repository is only half of the project.** The scripts, task sequences, and configuration files live here — but the **operating system images, OEM driver packs, OEM app archives, update packages, and supporting tools** are distributed via the [shared OneDrive folder](https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6). You **must** download and merge both to have a working deployment share. See [Quick Start](#quick-start).

> [!NOTE]
> **Windows 10 reached end of support on October 14, 2025.** The Windows 10 task sequences remain in this project for legacy hardware and existing deployments, but new deployments should target Windows 11 Pro.

---

## What This Is

A production-oriented Microsoft Deployment Toolkit (MDT) deployment share that goes well beyond stock MDT. It deploys 64-bit Windows 10 Pro and 64-bit Windows 11 Pro (plus 32-bit Windows 10 Pro), extracts and injects OEM customizations and drivers, and installs third-party software — all from a single PXE boot.

Built and maintained by [Arthur Durand](https://github.com/ArthurJDurand), this framework is designed for technicians who need a repeatable, vendor-agnostic imaging solution across Dell, HP, Lenovo, Acer, ASUS, MSI, and other OEM hardware.

### Highlights

- **Dynamic OEM driver extraction** — Model-specific driver packs are extracted from `.7z` archives and applied to the offline image via DISM
- **Intel VMD storage support** — Automatically loads the correct VMD driver for 10th/11th Gen+ Intel platforms during WinPE when internal storage is not detected
- **Smart target disk selection** — Prioritizes NVMe SSDs, then SATA SSDs, then HDDs
- **Offline update injection** — Applies `.cab`/`.msu` packages to the offline image during deployment
- **Custom WinRE deployment** — Configures recovery partition with conditional VMD driver injection
- **OEM app extraction** — Extracts manufacturer-specific app archives to `C:\Recovery\OEM`
- **LGPO application** — Applies local group policies from `$OEM$\$1\Recovery\OEM\LGPO`
- **Offline media support** — Build a DEPLOY-labeled USB flash drive for deployments without a server
- **Self-updating OEM payloads** — Companion GitHub repositories deliver the latest Apps, Drivers, and LGPO archives via hash-verified `.7z` downloads

### Who This Is For

This project assumes **working knowledge** of the following:

- Windows Server and Windows Desktop editions
- Networking (DHCP, DNS, subnetting, SMB shares)
- Windows deployment concepts (WinPE, DISM, unattend.xml, WIM)
- Microsoft Deployment Toolkit and the Windows ADK

If any of those are unfamiliar, start with Microsoft's own MDT documentation before attempting this project.

---

## Features

| Feature | Description |
|---|---|
| **Three Task Sequences** | `WIN11PROX64`, `WIN10PROX64`, `WIN10PROX86` |
| **Dynamic Driver Injection** | OEM, WLAN, and storage drivers applied based on system model and CPU generation |
| **Intel VMD Support** | Loads VMD drivers in WinPE when internal storage is not detected |
| **Disk Management** | Wipes fixed drives, selects optimal target disk, partitions BIOS/UEFI, creates recovery partitions |
| **Update Integration** | Injects `.cab`/`.msu` updates into the offline image before first boot |
| **OEM App Extraction** | Extracts manufacturer-specific app archives to `C:\Recovery\OEM` |
| **OEM Driver Extraction** | Extracts model-specific driver archives to `C:\Recovery\OEM\Drivers` |
| **WinRE Configuration** | Deploys and configures Windows Recovery Environment on the recovery partition |
| **LGPO Application** | Applies local group policies from `$OEM$\$1\Recovery\OEM\LGPO` |
| **OEM License Activation** | Activates the OEM digital license during first boot via `pre.ps1` |
| **Office Installation & Activation** | Installs Microsoft Office from `$OEM$` and activates via Ohook when safe |
| **Third-Party Applications** | 7-Zip, WinRAR, AnyDesk, RustDesk, DymaxIO, Acronis Drive Monitor (HDD-only) |
| **Post-Deployment Cleanup** | Removes MDT artifacts (`_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`) |
| **Offline Media** | Full support for DEPLOY-labeled USB flash drive deployments |
| **Network Share Fallback** | All extraction scripts fall back to `\\SERVER\Shared` or a DEPLOY USB when network is unavailable |
| **Self-Updating Payloads** | Companion repos deliver Apps/Drivers/LGPO archives with SHA-256 verification from Gists |

---

## Deployment Flow

```
   ┌─────────────┐
   │  PXE Boot   │
   └──────┬──────┘
          ▼
   ┌─────────────────────────────────────┐
   │  WinPE (LiteTouchPE_x64/x86)        │
   │  • Gather rules (ZTIGather)         │
   │  • Load VMD if storage missing      │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  Validation Phase                    │
   │  • Validate hardware                 │
   │  • BIOS/UEFI check                   │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  Preinstall Phase                    │
   │  • Wipe fixed drives                 │
   │  • Select optimal target disk        │
   │  • Partition (BIOS MBR / UEFI GPT)   │
   │  • Create recovery partition         │
   │  • Format secondary data drive       │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  Install Phase                       │
   │  • Apply OS image                    │
   │  • Inject offline updates            │
   │  • Copy OEM files ($OEM$)            │
   │  • Extract OEM apps + drivers        │
   │  • Apply OEM + VMD drivers           │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  Postinstall Phase                   │
   │  • Configure WinRE                   │
   │  • Cleanup scripts                   │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  State Restore Phase                 │
   │  • Install applications              │
   │  • Final cleanup                     │
   └──────┬──────────────────────────────┘
          ▼
   ┌─────────────────────────────────────┐
   │  OOBE (SetupComplete.cmd)            │
   │  • pre.ps1         (activation,      │
   │                     drivers, LGPO,   │
   │                     app installs)    │
   │  • Customizations.ps1                │
   │  • pbr.ps1         (push-button      │
   │                     reset package)   │
   └─────────────────────────────────────┘
```

---

## Quick Start

> **Prerequisites:** Windows Server (with DHCP + WDS) **or** a Windows desktop PC (with AOMEI PXE Boot), Windows ADK for Windows 11, Windows PE Addon, Windows SDK, MDT, and a deployment share.

### 1. Clone the repository

```bash
git clone https://github.com/ArthurJDurand/MDT-TS-and-Scripts.git
```

### 2. Download the companion content

Download the [shared OneDrive folder](https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6) and merge its contents with the cloned repository. **This step is mandatory** — the OS images, OEM packs, and update packages are not stored in Git.

### 3. Prepare your environment

- **Server path:** Rename host to `SERVER`, create a `Network User` account (password `p@$$w0rd`, member of `Administrators`), install the DHCP and WDS roles, and import the provided configs.
- **Desktop path:** Rename host to `SERVER`, create the same `Network User` account, install AOMEI PXE Boot.

### 4. Create and merge the deployment share

Create a new deployment share in Deployment Workbench (default location `C:\DeploymentShare`), then merge the contents of this repository **and** the shared OneDrive folder into it.

### 5. Configure `Control\Bootstrap.ini`

Edit `DeployRoot`, `UserID`, `UserPassword`, and `UserDomain` to match your environment.

> [!WARNING]
> `Bootstrap.ini` stores credentials in **plaintext**. Use a least-privilege deployment account and restrict share permissions to the minimum required. Never commit real credentials to a public repository.

### 6. Generate boot images and PXE boot

Update your deployment share, import `LiteTouchPE_x64.wim` and `LiteTouchPE_x86.wim` into WDS (or select them in AOMEI PXE Boot), then PXE boot a client.

**→ See [docs/SETUP.md](docs/SETUP.md) for the complete step-by-step guide.**

---

## Scripts Reference

### Task Sequence Scripts (`Scripts\Custom\`)

| Script | Purpose |
|---|---|
| `LoadWinPEDrivers.ps1` | Loads the latest Intel VMD storage driver in WinPE when internal storage is not detected. Writes a marker file so downstream scripts know VMD was required. |
| `CleanFixedDrives.ps1` | Wipes all internal (non-USB) drives using `Clear-Disk -RemoveData -RemoveOEM`. |
| `SetTargetOSDisk.ps1` | Selects the first NVMe SSD, or first SATA SSD, or first non-USB disk as the target OS disk. Sets `OSDDiskIndex`. |
| `CreateRecoveryPartition-BIOS.ps1` | Shrinks the Windows partition and creates a BIOS recovery partition (ID 27, NTFS). |
| `CreateRecoveryPartition-UEFI.ps1` | Shrinks the Windows partition and creates a UEFI recovery partition (GUID `de94bba4-06d1-4d40-a16a-bfd50179d6ac`, GPT attributes `0x8000000000000001`). |
| `FormatDataDrive.ps1` | Formats any additional raw internal disk as a GPT Data drive with a 128 MB MSR partition. |
| `ApplyUpdates10x64.ps1` | Injects Windows 10 x64 updates (`.cab`/`.msu`) into the offline image. |
| `ApplyUpdates10x86.ps1` | Injects Windows 10 x86 updates into the offline image. |
| `ApplyUpdates11.ps1` | Injects Windows 11 updates into the offline image. |
| `ExtractOEMAppsx64.ps1` | Extracts manufacturer-specific app `.7z` archives from `\\SERVER\OEM\x64` or a DEPLOY USB to `C:\Recovery\OEM`. |
| `ExtractOEMAppsx86.ps1` | x86 variant of the OEM app extraction. |
| `ExtractOEMDrivers.ps1` | Extracts the model-specific driver `.7z` archive from `\\SERVER\Shared\DriverPacks` or a DEPLOY USB to `C:\Recovery\OEM\Drivers`. |
| `ApplyOEMDrivers.ps1` | Applies extracted OEM, WLAN, and Intel VMD drivers to the offline Windows image via DISM. |
| `WinRE.ps1` | Deploys and configures WinRE on the recovery partition, optionally injecting VMD drivers. |
| `CleanupScripts.ps1` | Removes MDT artifacts (`_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`) after deployment. |
| `CopyOEM.wsf` | Copies `$OEM$\$1` and `$OEM$\$$` content from the deployment share to the target OS (based on Michael Niehaus's original script). |

### `$OEM$` Orchestration Scripts (`$OEM$\$$\\Setup\`)

| Script | Purpose |
|---|---|
| `SetupComplete.cmd` | Runs at the end of OOBE. Orchestrates `pre.ps1`, `Customizations.ps1`, and `pbr.ps1` in sequence, then cleans up MDT artifacts. |

### `$OEM$` Configuration Scripts (`$OEM$\$1\Recovery\OEM\`)

| Script | Purpose |
|---|---|
| `pre.ps1` | Runs during `SetupComplete.cmd`. Installs OEM drivers, WLAN, Intel VMD, applies LGPO, activates Windows and Office, installs third-party apps, and configures the OEM\Update scheduled task. Maintains its own inline version history. |
| `Customizations.ps1` | Runs after `pre.ps1` for additional OEM customizations. |
| `Apps\pbr.ps1` | Runs after `Customizations.ps1` to create the push-button reset provisioned package. |

### `$OEM$` Activation Scripts (`$OEM$\$1\Recovery\OEM\Activation\`)

| Script | Purpose |
|---|---|
| `HWID_Activation.cmd` | HWID-based Windows activation fallback when the firmware OEM key fails. Called by `pre.ps1`. |
| `Ohook_Activation.cmd` | Office activation via Ohook. Called by `pre.ps1` after `Test-OfficeSafeForActivation` confirms no Office app is running. |

### `$OEM$` Payload Updater Scripts (`$OEM$\$1\Recovery\OEM\`)

| Script | Purpose |
|---|---|
| `Apps.ps1` | Downloads the latest Apps `.7z` split archive from a companion GitHub repository, verifies SHA-256 against a Gist, and extracts to `C:\Recovery\OEM\Apps`. |
| `Drivers.ps1` | Downloads the latest Drivers `.7z` split archive from a companion GitHub repository, verifies SHA-256 against a Gist, and extracts to `C:\Recovery\OEM\Drivers`. |
| `LGPO.ps1` | Downloads the latest `LGPO.7z` from a companion GitHub repository, verifies SHA-256 against a Gist, and extracts to `C:\Recovery\OEM\LGPO`. |

### `$OEM$` Application Configurators (`$OEM$\$1\Recovery\OEM\Apps\`)

| Script | Purpose |
|---|---|
| `RustDesk.ps1` | Applies RustDesk configuration after installation (password, relay server, persistence). |
| `DymaxIOLicense.ps1` | Applies the DymaxIO license after installation. Returns exit code 2 if DymaxIO is not present. |
| `Update.xml` | Task Scheduler definition imported by `pre.ps1` as the `OEM\Update` scheduled task. |

### `$OEM$` Post-Deployment Scripts (`$OEM$\$1\Scripts\`)

| Script | Purpose |
|---|---|
| `OEMDriversExport.ps1` | Exports drivers from the deployed OS, archives them as `.7z`, and copies to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB. |
| `ScanWindowsImage64.ps1` | Cleans the Driver Store and restores the `Microsoft-OneCore-DirectX-Database-FOD-Package`. |
| `ScanStatex64.ps1` | Creates a provisioned package for push-button reset using USMT `ScanState`. |

**→ See [docs/SCRIPTS.md](docs/SCRIPTS.md) for detailed documentation of every script, including parameters, environment variables, and known limitations.**

---

## Related Repositories

The updater scripts (`Apps.ps1`, `Drivers.ps1`, `LGPO.ps1`) pull payloads from three companion GitHub repositories. Each archive is split into `.7z.001`, `.7z.002`, … parts and hash-verified against a GitHub Gist.

| Repository | Payload | Extracted To |
|---|---|---|
| [`52250179/Update-PBR-Extensibility-Apps`](https://github.com/52250179/Update-PBR-Extensibility-Apps) | OEM application installers | `C:\Recovery\OEM\Apps` |
| [`52250179/Update-PBR-Extensibility-Drivers`](https://github.com/52250179/Update-PBR-Extensibility-Drivers) | Model-specific driver packs | `C:\Recovery\OEM\Drivers` |
| [`52250179/Update-PBR-Extensibility-LGPO`](https://github.com/52250179/Update-PBR-Extensibility-LGPO) | LGPO tool and policy backups | `C:\Recovery\OEM\LGPO` |

If any of these repositories become unavailable, replace the `$GistUrl`, `$RepoOwner`, and `$RepoName` variables in the corresponding `.ps1` file with your own.

---

## Repository Structure

```
MDT-TS-and-Scripts/
├── Control/                       # Deployment share control files
│   ├── Bootstrap.ini              # WinPE bootstrap (server, creds, domain)
│   ├── CustomSettings.ini         # Rules for zero-touch deployment
│   ├── Medias.xml                 # Offline media configuration
│   └── Settings.xml               # Deployment share settings
├── Scripts/
│   └── Custom/                    # Task sequence PowerShell scripts
│       ├── ApplyOEMDrivers.ps1
│       ├── ApplyUpdates10x64.ps1
│       ├── ApplyUpdates10x86.ps1
│       ├── ApplyUpdates11.ps1
│       ├── CleanFixedDrives.ps1
│       ├── CleanupScripts.ps1
│       ├── CreateRecoveryPartition-BIOS.ps1
│       ├── CreateRecoveryPartition-UEFI.ps1
│       ├── ExtractOEMAppsx64.ps1
│       ├── ExtractOEMAppsx86.ps1
│       ├── ExtractOEMDrivers.ps1
│       ├── FormatDataDrive.ps1
│       ├── LoadWinPEDrivers.ps1
│       ├── SetTargetOSDisk.ps1
│       └── WinRE.ps1
├── $OEM$/                         # Copied to C:\Windows\Setup\Scripts
│   ├── $1/                        # Copied to the root of the target OS
│   │   ├── Recovery/OEM/          # pre.ps1, Apps.ps1, Drivers.ps1, LGPO.ps1, LGPO, Activation, Apps
│   │   └── Scripts/               # OEMDriversExport, ScanWindowsImage64, ScanStatex64
│   └── $$/                        # Copied to C:\Windows
│       └── Setup/                 # SetupComplete.cmd
├── Operating Systems/             # Win10 x64, Win10 x86, Win11 x64 WIMs
├── Out-of-box Drivers/            # MDT-managed drivers
├── Boot/                          # LiteTouchPE_x64.wim, LiteTouchPE_x86.wim
├── Task Sequences/                # WIN10PROX64, WIN10PROX86, WIN11PROX64
├── Prerequisites/                 # DHCP/WDS configs, MDT templates, AOMEI
├── Updates/                       # .cab/.msu update packages (Win10 x64/x86, Win11)
├── docs/                          # Detailed documentation
│   ├── SETUP.md
│   ├── SCRIPTS.md
│   ├── OEM.md
│   ├── OFFLINE-MEDIA.md
│   └── TROUBLESHOOTING.md
├── .github/
│   ├── FUNDING.yml
│   └── release.yml
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

---

## Documentation

| Document | Description |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | Complete prerequisites, server/desktop setup, deployment share creation, and PXE deployment walkthrough |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Detailed documentation for every custom script, including parameters, environment variables, and known limitations |
| [docs/OEM.md](docs/OEM.md) | OEM app and driver pack preparation, `.7z` naming conventions, and directory structure |
| [docs/OFFLINE-MEDIA.md](docs/OFFLINE-MEDIA.md) | Creating a DEPLOY-labeled USB flash drive for serverless deployments |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common errors, log locations, and fixes |
| [CHANGELOG.md](CHANGELOG.md) | Version history and notable changes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute scripts, OEM packs, and improvements |

---

## Offline Media (USB Deployment)

You can create an offline media set on a USB flash drive to deploy without a server:

1. Copy the `MDT` folder from this repository to the root of your system drive (e.g., `C:\Deploy\MDT`).
2. Update your Media in Deployment Workbench.
3. Format a USB flash drive as **FAT32**, label it **`DEPLOY`**, and mark the partition active.
4. Copy the contents of your Media Set (`C:\Deploy\MDT\Content`) to the root of the USB drive.
5. Copy the contents of the `Shared` folder to the root of the USB drive.

**→ See [docs/OFFLINE-MEDIA.md](docs/OFFLINE-MEDIA.md) for the full walkthrough.**

---

## Requirements

### Deployment Server (Windows Server)

- Windows Server with the **DHCP Server** and **WDS Server** roles installed
- Static IP address on your subnet (outside the DHCP scope)
- Hostname renamed to `SERVER`
- Local account `Network User` (member of `Administrators`)
- Password-protected sharing disabled

### Deployment Workstation (Windows Desktop)

- Any desktop edition of Windows 10 or Windows 11
- **AOMEI PXE Boot** server
- Hostname renamed to `SERVER`
- Local account `Network User` (member of `Administrators`)
- Password-protected sharing disabled

### Software (Both)

- **PowerShell 7**
- **Windows ADK for Windows 11**
- **Windows PE Addon for the ADK**
- **Windows SDK for Windows 11**
- **Microsoft Deployment Toolkit (MDT)**
- **7-Zip** (installed at `C:\Program Files\7-Zip\7z.exe` — required by the payload updater scripts)

### Network Shares

| Share | Purpose |
|---|---|
| `\\SERVER\DeploymentShare$` | MDT deployment share |
| `\\SERVER\Shared` | Updates, DriverPacks, WindowsRE, Servicing, ScanState |
| `\\SERVER\OEM` | OEM app archives (`.7z`) |

---

## Configuration Files to Edit

Most users will only need to edit a few files:

| File | What to edit |
|---|---|
| `Control\Bootstrap.ini` | `DeployRoot`, `UserID`, `UserPassword`, `UserDomain` |
| `Control\CustomSettings.ini` | Rules for computer name, domain join, applications |
| `Control\Medias.xml` | `Root` if you use a non-default offline media path |
| `Control\Settings.xml` | `UNCPath`, `PhysicalPath`, `Boot.x86.ExtraDirectory`, `Boot.x64.ExtraDirectory` |
| `Task Sequences\WIN10PROX64\Unattend.xml` | Locales and time zone |
| `Task Sequences\WIN11PROX64\Unattend.xml` | Locales and time zone |
| `$OEM$\$1\Recovery\OEM\pre.ps1` | AnyDesk password, OEM license activation, LGPO application |
| `$OEM$\$1\Recovery\OEM\Apps.ps1` | Companion repo owner/name, Gist hash URL |
| `$OEM$\$1\Recovery\OEM\Drivers.ps1` | Companion repo owner/name, Gist hash URL |
| `$OEM$\$1\Recovery\OEM\LGPO.ps1` | Companion repo owner/name, Gist hash URL |
| `$OEM$\$1\Scripts\OEMDriversExport.ps1` | Driver export destination |
| `$OEM$\$1\Scripts\ScanWindowsImage64.ps1` | Servicing path |
| `$OEM$\$1\Scripts\ScanStatex64.ps1` | ScanState tool path |

---

## After OS Deployment

Once the OS is deployed, use the scripts in `C:\Scripts` on the deployed client to finalize the image:

| Script | Purpose |
|---|---|
| `1CleanImage.cmd` | Cleans up the Windows image after Windows Updates |
| `2CleanupDriverStore` | Cleans up the Driver Store |
| `3OEMDriversExport` | Captures drivers, archives as `.7z`, copies to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB |
| `4ScanState` | Creates a provisioned package for push-button reset |

Apply updates and drivers via Windows Update (including Optional Driver updates), then use the bundled OEM Support/Update apps to install OEM drivers and updates.

---

## Known Limitations

- **Windows 10 end of support:** Windows 10 reached end of support on October 14, 2025. The Win10 task sequences are provided for legacy hardware and existing deployments only.
- **Plaintext credentials:**
  - `Control\Bootstrap.ini` stores the deployment share account in cleartext. Use a least-privilege deployment account and restrict share permissions. Never commit real credentials to a public repository.
  - `$OEM$\$1\Recovery\OEM\pre.ps1` contains a hardcoded `$AnyDeskPassword = 'p@$$w0rd'`. **Change this before using AnyDesk in any non-lab environment.**
- **MDT lifecycle:** Microsoft Deployment Toolkit is no longer under active development. This project targets MDT `6.3.8456.1000`.
- **WinPE feature packs:** Some scripts assume specific WinPE feature packs. `winpe-wmi` is **not** included by default in `Scripts\Custom\`. Scripts in `Scripts\Custom\` use registry-based hardware detection to stay WinPE-safe. Scripts in `$OEM$` run in the full OS and may use WMI/CIM.
- **VMD driver versions:** Intel VMD driver versions are hardcoded for specific CPU generations in `LoadWinPEDrivers.ps1` and `ApplyOEMDrivers.ps1`. New generations require updates to the generation map.
- **x86 task sequence:** The `WIN10PROX86` task sequence is provided for legacy 32-bit hardware. VMD and some driver packs are x64-only and will not apply.
- **OEM packs are model-specific:** `ExtractOEMDrivers.ps1` relies on exact or partial model string matching. Unknown models will fall through without a driver pack.
- **No built-in application installation:** `Applications.xml` and `Packages.xml` are empty by default. Add your own applications via MDT or the `$OEM$` folder.
- **Companion repos and Gists are external dependencies:** `Apps.ps1`, `Drivers.ps1`, and `LGPO.ps1` rely on GitHub repositories and Gists owned by a third party (`52250179`). If those become unavailable, replace the variables in each script with your own.
- **Office activation is deferred when Office is running:** `pre.ps1` fails closed if any Office application is running in an interactive user session. The machine may complete OOBE with Office installed but not yet activated.

**→ See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common errors and fixes.**

---

## Contributing

Contributions are welcome and encouraged! This project improves through community feedback.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Script Standards

All PowerShell scripts in `Scripts/Custom/` must:

- Be **WinPE-safe** — use the registry and file system only; avoid WMI/CIM in WinPE unless `winpe-wmi` is added to FeaturePacks. (Scripts in `$OEM$` run in the full OS and are exempt.)
- Use `Get-Volume ... | Select-Object -First 1` when retrieving volume letters
- Include retry logic for DISM and robocopy operations
- Be silent (no `Write-Host` unless absolutely necessary for diagnostics)
- Preserve exit codes — do not mask errors

**→ See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guidelines.**

### Ideas for Contributions

- **OEM license edition detection** — A script that sets the deployed Windows edition to match the OEM license (e.g., Home Single Language) during deployment, and limits LGPO application to Pro edition
- **Additional OEM packs** — Driver and app packs for OEMs not yet covered
- **New hardware support** — VMD/storage driver updates for newer Intel and AMD platforms
- **Script improvements** — Any bug fixes or enhancements to existing scripts

---

## Support This Project

This project is maintained in my spare time and provided free of charge. If it saved you or your organization time, please consider [sponsoring ongoing maintenance](https://github.com/sponsors/ArthurJDurand). Sponsorship helps fund issue triage, script improvements, OEM driver pack updates, and documentation.

[![Sponsor](https://img.shields.io/badge/Sponsor-ArthurJDurand-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/ArthurJDurand)

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Author

**Arthur Durand**

- GitHub: [@ArthurJDurand](https://github.com/ArthurJDurand)
- Repository: [MDT-TS-and-Scripts](https://github.com/ArthurJDurand/MDT-TS-and-Scripts)
- Sponsor: [github.com/sponsors/ArthurJDurand](https://github.com/sponsors/ArthurJDurand)

---

## Acknowledgments

- The MDT community for ongoing documentation and scripts
- Microsoft for the Deployment Toolkit and ADK
- Michael Niehaus for the original `CopyOEM.wsf` script
- All contributors who have shared OEM packs, scripts, and feedback

---

<div align="center">

**If this project helped you deploy Windows faster, consider giving it a ⭐**

</div>
```
