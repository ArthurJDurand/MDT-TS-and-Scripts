# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning Policy

Because this is a deployment framework, version numbers have specific meaning for users:

| Bump | Meaning | Examples |
|---|---|---|
| **MAJOR** | Breaking changes that require you to update your deployment share, task sequences, or configuration. Existing deployments may fail without intervention. | New required task sequence variable, changed script interface, changed directory structure, removal of a task sequence |
| **MINOR** | New functionality that is backward-compatible. Safe to pull and regenerate boot images without breaking existing setups. | New OEM pack support, new script, new hardware generation support, new task sequence |
| **PATCH** | Bug fixes, driver version updates, and documentation improvements. Safe to pull at any time. | Script bug fix, VMD version bump, README typo, LGPO policy update |

**When upgrading across MAJOR versions, read the migration notes in the release description.**

---

## [Unreleased]

### Added

### Changed

### Fixed

### Removed

### Security

---

## [1.0.0] - YYYY-MM-DD

Initial public release.

### Added

#### Task Sequences

- `WIN11PROX64` — Windows 11 Pro (64-bit) deployment task sequence
- `WIN10PROX64` — Windows 10 Pro (64-bit) deployment task sequence
- `WIN10PROX86` — Windows 10 Pro (32-bit) deployment task sequence for legacy hardware

#### Task Sequence Scripts (`DeploymentShare\Scripts\Custom\`)

