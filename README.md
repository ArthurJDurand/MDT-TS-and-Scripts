<div align="center">

# MDT Zero-Touch Deployment

**A production-oriented Microsoft Deployment Toolkit (MDT) deployment share for Windows 10 and Windows 11, with dynamic OEM driver injection, Intel VMD storage support, offline update integration, an OEM Apps framework, and offline media support.**

[![MDT](https://img.shields.io/badge/MDT-6.3.8456.1000-0078D4)](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)](https://www.microsoft.com/windows)
[![ADK](https://img.shields.io/badge/ADK-Windows%2011-0078D4)](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-ArthurJDurand-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/ArthurJDurand)

[Features](#features) · [Repository Structure](#repository-structure) · [Quick Start](#quick-start) · [Documentation](#documentation) · [Support](#support-this-project) · [Contributing](#contributing)

</div>

---

> [!IMPORTANT]
> **This repository ships the deployment share content, not a complete installer.** Cloning the repo gives you the scripts, task sequences, configuration files, and OEM content structure, but you must have a working MDT environment (ADK, WinPE Addon, MDT, and a created deployment share) before you can use it. See [Quick Start](#quick-start) and [docs/SETUP.md](docs/SETUP.md).

> [!NOTE]
> **Windows 10 reached end of support on October 14, 2025.** The Windows 10 task sequences remain for legacy hardware and existing deployments. New deployments should target Windows 11 Pro. The x86 tree is maintained for legacy 32-bit hardware only.

---

## What This Is

A production-oriented Microsoft Deployment Toolkit (MDT) deployment share that goes well beyond stock MDT. It deploys Windows 10 and Windows 11 Pro, applies OEM drivers and customizations, installs third-party applications, and supports both PXE and USB-based deployment.

The project is designed for technicians who need a repeatable, vendor-agnostic imaging solution across Dell, HP, Lenovo, Acer, ASUS, MSI, and other OEM hardware.

### What Makes It Different

- **Dynamic OEM driver injection** — Model-specific driver packs are selected by matching the target hardware against archive filenames and are applied to the offline image via DISM
- **Intel VMD storage support** — Automatically loads the correct VMD driver for 10th/11th Gen+ Intel platforms during WinPE when internal storage is not detected
- **OEM Apps framework** — A two-phase deployment engine that installs per-vendor applications and generates Start and taskbar layouts, with vendor-specific modules for eleven OEMs
- **Offline update injection** — Applies `.cab`/`.msu` packages to the offline image during deployment
- **WinRE deployment** — Configures the Windows Recovery Environment with conditional VMD driver injection
- **Push-button reset extensibility** — Custom PBR configuration that restores OEM content after a factory reset
- **Offline media support** — Generate a self-contained deployment USB from your share with a single Deployment Workbench operation

### Who This Is For

This project assumes **working knowledge** of:

- Windows Server and Windows Desktop editions
- Networking (DHCP, DNS, SMB, subnetting)
- Windows deployment concepts (WinPE, DISM, unattend.xml, WIM)
- Microsoft Deployment Toolkit and the Windows ADK

If any of those are unfamiliar, work through Microsoft's own MDT documentation first. This project extends MDT — it does not teach it.

---

## Features

| Feature | Description |
|---|---|
| **Three Task Sequences** | `WIN11PROX64`, `WIN10PROX64`, `WIN10PROX86` |
| **Dynamic Driver Injection** | OEM and WLAN drivers applied based on system model and CPU generation |
| **Intel VMD Support** | Loads VMD drivers in WinPE when internal storage is not detected |
| **Disk Management** | Wipes fixed drives, selects optimal target disk, partitions BIOS/UEFI, creates recovery partitions |
| **Update Integration** | Injects `.cab`/`.msu` updates into the offline image before first boot |
| **OEM App Extraction** | Extracts manufacturer-specific app archives to `C:\Recovery\OEM` |
| **OEM Driver Extraction** | Extracts model-specific driver archives to `C:\Recovery\OEM\Drivers` |
| **WinRE Configuration** | Deploys and configures WinRE on the recovery partition |
| **OEM Apps Framework** | Two-phase framework for per-vendor app installation and layout generation (x64 only) |
| **Local Group Policy** | Applies policies via LGPO during OOBE |
| **OEM License Activation** | Activates the OEM digital license during first boot |
| **Push-Button Reset** | Custom PBR chain that restores OEM content after a factory reset |
| **Offline Media** | Generate a bootable deployment USB from the deployment share on demand |
| **Network Share Fallback** | All extraction scripts fall back to a DEPLOY-labeled USB when the network is unavailable |

---

## Repository Structure

The repository root contains documentation, GitHub configuration, and the deployment share payload:

```
MDT-Zero-Touch-Deployment/
├── DeploymentShare/                     Merge this into your MDT deployment share
│   ├── Boot/
│   │   └── Addon/
│   │       ├── x64/                     Bundled 7-Zip for the x64 boot image
│   │       └── x86/                     Bundled 7-Zip for the x86 boot image
│   ├── Control/                         Deployment share configuration
│   │   ├── Bootstrap.ini
│   │   ├── CustomSettings.ini
│   │   ├── Settings.xml
│   │   ├── Medias.xml
│   │   ├── OperatingSystems.xml
│   │   ├── TaskSequences.xml
│   │   ├── WIN10PROX64/
│   │   ├── WIN10PROX86/
│   │   └── WIN11PROX64/
│   ├── Scripts/
│   │   ├── CopyOEM.wsf
│   │   ├── ZTIBde.wsf
│   │   ├── ZTIUtility.vbs
│   │   ├── DeployWiz_SelectTS.vbs
│   │   └── Custom/                      Task sequence scripts
│   ├── Templates/
│   │   └── Unattend_PE_x64.xml
│   ├── Tools/
│   │   ├── x64/                         BGInfo64, Microsoft.BDD.Utility.dll
│   │   └── x86/                         BGInfo, Microsoft.BDD.Utility.dll
│   ├── x64/
│   │   └── $OEM$/                       x64 OEM content, Apps framework, activation, layout
│   └── x86/
│       └── $OEM$/                       x86 OEM content (no framework; monolithic pre.ps1)
├── Prerequisites/
│   ├── All MDT Fixes 2025.exe           ADK/ADK-addon fixes, template patches
│   ├── for Desktop Editions of Windows/
│   │   └── AOMEI PXE Boot Free 1.5/
│   └── for Windows Server/
│       └── Configs/                     DHCP, WDS, and role configuration templates
├── docs/                                Detailed documentation
├── .github/                             Issue templates, PR template, funding, release notes
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── .gitignore
```

The `DeploymentShare/` folder mirrors the layout MDT creates when you create a new deployment share. Merge its contents into your own share after creating it.

The x86 tree ships the same OEM orchestration scripts (`SetupComplete.cmd`, `pre.ps1`, `HWID_Activation.cmd`, LGPO, PBR chain, post-deployment scripts) but does not ship the Apps framework. See [Known Limitations](#known-limitations).

---

## Quick Start

> **Prerequisites:** Windows Server (with DHCP + WDS) or a Windows desktop PC (with AOMEI PXE Boot), plus Windows ADK for Windows 11, Windows PE Addon, Windows SDK, and MDT.

### 1. Clone the repository

```bash
git clone https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment.git
```

### 2. Prepare your environment

- **Server path:** Rename the host to `SERVER`, create a `Network User` account (member of `Administrators`, password never expires, user cannot change password), install the DHCP and WDS roles, and import the provided configs.
- **Desktop path:** Rename the host to `SERVER`, create the same `Network User` account, and install AOMEI PXE Boot.

Full setup steps for both paths are in [docs/SETUP.md](docs/SETUP.md).

### 3. Create a deployment share

Open Deployment Workbench (Microsoft Deployment Toolkit) and create a new deployment share. The default location is `C:\DeploymentShare`. Close the Workbench.

### 4. Merge this repository into the deployment share

Copy the contents of `DeploymentShare/` from this repository into your new deployment share, merging folders.

```powershell
robocopy "C:\path\to\MDT-Zero-Touch-Deployment\DeploymentShare" "C:\DeploymentShare" /E /COPY:DAT /R:2 /W:5
```

### 5. Configure `Control\Bootstrap.ini`

Edit `DeployRoot`, `UserID`, `UserPassword`, and `UserDomain` to match your environment.

> [!WARNING]
> `Bootstrap.ini` stores credentials in **plaintext**. Use a least-privilege deployment account and restrict share permissions. Never commit real credentials to a public repository.

### 6. Prepare network shares

Create and populate the shares the scripts expect:

| Share | Purpose |
|---|---|
| `\\SERVER\Shared` | Updates, DriverPacks, WindowsRE, Servicing, ScanState |
| `\\SERVER\Shared\OEM` | OEM app archives (`.7z`) |

Details are in [docs/OEM.md](docs/OEM.md).

### 7. Build the boot images and PXE boot

Update the deployment share in Deployment Workbench to regenerate the boot images. Import them into WDS (or select them in AOMEI PXE Boot) and PXE boot a client.

**→ See [docs/SETUP.md](docs/SETUP.md) for the complete walkthrough.**

---

## Documentation

| Document | Description |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | Complete prerequisites, server and desktop setup, deployment share creation, and PXE deployment walkthrough |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Reference for every script in the repository, with parameters, dependencies, and known limitations |
| [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md) | The OEM Apps framework — phases, modules, manifests, extension points |
| [docs/OEM.md](docs/OEM.md) | OEM driver pack and app archive structure, `.7z` naming conventions, network share layout |
| [docs/OFFLINE-MEDIA.md](docs/OFFLINE-MEDIA.md) | Creating a DEPLOY-labeled USB flash drive for serverless deployments |
| [docs/WINDOWS-MEDIA.md](docs/WINDOWS-MEDIA.md) | Obtaining or building a Windows installation image |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common errors, log locations, and fixes |
| [CHANGELOG.md](CHANGELOG.md) | Version history and notable changes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute scripts, OEM packs, and improvements |

---

## Deployment Flow

```
PXE or USB boot
        │
        ▼
  WinPE (LiteTouchPE)
  • Gather rules
  • Load VMD driver if storage is missing
        │
        ▼
  Validation
  • Hardware check, BIOS/UEFI check
        │
        ▼
  Preinstall
  • Wipe fixed drives
  • Select optimal target disk
  • Partition (BIOS MBR / UEFI GPT)
  • Create recovery partition
  • Format secondary data drive
        │
        ▼
  Install
  • Apply OS image
  • Inject offline updates
  • Copy $OEM$ content
  • Extract OEM apps + drivers
  • Apply OEM + VMD drivers
        │
        ▼
  Postinstall
  • Configure WinRE
  • Clean up deployment artifacts
        │
        ▼
  State Restore
  • Install MDT applications
  • Apply local GPOs
        │
        ▼
  OOBE → SetupComplete.cmd
  • pre.ps1           OEM configuration, activation, third-party apps
  • Customizations.ps1 Branding, offline hive hardening
  • pbr.ps1           OEM Apps framework (SYSTEM phase, x64 only)
        │
        ▼
  First logon → resume task → pbr.ps1 (USER phase, x64 only)
  • Winget installs, health check, layout generation
        │
        ▼
  Post-deployment (manual, by technician)
  • Run C:\Scripts\0..4 in order
  • Capture PBR provisioning package
```

---

## Requirements

### Deployment Server (Windows Server)

- Windows Server with the **DHCP Server** and **WDS Server** roles
- Static IP address outside the DHCP scope
- Hostname set to `SERVER`
- Local account `Network User`, member of `Administrators`
- Password-protected sharing disabled (lab only)

### Deployment Workstation (Windows Desktop)

- Any desktop edition of Windows 10 or Windows 11
- AOMEI PXE Boot
- Hostname set to `SERVER`
- Local account `Network User`, member of `Administrators`

### Software (both paths)

- PowerShell 7
- Windows ADK for Windows 11
- Windows PE Addon for the ADK
- Windows SDK for Windows 11
- Microsoft Deployment Toolkit `6.3.8456.1000`
- 7-Zip (the bundled copy in `Boot/Addon/x64/` is used by the boot image; the deployed OS installs its own copy)

### Prerequisites Bundle

The `Prerequisites/` folder ships:

- `All MDT Fixes 2025.exe` — ADK and MDT template fixes required for modern Windows builds
- `for Desktop Editions of Windows/AOMEI PXE Boot Free 1.5/` — PXE boot server for desktop-based deployment
- `for Windows Server/Configs/` — DHCP, WDS, and Windows Server role configuration templates

---

## Configuration Files to Edit

| File | What to edit |
|---|---|
| `Control\Bootstrap.ini` | `DeployRoot`, `UserID`, `UserPassword`, `UserDomain` |
| `Control\CustomSettings.ini` | Rules for computer name, domain join, applications |
| `Control\Medias.xml` | `Root` if you use a non-default offline media path |
| `Control\Settings.xml` | `UNCPath`, `PhysicalPath`, `Boot.x86.ExtraDirectory`, `Boot.x64.ExtraDirectory` |
| `Task Sequences\WIN10PROX64\Unattend.xml` | Locale and time zone |
| `Task Sequences\WIN11PROX64\Unattend.xml` | Locale and time zone |
| `x64\$OEM$\$1\Recovery\OEM\pre.ps1` | AnyDesk password, activation settings, third-party app list |
| `x64\$OEM$\$1\Recovery\OEM\LGPO\Backup` | Local group policies (replace with your own backup if desired) |

---

## After OS Deployment

Once the OS is deployed and OOBE completes, run the scripts in `C:\Scripts\` on the deployed machine in numerical order. Restart when instructed.

| Script | Purpose |
|---|---|
| `0CleanWindowsUpdates.cmd` | Clean the Windows component store after Windows Updates |
| `0Install-AnyDesk.cmd` | Install AnyDesk interactively (x64 only) |
| `0KeepAwake.cmd` | Prevent sleep during long-running maintenance |
| `1Firstrun.cmd` | Interactive first pass: Windows Update, OEM utility setup, GPU software |
| `2Secondrun.cmd` | Interactive second pass after restart: final updates and marker decisions |
| `3OEMDriversExport.cmd` | Export drivers, save to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB |
| `4ScanState.cmd` | Capture a PBR provisioning package and populate `C:\Recovery\AutoApply` |

---

## Offline Media

For deployments without a server or network, you can generate a self-contained USB from your deployment share using the Deployment Workbench.

Summary:

1. Create a media set in Deployment Workbench (default path `C:\Deploy\MDT`)
2. Update the media content — MDT copies the boot image, OS images, task sequences, and scripts
3. Format a USB flash drive as **FAT32**, label it **`DEPLOY`**, mark active
4. Copy the media content to the USB root
5. Copy the OEM payload from `\\SERVER\Shared` to the USB root

The media set is generated on demand. It is not shipped in this repository. See [docs/OFFLINE-MEDIA.md](docs/OFFLINE-MEDIA.md) for the full walkthrough.

---

## Verification Checklist

### Deployment host

- [ ] Hostname is `SERVER`
- [ ] Deployment account `Network User` exists and is a member of `Administrators`
- [ ] Account password is set, user cannot change password, password never expires
- [ ] Static IP is configured outside the DHCP scope
- [ ] ADK, WinPE Addon, SDK, MDT, PowerShell 7, and 7-Zip are installed
- [ ] `Prerequisites/All MDT Fixes 2025.exe` has been run
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
- [ ] Framework convergence markers are written (`SYSTEM_DONE` and eventually `USER_DONE`) — x64 only

---

## Known Limitations

- **Windows 10 end of support:** Windows 10 reached end of support on October 14, 2025. Win10 task sequences are for legacy hardware and existing deployments only.
- **Plaintext credentials:** `Control\Bootstrap.ini` stores credentials in cleartext. Use a least-privilege deployment account and restrict share permissions. Never commit real credentials.
- **AnyDesk password is hardcoded** in `pre.ps1` as `p@$$w0rd`. Change it before using AnyDesk outside an isolated lab.
- **MDT is no longer under active development.** This project targets MDT `6.3.8456.1000`.
- **Apps framework is x64-only.** The OEM Apps framework (framework modules, OEM modules, JSON manifests) ships only in the x64 tree. On x86, OEM application installation is handled by a monolithic `pre.ps1` with no manifest-driven module system. Post-deployment updates via `Update.xml` are x64-only.
- **VMD driver versions are hardcoded** for specific CPU generations in `LoadWinPEDrivers.ps1` and `ApplyOEMDrivers.ps1`. New generations require code updates.
- **`ExtractOEMDrivers.ps1` hardcodes the OS family to Win11** when resolving the driver pack path. This is a latent bug for Win10 deployments — the Win10 task sequence will look in the Win11 driver pack folder.
- **x86 task sequence cannot use VMD.** Intel VMD drivers are x64-only. The x86 task sequence will not attempt VMD loading.
- **OEM driver packs are model-specific.** `ExtractOEMDrivers.ps1` relies on model string matching. Unknown models fall through without a driver pack.
- **No built-in MDT application installation.** `Applications.xml` and `Packages.xml` are empty. Add your own applications via MDT or the `$OEM$` folder.
- **Framework canonical docs are not in this repository.** The framework's design rationale and internal reference documentation are maintained separately. See [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md) for the framework overview that ships here.

**→ See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common errors and fixes.**

---

## Related Projects

| Project | Purpose |
|---|---|
| [`MDT-Windows-Image-Builder`](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) | Companion repository with a full guide on building a custom Windows installation image using UUPDump, Hyper-V, and audit mode. Required if you want to produce your own `install.wim`. |
| [`MDT-OEM-Extensibility`](https://github.com/ArthurJDurand/MDT-OEM-Extensibility) | Companion repository that builds the OEM payload archives (`<Vendor>.7z`) this deployment share consumes. Fetches installers and drivers from official vendor sources. |

The `MDT-Windows-Image-Builder` repository is where the deep guide for image creation lives. The `MDT-OEM-Extensibility` repository is where the OEM content is built. This repository expects you to already have a Windows `install.wim` and OEM archives to import into MDT.

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to submit changes, script standards, and areas where help is needed.

### Script Standards

Scripts in `Scripts\Custom\` must be WinPE-safe. Scripts in `$OEM$` may use WMI/CIM but must write to the registry via `reg.exe` only. Full rules are in [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/SCRIPTS.md](docs/SCRIPTS.md).

---

## Support This Project

This project is maintained in spare time and provided free of charge. If it saved you or your organization time, consider [sponsoring ongoing maintenance](https://github.com/sponsors/ArthurJDurand). Sponsorship funds issue triage, script improvements, OEM pack updates, and documentation.

[![Sponsor](https://img.shields.io/badge/Sponsor-ArthurJDurand-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/ArthurJDurand)

---

## License

MIT License — see [LICENSE](LICENSE).

---

## Author

**Arthur Durand**

- GitHub: [@ArthurJDurand](https://github.com/ArthurJDurand)
- Repository: [MDT-Zero-Touch-Deployment](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment)
- Sponsor: [github.com/sponsors/ArthurJDurand](https://github.com/sponsors/ArthurJDurand)

---

## Acknowledgments

- The MDT community for ongoing documentation and scripts
- Microsoft for the Deployment Toolkit and the Windows ADK
- Michael Niehaus for the original `CopyOEM.wsf`
- All contributors who have shared driver packs, scripts, and feedback

---

<div align="center">

**If this project helped you deploy Windows faster, consider giving it a ⭐**

</div>
