<div align="center">

# MDT Zero-Touch Deployment

**A production-oriented Microsoft Deployment Toolkit (MDT) deployment share for Windows 10 and Windows 11, with dynamic OEM driver injection, Intel VMD storage support, offline update integration, an OEM Apps framework, and offline media support.**

[![MDT](https://img.shields.io/badge/MDT-6.3.8456.1000-0078D4)](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)](https://www.microsoft.com/windows)
[![ADK](https://img.shields.io/badge/ADK-Windows%2011-0078D4)](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Sponsor](https://img.shields.io/badge/Sponsor-ArthurJDurand-ea4aaa?logo=github-sponsors&logoColor=white)](https://github.com/sponsors/ArthurJDurand)

[Features](#features) · [Repository Structure](#repository-structure) · [Quick Start](#quick-start) · [Documentation](#documentation) · [Support](#support-this-project) · [Contributing](#contributing)

</div>

---

> [!IMPORTANT]
> **This repository ships the deployment share content, not a complete installer.** Cloning the repo gives you the scripts, task sequences, configuration files, and OEM content, but you must have a working MDT environment (ADK, WinPE Addon, MDT, and a created deployment share) before you can use it. See [Quick Start](#quick-start) and [docs/SETUP.md](docs/SETUP.md).

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
- **Offline media support** — A pre-built offline media set in `MDT/Content/` for deployments without a server, using SWM-split images so the media fits on FAT32 USB

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
| **Offline Media** | Pre-built media set for USB-based deployments |
| **Network Share Fallback** | All extraction scripts fall back to a DEPLOY-labeled USB when the network is unavailable |

---

## Repository Structure

The repository root contains documentation, GitHub configuration, and two payload folders:

```
MDT-Zero-Touch-Deployment/
├── DeploymentShare/                 The contents to merge into your MDT deployment share
│   ├── Boot/
│   │   └── Addon/x64/               Bundled 7-Zip for the WinPE boot image
│   ├── Control/                     Bootstrap.ini, CustomSettings.ini, Settings.xml, Medias.xml, task sequences
│   ├── Scripts/
│   │   ├── CopyOEM.wsf
│   │   └── Custom/                  Task sequence scripts
│   ├── x64/
│   │   └── $OEM$/                   x64 OEM content, Apps framework, activation, layout
│   └── x86/
│       └── $OEM$/                   x86 OEM content (monolith scripts, no framework)
├── MDT/
│   └── Content/Deploy/              Pre-built offline media set (SWM-split images)
├── Prerequisites/                   DHCP/WDS config templates, MDT Templates, AOMEI PXE Boot
├── docs/                            Detailed documentation
├── .github/                         Issue templates, PR template, funding, release notes
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE.md
├── README.md
└── .gitignore
```

The `DeploymentShare/` folder mirrors the layout MDT creates when you create a new deployment share. Merge its contents into your own share after creating it.

The x86 tree does not ship the Apps framework. It uses monolith scripts that are not part of this repository. See [Known Limitations](#known-limitations).

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
  • pbr.ps1           OEM Apps framework (SYSTEM phase)
        │
        ▼
  First logon → resume task → pbr.ps1 (USER phase)
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

## Known Limitations

- **Windows 10 end of support:** Windows 10 reached end of support on October 14, 2025. Win10 task sequences are for legacy hardware and existing deployments only.
- **Plaintext credentials:** `Control\Bootstrap.ini` stores credentials in cleartext. Use a least-privilege deployment account and restrict share permissions. Never commit real credentials.
- **AnyDesk password is hardcoded** in `pre.ps1` as `p@$$w0rd`. Change it before using AnyDesk outside an isolated lab.
- **MDT is no longer under active development.** This project targets MDT `6.3.8456.1000`.
- **Framework is x64-only.** The OEM Apps framework ships only in the x64 tree. The x86 tree uses monolith scripts that are not part of this repository. Post-deployment updates via `Update.xml` are x64-only.
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

The `MDT-Windows-Image-Builder` repository is where the deep guide for image creation lives. This repository expects you to already have a Windows `install.wim` (or an ISO containing one) to import into MDT.

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

MIT License — see [LICENSE.md](LICENSE.md).

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
```

Now `CONTRIBUTING.md` — same title fix needed there. Here it is:

```markdown
# Contributing to MDT Zero-Touch Deployment

First off — **thank you** for considering a contribution. This project exists because the MDT community shares knowledge, and every improvement (a new OEM pack, a bug fix, a documentation tweak) makes it more useful for everyone.

This document explains how to contribute effectively and what standards your contributions should meet.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Before You Start](#before-you-start)
- [Development Setup](#development-setup)
- [Script Standards](#script-standards)
- [Commit Message Convention](#commit-message-convention)
- [Branch Naming](#branch-naming)
- [Pull Request Process](#pull-request-process)
- [What Reviewers Look For](#what-reviewers-look-for)
- [Contributing to the Apps Framework](#contributing-to-the-apps-framework)
- [Areas Where Help Is Needed](#areas-where-help-is-needed)
- [Reporting Bugs](#reporting-bugs)
- [License of Contributions](#license-of-contributions)
- [Code of Conduct](#code-of-conduct)
- [Questions](#questions)

---

## Ways to Contribute

You don't have to write code to contribute. All of the following are valuable:

| Contribution Type | Examples |
|---|---|
| **Bug fixes** | Correcting a script that fails on a specific model, fixing a path typo, resolving a DISM error |
| **New scripts** | A new task sequence step, a new post-deployment cleanup script, a new driver detection routine |
| **OEM packs** | Driver packs or app archives for OEMs or models not yet covered |
| **Hardware support** | Intel VMD or AMD storage driver updates for newer CPU generations |
| **Framework contributions** | New OEM modules, manifest entries, or hook implementations for the Apps framework |
| **Documentation** | Clarifying a setup step, fixing a typo, adding a troubleshooting entry |
| **Testing** | Confirming a script works on your hardware and reporting the result |
| **Ideas** | Feature requests, workflow suggestions, or architectural feedback |

If you're unsure whether an idea is in scope, **open a [Discussion](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions) first** before investing time in a PR.

---

## Before You Start

### Check existing issues and PRs

Someone may already be working on the same thing. Search [open issues](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues) and [open PRs](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/pulls) before starting.

### Open an issue first for large changes

For anything beyond a typo or obvious bug fix — especially new scripts, task sequence changes, new OEM packs, or framework extensions — **open an issue to discuss the approach first**. This avoids wasted effort if the change does not fit the project's direction.

### Small, focused PRs are preferred

One logical change per PR. A PR that fixes a bug *and* adds a feature *and* reformats a script is hard to review and hard to revert if something goes wrong.

---

## Development Setup

To test your changes properly, you need a working MDT environment.

### Minimum requirements

- Windows Server (with DHCP + WDS) **or** Windows desktop (with AOMEI PXE Boot)
- Windows ADK for Windows 11 + Windows PE Addon
- Windows SDK for Windows 11
- Microsoft Deployment Toolkit `6.3.8456.1000`
- PowerShell 7 on the development host
- 7-Zip installed at `C:\Program Files\7-Zip\7z.exe`
- A target machine for testing (physical hardware strongly preferred over a VM for driver-related changes)

### Recommended workflow

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/MDT-Zero-Touch-Deployment.git
   ```
3. Set up a **test deployment share** separate from any production share
4. Merge the repository's `DeploymentShare/` contents into your test share
5. Test your changes end-to-end (PXE boot a client, complete a full deployment through OOBE, and if applicable, verify the framework phases)
6. Commit and push to your fork
7. Open a PR against the `main` branch

### Testing requirements by change type

| Change Type | Testing Required |
|---|---|
| Documentation only | None, but proofread carefully |
| Script bug fix | Reproduce the bug, apply the fix, verify it is resolved, confirm no regression |
| New task sequence script | Full deployment on at least one physical machine |
| Driver pack addition | Deploy to the target model and confirm drivers install |
| Task sequence change | Full deployment on both BIOS and UEFI, if applicable |
| VMD / storage driver change | Deploy to the target CPU generation |
| `pre.ps1` change | Full deployment through OOBE on at least one physical machine; verify the transcript at `C:\ProgramData\OEM\Logs\pre_*.log` |
| `SetupComplete.cmd` change | Full deployment through OOBE; verify all three child scripts run and log |
| Framework module change | Full deployment through both SYSTEM and USER phases; verify health check passes and convergence marker is written |
| OEM module change | Full deployment on hardware from that OEM; verify family detection and app installation |
| Manifest change | Full deployment on hardware from that OEM; verify the added/changed app installs and any pinning applies |

**State what hardware you tested on in the PR description.** "Tested on Dell Latitude 5430, BIOS mode, Win11 Pro x64" is far more useful than "tested and works."

---

## Script Standards

Scripts live in several execution contexts. The standards differ per context.

| Location | Execution Context | WMI/CIM | Registry Writes |
|---|---|---|---|
| `DeploymentShare\Scripts\Custom\` | WinPE | Only `Get-PhysicalDisk` via `winpe-storagewmi`; other WMI/CIM unavailable | `reg.exe` only |
| `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\` | Full OS (OOBE) | Available | `reg.exe` only |
| `DeploymentShare\<arch>\$OEM$\$1\Scripts\` | Full OS (interactive) | Available | `reg.exe` only |
| `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\Framework\` | Full OS (OOBE and first logon) | Available | `reg.exe` only, via `Registry.psm1` helpers |

### 1. WinPE-safe (for `Scripts\Custom\` only)

Scripts in `Scripts\Custom\` run in WinPE. WinPE is a stripped-down environment.

**Rules:**

- Use the registry and file system for hardware detection
- **Do not use `Get-CimInstance`, `Get-WmiObject`, or `Get-PhysicalDisk`** unless `winpe-storagewmi` and the Storage module are explicitly available in the boot image
- Do not assume `Get-Volume` returns a single result

```powershell
# BAD — WMI is not reliable in WinPE
$model = (Get-CimInstance Win32_ComputerSystem).Model

# GOOD — registry is always available
$model = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -Name SystemProductName).SystemProductName
```

Scripts in `$OEM$` and the Apps framework run in the full OS and are **exempt** from this rule.

### 2. Defensive volume and disk lookups

`Get-Volume`, `Get-Partition`, and `Get-Disk` can return multiple results on systems with multiple disks or duplicate labels. **Always pipe through `Select-Object -First 1`** or wrap in `@()` and check the count.

```powershell
# BAD — may return an array, breaks later string operations
$WindowsDrive = (Get-Volume -FileSystemLabel Windows).DriveLetter

# GOOD — deterministic single value
$WindowsDrive = (Get-Volume -FileSystemLabel Windows | Select-Object -First 1).DriveLetter
```

### 3. Retry logic for DISM and robocopy

Both tools fail intermittently. Wrap them in retry loops.

```powershell
$maxAttempts = 3
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    & DISM.exe /Image:"$ImagePath" /Add-Driver /Driver:"$DriverPath" /Recurse
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 5 }
}
```

### 4. Silent operation

Scripts in `Scripts\Custom\` run inside a task sequence. User-facing output disrupts the deployment UI.

- **No `Write-Host`** unless the message is diagnostic and critical
- **No `Write-Output`** unless the output is meant to be captured
- Redirect verbose tool output to `$null` or a log file
- Preserve `$LASTEXITCODE` — do not use `| Out-Null` on native commands if you need the exit code

Scripts in `$OEM$` and the framework may use `Write-Host` freely for progress reporting, because they run in OOBE or at first logon with no task sequence UI to disturb.

### 5. Preserve exit codes

Never mask a failure with a silent `try/catch` that swallows the error. If a script fails, the caller should know about it.

```powershell
# BAD — swallows the error
try { & dism.exe /Image:$Image /Add-Package /PackagePath:$Pkg } catch { }

# GOOD — check the exit code explicitly
& dism.exe /Image:$Image /Add-Package /PackagePath:$Pkg
if ($LASTEXITCODE -ne 0) {
    # log or fail visibly
}
```

### 6. Header documentation

Every script must begin with a comment block containing at minimum:

```powershell
<#
.SYNOPSIS
    One-line description of what the script does.

.DESCRIPTION
    Longer explanation including when this script runs in the task sequence
    and what preconditions it expects.

.NOTES
    - WinPE-safe: yes/no
    - External dependencies (7-Zip, network shares, USB labels)
    - Known limitations
#>
```

### 7. No hardcoded drive letters

Never hardcode `C:`, `D:`, and so on. Always discover via volume label.

```powershell
# BAD
$WindowsImage = "C:\"

# GOOD
$WindowsDrive = (Get-Volume -FileSystemLabel Windows | Select-Object -First 1).DriveLetter
$WindowsImage = "${WindowsDrive}:\"
```

### 8. Path fallbacks

Scripts that read from network shares should fall back to a DEPLOY-labeled USB drive, matching the pattern used in `ApplyUpdates*.ps1` and `ExtractOEM*.ps1`.

### 9. Registry writes via `reg.exe` only

This rule applies project-wide. Never use `New-ItemProperty` or the PowerShell Registry Provider for writes. The provider's handle retention blocks offline-hive unload, and a policy that requires per-site reasoning is a policy the next write site will violate. Reads via the provider are permitted.

```powershell
# BAD — provider write
New-ItemProperty -Path $Key -Name $Name -Value $Value -Force

# GOOD — reg.exe write
& reg.exe add $Key /v $Name /t REG_SZ /d $Value /f
```

In the Apps framework, use the `Registry.psm1` helpers (`Set-RegistryValueSilent`, `Set-OfflineHiveValueSet`).

### 10. PowerShell 5.1 compatibility

Scripts must run under the WinPE and Windows OOBE versions of PowerShell, which are **5.1**. Do not use syntax or cmdlets exclusive to PowerShell 7 (ternary operator `? :`, `??`, `-Parallel`).

### 11. No `exit` in task sequence scripts

Task sequence scripts should return rather than `exit`, so the task sequence can capture failures. Scripts invoked from `SetupComplete.cmd` are standalone and may use `exit`.

### 12. Idempotence

Scripts that run repeatedly (framework phases, `pre.ps1`, orchestration scripts) must be idempotent. Re-running them must not produce different outcomes, duplicate files, or regressions.

---

## Commit Message Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). This makes the changelog easier to generate and clarifies what each commit does.

### Format

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

### Types

| Type | Use For |
|---|---|
| `feat` | A new feature or new script |
| `fix` | A bug fix |
| `docs` | Documentation changes only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Maintenance (dependency bumps, formatting, build changes) |
| `revert` | Reverting a previous commit |

### Scopes (optional but recommended)

Use the script name or area affected:

- `apply-drivers`, `apply-updates`, `winre`, `disk`, `oem`, `lgpo`, `pre`, `setupcomplete`
- `framework`, `manifest`, `oem-module`, `layout`, `winget`
- `docs`, `readme`, `changelog`

### Examples

```
feat(apply-drivers): add support for 14th Gen Intel VMD
fix(winre): persist VMD marker on target OS drive
docs(setup): clarify WDS boot image import steps
refactor(disk): use Select-Object -First 1 for volume lookups
feat(oem-module): add OEM.Samsung module
```

### Breaking changes

If a change breaks existing deployments, add `!` after the type/scope and include a `BREAKING CHANGE:` footer:

```
feat(apply-updates)!: require OSDVersion task sequence variable

BREAKING CHANGE: ApplyUpdates11.ps1 now reads the OSDVersion task
sequence variable to pick the update source folder. Update your task
sequences to set OSDVersion before upgrading.
```

---

## Branch Naming

Use a prefix that matches the commit type:

| Prefix | Use For |
|---|---|
| `feature/` | New features or new scripts |
| `fix/` | Bug fixes |
| `docs/` | Documentation changes |
| `refactor/` | Code refactoring |
| `chore/` | Maintenance |

Examples:

- `feature/intel-vmd-14th-gen`
- `fix/winre-marker-persistence`
- `docs/troubleshooting-section`
- `feature/oem-samsung-module`

---

## Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main` using the naming convention above
3. **Make your changes** following the script standards
4. **Update `CHANGELOG.md`** — add your change under `[Unreleased]` in the appropriate section (`Added`, `Changed`, `Fixed`, `Removed`, `Security`)
5. **Test end-to-end** on real hardware where applicable
6. **Push** to your fork
7. **Open a PR** against `main` with:
   - A clear title matching the Conventional Commits format
   - A description of **what** changed and **why**
   - The **hardware and OS** you tested on
   - A **link to the related issue** if one exists
   - Screenshots or log excerpts if relevant

### PR title format

Match your commit message convention:

```
feat(apply-drivers): add support for 14th Gen Intel VMD
```

### What makes a good PR description

```markdown
## Summary
Adds support for 14th Gen Intel VMD drivers, which use a newer
version than 11th-13th Gen.

## Changes
- Updated `Get-IntelVMDVersion` in ApplyOEMDrivers.ps1
- Added 14th Gen to the generation map
- Updated LoadWinPEDrivers.ps1 to use the new version

## Testing
- Tested on HP EliteBook 840 G11, UEFI, Win11 Pro x64
- Full deployment completed successfully through OOBE
- VMD driver version 20.2.6.1025.3 loaded in WinPE

## Related Issue
Closes #42

## Checklist
- [x] Follows script standards
- [x] CHANGELOG.md updated under [Unreleased]
- [x] Tested on real hardware
- [x] No hardcoded drive letters
- [x] Retry logic for DISM/robocopy
- [x] Registry writes via reg.exe only
```

---

## What Reviewers Look For

When reviewing a PR, the maintainer checks:

| Item | Why |
|---|---|
| **WinPE safety** | No WMI/CIM in `Scripts\Custom\` unless a FeaturePack provides it |
| **Defensive lookups** | `Select-Object -First 1` on volume and disk commands |
| **Retry logic** | DISM and robocopy operations retry on failure |
| **Silent operation** | No spurious output in task sequence scripts |
| **Exit code preservation** | Failures are visible to the caller |
| **Header documentation** | SYNOPSIS, DESCRIPTION, NOTES block present |
| **CHANGELOG entry** | Added under `[Unreleased]` |
| **No drive letter hardcoding** | Paths discovered via volume labels |
| **PowerShell 5.1 compatible** | No PS7-only syntax |
| **Registry write discipline** | All writes via `reg.exe` or framework helpers |
| **Idempotence** | Repeated runs produce the same outcome |
| **Tested on hardware** | PR description states the hardware used |
| **Small, focused scope** | One logical change per PR |

---

## Contributing to the Apps Framework

The Apps framework — `pbr.ps1`, the `Framework\` modules, the `OEM\` modules, and the `Manifests\` files — has additional standards beyond those above.

### Before you write code

Read [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md) end to end. It defines the contract between the framework, OEM modules, and manifests.

### Additional rules

- **Framework modules must not be edited lightly.** They are stable interfaces. If you believe a framework module needs a change, open an issue first and describe the reason.
- **OEM modules must not write the registry directly.** Use the helpers exported by `Registry.psm1`.
- **OEM modules must not manage the scheduled task directly** unless overriding `RegisterResumeTask`.
- **OEM modules must not write stage markers directly.** Use `Set-DeploymentStage`.
- **OEM modules must not log outside `LogDirectory`.** Use `Write-DeploymentLog`.
- **Manifest additions must not introduce required fields.** Framework consumers read only the fields they know about; every other field must be optional with a documented default.

### Adding a new OEM module

1. Create `OEM\OEM.<Brand>.psm1` with at least a `Get-OEMProfile` function
2. Create `Manifests\<Brand>.json` with the app list
3. Ensure the profile's `Name` matches the module filename
4. Ensure the profile's `ManifestFile` matches the manifest filename
5. Ensure the profile's `MarkerRegistryPath` is distinct from every other OEM's
6. Test on hardware from that OEM
7. Update the OEM modules table in [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md)

### Canonical framework documentation

The framework has its own design and reference documentation, maintained separately from this repository. Before making changes that affect framework invariants, ensure your change is consistent with the canonical docs. If it is not, open an issue to discuss before submitting a PR.

The framework's canonical docs are not shipped here. This repository ships the framework code and a user-facing overview in [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md).

---

## Areas Where Help Is Needed

Some specific things the maintainer would love help with:

### 1. OEM license edition detection

A script that reads the OEM digital license from the BIOS (`OA3xOriginalProductKeyDescription`), determines the licensed edition (for example, Home Single Language, Home, Pro), and sets the deployed OS edition to match during deployment.

Currently, `pre.ps1` activates only if the OEM license is Professional. Non-Pro licenses are not applied, and LGPO policies are applied regardless of edition.

**Where to hook in:** `$OEM$\$1\Recovery\OEM\pre.ps1` and the task sequence State Restore phase.

### 2. x86 framework support

The x86 tree does not have the Apps framework. It uses monolith scripts that are not part of this repository. Contributing an x86 framework implementation, or documenting the x86 monolith scripts, would close a significant gap.

### 3. Additional OEM packs

Driver packs and app archives for:

- Panasonic Toughbook
- Fujitsu LifeBook
- Samsung / LG laptops
- Toshiba Dynabook (existing pack needs updating)
- Clevo / Tongfang / XMG / Schenker

### 4. Newer Intel and AMD storage drivers

- Intel VMD for 14th Gen and beyond (Meteor Lake, Arrow Lake)
- AMD RAID / NVMe drivers for Ryzen 7000, 8000, 9000 series

### 5. Script improvements

- Refactoring `pre.ps1` into smaller modules
- Fixing the `Get-OSFamily` hardcoded `Win11` bug in `ExtractOEMDrivers.ps1`
- Adding a `-DryRun` mode to destructive scripts (`CleanFixedDrives.ps1`, `FormatDataDrive.ps1`)
- Adding structured logging to a file alongside the existing logs

### 6. Documentation

- Expanding `docs/TROUBLESHOOTING.md` with real-world error scenarios
- Adding a "known working hardware" table to the README
- Adding screenshots to the setup guide
- Authoring the companion repository [`MDT-Windows-Image-Builder`](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) content

If any of these interest you, **open a Discussion first** so we can scope it together.

---

## Reporting Bugs

Found a bug? [Open an issue](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues/new) with:

- **Description** — what you expected vs. what happened
- **Steps to reproduce** — exact task sequence step, phase, or command
- **Hardware** — make, model, CPU, BIOS/UEFI mode
- **OS being deployed** — Win10 x64 / Win10 x86 / Win11 x64
- **Relevant log file** — MDT logs are in `X:\MININT\SMSOSD\OSDLOGS\` (WinPE) or `C:\MININT\SMSOSD\OSDLOGS\` (full OS) during deployment; OEM logs are in `C:\ProgramData\OEM\Logs\` after OOBE
- **Screenshots** if applicable

**Please don't paste full logs inline** — attach them as files or link to a Gist.

---

## License of Contributions

By submitting a pull request to this project, you agree that your contribution is licensed under the same [MIT License](LICENSE.md) that governs the project.

You confirm that:

- You have the right to submit the contribution
- The contribution is your original work, or you have obtained permission to submit it under the MIT License
- Any third-party code included in your contribution is compatible with the MIT License and clearly attributed

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

In short: be respectful, be patient, assume good faith, and focus on the technical problem. Harassment, personal attacks, and dismissive behavior are not tolerated. Violations can be reported to the maintainer via a [private GitHub security advisory](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/security/advisories/new).

---

## Questions?

- **General questions or ideas:** [GitHub Discussions](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions)
- **Bug reports:** [GitHub Issues](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues)
- **Security vulnerabilities:** [Private security advisory](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/security/advisories/new)
- **Direct contact:** See the [author's GitHub profile](https://github.com/ArthurJDurand)

---

## Thank You

Whether you submit a driver pack, fix a typo, or report a bug on a machine you have access to — **your contribution matters**. This project is built on community knowledge, and every improvement helps someone deploy Windows a little faster.

Thank you for being part of it.

---

<div align="center">

**Happy deploying!** 🚀

</div>