- `LoadWinPEDrivers.ps1` — Loads the correct Intel VMD storage driver in WinPE when internal storage is not detected. Writes a marker file (`VMD_Loaded.txt`) so downstream scripts know VMD was required.
- `CleanFixedDrives.ps1` — Wipes all internal (non-USB) drives using `Clear-Disk -RemoveData -RemoveOEM`.
- `SetTargetOSDisk.ps1` — Selects the first NVMe SSD, or first SATA SSD, or first non-USB disk as the target OS disk. Sets `OSDDiskIndex` for the partition steps.
- `CreateRecoveryPartition-BIOS.ps1` — Shrinks the Windows partition and creates a BIOS recovery partition (ID 27, NTFS).
- `CreateRecoveryPartition-UEFI.ps1` — Shrinks the Windows partition and creates a UEFI recovery partition (GUID `de94bba4-06d1-4d40-a16a-bfd50179d6ac`, GPT attributes `0x8000000000000001`).
- `FormatDataDrive.ps1` — Formats any additional raw internal disk as a GPT Data drive with a 128 MB MSR partition.
- `ApplyUpdates10x64.ps1` — Injects Windows 10 x64 updates (`.cab`/`.msu`) into the offline image via DISM.
- `ApplyUpdates10x86.ps1` — Injects Windows 10 x86 updates into the offline image via DISM.
- `ApplyUpdates11.ps1` — Injects Windows 11 updates into the offline image via DISM.
- `ExtractOEMAppsx64.ps1` — Extracts manufacturer-specific app `.7z` archives from `\\SERVER\Shared\OEM\x64` or a DEPLOY USB to `C:\Recovery\OEM`.
- `ExtractOEMAppsx86.ps1` — x86 variant of the OEM app extraction.
- `ExtractOEMDrivers.ps1` — Extracts the model-specific driver `.7z` archive from `\\SERVER\Shared\DriverPacks` or a DEPLOY USB to `C:\Recovery\OEM\Drivers`.
- `ApplyOEMDrivers.ps1` — Applies extracted OEM, WLAN, and Intel VMD drivers to the offline Windows image via DISM.
- `WinRE.ps1` — Deploys and configures WinRE on the recovery partition, optionally injecting VMD drivers when a marker file is present.
- `CleanupScripts.ps1` — Removes MDT artifacts (`_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`) after deployment.
- `CopyOEM.wsf` — Copies `$OEM$\$1` and `$OEM$\$$` content from the deployment share to the target OS (based on Michael Niehaus's original script).

#### OEM Setup and Orchestration

- `SetupComplete.cmd` — Runs at the end of OOBE. Orchestrates `pre.ps1`, `Customizations.ps1`, and `pbr.ps1` in sequence, then cleans up MDT artifacts and sets hidden attributes on the Default user profile folders. An identical copy exists at `$1\Recovery\OEM\SetupComplete.cmd` for restoration by `AfterImage.cmd` during PBR.

#### OEM Configuration

- `pre.ps1` — Runs during `SetupComplete.cmd`. Installs OEM drivers, WLAN, Intel VMD, applies LGPO, activates Windows and Office, installs third-party applications (7-Zip, WinRAR, AnyDesk, RustDesk, DymaxIO on x64 / Diskeeper on x86, Acronis Drive Monitor), configures the OEM\Update scheduled task on x64, sets system attributes, and cleans up. Maintains its own inline version history.
- `Customizations.ps1` — Runs after `pre.ps1` for OEM branding and offline hive hardening.
- `pbr.ps1` — Runs after `Customizations.ps1` in SYSTEM context. Entry point for the OEM Apps framework (x64 only).

#### OEM Apps Framework (`x64\$OEM$\$1\Recovery\OEM\Apps\`)

A two-phase deployment engine for OOBE-era machines. Ships only in the x64 tree.

- **Framework modules** (`Framework\`) — Ten PowerShell modules:
  - `State.psm1` — per-run context and hardware detection
  - `Logging.psm1` — unified log output
  - `Registry.psm1` — registry helpers with `reg.exe`-only write discipline
  - `AppDetection.psm1` — application presence detection with five independent caches
  - `WinGet.psm1` — winget invocation engine (USER phase only)
  - `LocalInstall.psm1` — MSI, MSP, EXE, CMD, AppX, MSIX, and bundle installer handling
  - `Layout.psm1` — Start and taskbar layout generation
  - `ScheduledTask.psm1` — resume task lifecycle
  - `Health.psm1` — post-USER-phase health check
  - `Engine.psm1` — orchestration entry points
- **OEM modules** (`OEM\`) — Eleven vendor-specific modules:
  - `OEM.ASUS.psm1`, `OEM.Acer.psm1`, `OEM.Dell.psm1`, `OEM.Dynabook.psm1`, `OEM.Gigabyte.psm1`, `OEM.HP.psm1`, `OEM.Huawei.psm1`, `OEM.Lenovo.psm1`, `OEM.MSI.psm1`, `OEM.Proline.psm1`, `OEM.Surface.psm1`
- **Manifests** (`Manifests\`) — Eleven JSON manifests, one per OEM. `Gigabyte.json` and `Proline.json` ship as empty stubs; their modules exist for family detection and future expansion.
- **Two-phase model** — SYSTEM phase runs at OOBE (local installers only), USER phase runs at first logon (winget + local). Phase ordering is permissive.
- **Stage markers** — `SYSTEM_DONE` and `USER_DONE` convergence markers under a per-OEM registry path.
- **Health check** — post-USER-phase verification that all expected apps are present.
- **Layout generation** — automatic unless `C:\Recovery\AutoApply` is present.

See [docs/APPS-FRAMEWORK.md](docs/APPS-FRAMEWORK.md) for the full framework reference.

#### OEM Activation

- `HWID_Activation.cmd` — HWID-based Windows activation fallback used when the firmware OEM key activation fails.
- Office activation via Ohook is supported by `pre.ps1` if a user-supplied `Ohook_Activation.cmd` is present at `C:\Recovery\OEM\Activation\`. **This script is not distributed with the repository.** Users who require Ohook activation supply their own copy. `pre.ps1` calls it only after confirming no Office application is running in an interactive user session.

#### OEM Application Configurators

- `RustDesk.ps1` — Applies RustDesk configuration after installation.
- `DymaxIOLicense.ps1` — Applies the DymaxIO license (x64 tree only).
- `DiskeeperLicense.ps1` — Applies the Diskeeper license (x86 tree only).
- `AnyDesk.cmd` — Configures AnyDesk after installation.
- `Update.xml` — Task Scheduler definition for the `OEM\Update` scheduled task (x64 tree only). Performs monthly post-deployment updates.

#### OEM Layout Files

- `LayoutModification.xml` — Base Start menu layout for Windows 10.
- `TaskbarLayoutModification.xml` — Base taskbar layout for Windows 11.

#### Local Group Policy (LGPO)

- LGPO tool integration with preconfigured policies covering Windows Update configuration, Microsoft Defender Antivirus configuration, AutoPlay behavior, and power management.
- LGPO application via `pre.ps1` during OOBE.
- `LGPO.exe` and policy backup ship in both `x64` and `x86` trees.

#### PBR Extensibility Chain

- `ResetConfig.xml` — Windows PBR configuration. Hooks `PreImage.cmd` and `AfterImage.cmd` into four reset phases.
- `PreImage.cmd` — No-op placeholder for the `BeforeImageApply` hook.
- `AfterImage.cmd` — Runs after the PBR image is applied. Creates folders, copies `SetupComplete.cmd` to `Windows\Setup\Scripts`, and copies `unattend.xml` to `Windows\Panther`.
- `preWINRE.cmd` (x64) / `PreWinRE.cmd` (x86) — Loads boot-critical drivers via `drvload` during WinRE startup. Casing differs between architectures per the PBR extensibility contract.
- `ResetPartitions.txt` — Diskpart script for factory reset. Creates EFI (260 MB), MSR (128 MB), Windows, and Recovery partitions on GPT.
- `unattend.xml` — OOBE unattend restored to `Windows\Panther` by `AfterImage.cmd` after a PBR reset.

#### Post-Deployment Scripts (`$OEM$\$1\Scripts\`)

Numbered CMD scripts run manually by the technician after OOBE. Number prefix indicates order; restarts are required between `1Firstrun.cmd` and `2Secondrun.cmd`, and after `2Secondrun.cmd`.

- `0CleanWindowsUpdates.cmd` — Cleans the Windows component store after updates.
- `0Install-AnyDesk.cmd` — Installs AnyDesk interactively (x64 tree only).
- `0KeepAwake.cmd` — Prevents sleep during long-running maintenance.
- `1Firstrun.cmd` — Interactive first pass: Windows Update, OEM utility setup, GPU software.
- `2Secondrun.cmd` — Interactive second pass after restart: final updates and marker decisions.
- `3OEMDriversExport.cmd` — Exports drivers to `\\SERVER\Shared\DriverPacks` or a DEPLOY-labeled USB at `X:\DriverPacks`.
- `4ScanState.cmd` — Captures a PBR provisioning package at `C:\Recovery\Customizations` and populates `C:\Recovery\AutoApply`. The ScanState tooling itself is downloaded from a companion Gist at run time rather than shipped in this repository.

#### Dynamic Driver Support

- Intel VMD storage driver loading for 10th/11th Gen+ Intel platforms.
- CPU generation detection via registry (WinPE-safe), supporting classic Core i-series, Intel Core Ultra, Intel Xeon, new Core (non-i), and AMD Ryzen.
- Manufacturer and model detection via registry (`HKLM:\HARDWARE\DESCRIPTION\System\BIOS`).
- Model matching with support for Dell, HP, Lenovo, Acer, ASUS, MSI, Gigabyte, Huawei, Dynabook, Microsoft, and Proline.

#### Third-Party Applications Installed by `pre.ps1`

- 7-Zip (silent)
- WinRAR (silent, with registry configuration)
- AnyDesk (silent, with permanent password)
- RustDesk (silent, with external configuration script)
- DymaxIO (x64) / Diskeeper (x86), with external licensing script
- Acronis Drive Monitor (installed only when a spinning HDD is detected)
- Microsoft Office 365 (installed from `C:\Recovery\OEM\Apps\Office365`)

#### Windows AppX Packages Provisioned by `pre.ps1`

- Microsoft.Todos
- Microsoft.OutlookForWindows (Windows 10 only)
- Microsoft.BingNews (Windows 10 only)
- Media extensions: AV1, HEIF, HEVC, MPEG2, RawImage, VP9, WebMedia, Webp

#### Offline Media

- Media sets are generated on demand by the Deployment Workbench from the user's own deployment share, then copied to a FAT32 DEPLOY-labeled USB flash drive.
- Boot image, OS images, task sequences, and scripts are copied automatically by MDT.
- The OEM payload is copied to the USB from the network shares the deployment share expects.
- See [docs/OFFLINE-MEDIA.md](docs/OFFLINE-MEDIA.md) for the full workflow.

#### Prerequisites Bundle (`Prerequisites\`)

- `All MDT Fixes 2025.exe` — Self-extracting archive containing ADK fixes, WinPE Addon updates, MDT template patches, and the fixes for KB4564442 and the HTA Script Error on Windows Server.
- `for Desktop Editions of Windows\AOMEI PXE Boot Free 1.5\PXEBoot.exe` — AOMEI PXE Boot installer for desktop-based deployment.
- `for Windows Server\Configs\DHCP Server.xml` — DHCP Server configuration template.
- `for Windows Server\Configs\DeploymentConfigTemplate.xml` — Windows Server role configuration template.
- `for Windows Server\Configs\WDS Server.xml` — WDS Server configuration template.

#### Boot Image Add-Ons

- `Boot\Addon\x64\Program Files\7-Zip\` — Full 7-Zip installation bundled for the x64 WinPE boot image. Required by `ApplyOEMDrivers.ps1`, `ExtractOEMDrivers.ps1`, and `ExtractOEMApps*.ps1`.
- `Boot\Addon\x86\Program Files\7-Zip\` — Full 7-Zip installation bundled for the x86 WinPE boot image.

#### MDT Stock Content

- `DeploymentShare\Templates\Unattend_PE_x64.xml` — Stock MDT unattend template for WinPE.
- `DeploymentShare\Tools\x64\Bginfo64.exe` — BGInfo for x64, used by stock MDT to write system information to the desktop wallpaper.
- `DeploymentShare\Tools\x64\microsoft.bdd.utility.dll` — MDT utility library (x64).
- `DeploymentShare\Tools\x86\Bginfo.exe` — BGInfo for x86.
- `DeploymentShare\Tools\x86\microsoft.bdd.utility.dll` — MDT utility library (x86).

#### Documentation

- `README.md` — Project overview, features, quick start, and documentation index.
- `docs/SETUP.md` — Full server and desktop setup walkthrough.
- `docs/SCRIPTS.md` — Reference for every script in the repository.
- `docs/APPS-FRAMEWORK.md` — OEM Apps framework reference.
- `docs/OEM.md` — OEM driver pack and app archive structure.
- `docs/OFFLINE-MEDIA.md` — DEPLOY USB creation walkthrough.
- `docs/WINDOWS-MEDIA.md` — Obtaining or building a Windows installation image.
- `docs/TROUBLESHOOTING.md` — Common errors and fixes.
- `CONTRIBUTING.md` — Contribution guidelines and script standards.
- `CHANGELOG.md` — This file.
- `CODE_OF_CONDUCT.md` — Contributor Covenant Code of Conduct.

#### Repository Infrastructure

- `LICENSE` — MIT License.
- `.gitignore` — Ignore rules reflecting the intentional binary exceptions.
- `.gitattributes` — Line-ending and encoding rules per file type.
- `.github/FUNDING.yml` — GitHub Sponsors configuration.
- `.github/release.yml` — Auto-categorized release notes from PRs.
- `.github/ISSUE_TEMPLATE/bug_report.yml` — Bug report template.
- `.github/ISSUE_TEMPLATE/feature_request.yml` — Feature request template.
- `.github/PULL_REQUEST_TEMPLATE.md` — Pull request template.

### Security

- Documented that `Control\Bootstrap.ini` stores credentials in plaintext and requires a least-privilege deployment account with restricted share permissions.
- Documented that `pre.ps1` contains a hardcoded `$AnyDeskPassword` that must be changed before use in any non-lab environment.
- Office activation via Ohook is gated by `Test-OfficeSafeForActivation`, which fails closed if any Office application is running in an interactive user session or if the process list cannot be enumerated. The Ohook activation script itself is not distributed with this repository.
- Windows activation via `Activate-Windows` captures `/ipk` and `/ato` exit codes separately and falls through to HWID activation if the firmware-key path fails.
- All registry writes in the Apps framework go through `reg.exe` exclusively. The PowerShell Registry Provider is used for reads only.

### Known Limitations at Release

- Framework ships only in the x64 tree. The x86 tree uses a monolithic `pre.ps1` with no manifest-driven module system.
- `ExtractOEMDrivers.ps1` hardcodes the OS family to Win11 when resolving the driver pack path.
- VMD driver versions are hardcoded for specific CPU generations.
- `Update.xml` post-deployment updates are x64-only.
- `pre.ps1` is a large monolith (68 KB x64, 45 KB x86).

---

[Unreleased]: https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/releases/tag/v1.0.0
