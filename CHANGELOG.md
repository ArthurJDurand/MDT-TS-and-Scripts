# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning Policy

Because this is a deployment framework, version numbers have specific meaning for users:

| Bump | Meaning | Examples |
|---|---|---|
| **MAJOR** | Breaking changes that require you to update your deployment share, task sequences, or configuration. Existing deployments may fail without intervention. | New required TS variable, changed script interface, changed directory structure, removal of a task sequence |
| **MINOR** | New functionality that is backward-compatible. You can pull and re-generate boot images without breaking existing setups. | New OEM pack support, new script, new hardware generation support, new task sequence |
| **PATCH** | Bug fixes, driver version updates, and documentation improvements. Safe to pull at any time. | Script bug fix, VMD version bump, README typo, LGPO policy update |

**When upgrading across MAJOR versions, always read the migration notes in the release description.**

---

## [Unreleased]

---

## [1.0.0] - YYYY-MM-DD

Initial public release.

### Added

#### Task Sequences

- `WIN11PROX64` — Windows 11 Pro (64-bit) deployment task sequence
- `WIN10PROX64` — Windows 10 Pro (64-bit) deployment task sequence
- `WIN10PROX86` — Windows 10 Pro (32-bit) deployment task sequence for legacy hardware

#### Task Sequence Scripts (`Scripts\Custom\`)

- `LoadWinPEDrivers.ps1` — Loads the correct Intel VMD storage driver in WinPE when internal storage is not detected. Writes a marker file (`VMD_Loaded.txt`) so downstream scripts know VMD was required.
- `CleanFixedDrives.ps1` — Wipes all internal (non-USB) drives using `Clear-Disk -RemoveData -RemoveOEM`.
- `SetTargetOSDisk.ps1` — Selects the first NVMe SSD, or first SATA SSD, or first non-USB disk as the target OS disk. Sets `OSDDiskIndex` for the partition steps.
- `CreateRecoveryPartition-BIOS.ps1` — Shrinks the Windows partition and creates a BIOS recovery partition (ID 27, NTFS).
- `CreateRecoveryPartition-UEFI.ps1` — Shrinks the Windows partition and creates a UEFI recovery partition (GUID `de94bba4-06d1-4d40-a16a-bfd50179d6ac`, GPT attributes `0x8000000000000001`).
- `FormatDataDrive.ps1` — Formats any additional raw internal disk as a GPT Data drive with a 128 MB MSR partition.
- `ApplyUpdates10x64.ps1` — Injects Windows 10 x64 updates (`.cab`/`.msu`) into the offline image via DISM.
- `ApplyUpdates10x86.ps1` — Injects Windows 10 x86 updates into the offline image via DISM.
- `ApplyUpdates11.ps1` — Injects Windows 11 updates into the offline image via DISM.
- `ExtractOEMAppsx64.ps1` — Extracts manufacturer-specific app `.7z` archives from `\\SERVER\OEM\x64` or a DEPLOY USB to `C:\Recovery\OEM`.
- `ExtractOEMAppsx86.ps1` — x86 variant of the OEM app extraction.
- `ExtractOEMDrivers.ps1` — Extracts the model-specific driver `.7z` archive from `\\SERVER\Shared\DriverPacks` or a DEPLOY USB to `C:\Recovery\OEM\Drivers`.
- `ApplyOEMDrivers.ps1` — Applies extracted OEM, WLAN, and Intel VMD drivers to the offline Windows image via DISM.
- `WinRE.ps1` — Deploys and configures WinRE on the recovery partition, optionally injecting VMD drivers when a marker file is present.
- `CleanupScripts.ps1` — Removes MDT artifacts (`_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`) after deployment.
- `CopyOEM.wsf` — Copies `$OEM$\$1` and `$OEM$\$$` content from the deployment share to the target OS (based on Michael Niehaus's original script).

#### `$OEM$` Orchestration Scripts (`$OEM$\$$\\Setup\`)

- `SetupComplete.cmd` — Runs at the end of OOBE. Orchestrates `pre.ps1`, `Customizations.ps1`, and `pbr.ps1` in sequence, then cleans up MDT artifacts and sets hidden attributes on the Default user profile.

#### `$OEM$` Configuration Scripts (`$OEM$\$1\Recovery\OEM\`)

- `pre.ps1` — Runs during `SetupComplete.cmd`. Installs OEM drivers, WLAN, Intel VMD, applies LGPO, activates Windows and Office, installs third-party applications (7-Zip, WinRAR, AnyDesk, RustDesk, DymaxIO, Acronis Drive Monitor), configures the OEM\Update scheduled task, and sets system attributes. Maintains its own inline version history (currently v2.2.0).
- `Customizations.ps1` — Runs after `pre.ps1` for additional OEM customizations.
- `Apps\pbr.ps1` — Runs after `Customizations.ps1` to create the push-button reset provisioned package.

#### `$OEM$` Activation Scripts (`$OEM$\$1\Recovery\OEM\Activation\`)

- `HWID_Activation.cmd` — HWID-based Windows activation fallback used when the firmware OEM key fails.
- `Ohook_Activation.cmd` — Office activation via Ohook. Called by `pre.ps1` only after `Test-OfficeSafeForActivation` confirms no Office application is running in an interactive user session.

#### `$OEM$` Payload Updater Scripts (`$OEM$\$1\Recovery\OEM\`)

- `Apps.ps1` — Downloads the latest Apps `.7z` split archive from the companion `Update-PBR-Extensibility-Apps` repository, verifies SHA-256 against a GitHub Gist, and extracts to `C:\Recovery\OEM\Apps`.
- `Drivers.ps1` — Downloads the latest Drivers `.7z` split archive from the companion `Update-PBR-Extensibility-Drivers` repository, verifies SHA-256 against a GitHub Gist, and extracts to `C:\Recovery\OEM\Drivers`.
- `LGPO.ps1` — Downloads the latest `LGPO.7z` from the companion `Update-PBR-Extensibility-LGPO` repository, verifies SHA-256 against a GitHub Gist, and extracts to `C:\Recovery\OEM\LGPO`.

#### `$OEM$` Application Configurators (`$OEM$\$1\Recovery\OEM\Apps\`)

- `RustDesk.ps1` — Applies RustDesk configuration after installation (password, relay server, persistence).
- `DymaxIOLicense.ps1` — Applies the DymaxIO license after installation. Returns exit code 2 if DymaxIO is not present.
- `Update.xml` — Task Scheduler definition imported by `pre.ps1` as the `OEM\Update` scheduled task.

#### `$OEM$` Post-Deployment Scripts (`$OEM$\$1\Scripts\`)

- `OEMDriversExport.ps1` — Exports drivers from the deployed OS, archives them as `.7z`, and copies to `\\SERVER\Shared\DriverPacks` or a DEPLOY USB.
- `ScanWindowsImage64.ps1` — Cleans the Driver Store and restores the `Microsoft-OneCore-DirectX-Database-FOD-Package`.
- `ScanStatex64.ps1` — Creates a provisioned package for push-button reset using USMT `ScanState`.

#### Dynamic Driver Support

- Intel VMD storage driver loading for 10th/11th Gen+ Intel platforms
- CPU generation detection via registry (WinPE-safe), supporting:
  - Classic Core i-series (i3/i5/i7/i9)
  - Intel Core Ultra (Series 1 and 2)
  - Intel Xeon (W/E series)
  - New Core (Core 3/5/7/9, non-i)
  - AMD Ryzen (with brand and series detection)
- Manufacturer and model detection via registry (`HKLM:\HARDWARE\DESCRIPTION\System\BIOS`)
- Model matching with support for Dell, HP, Lenovo, Acer, ASUS, MSI, Gigabyte, Huawei, Dynabook, Microsoft, and Proline

#### OEM App Packs

- Dell OEM app pack (extensibility points as base)
- HP OEM app pack
- Lenovo OEM app pack
- Additional vendor packs as available in the shared OneDrive folder

#### Third-Party Applications Installed by `pre.ps1`

- 7-Zip (silent)
- WinRAR (silent, with registry configuration)
- AnyDesk (silent, with permanent password — see Security)
- RustDesk (silent, with external configuration script)
- DymaxIO (silent, with external licensing script)
- Acronis Drive Monitor (installed only when a spinning HDD is detected)
- Microsoft Office (installed from `C:\Recovery\OEM\Apps\Office*`, activated via Ohook)

#### Windows AppX Packages Provisioned by `pre.ps1`

- Microsoft.Todos
- Microsoft.OutlookForWindows (Windows 10 only)
- Microsoft.BingNews (Windows 10 only)
- Media extensions: AV1, HEIF, HEVC, MPEG2, RawImage, VP9, WebMedia, Webp

#### Local Group Policy (LGPO)

- LGPO tool integration with preconfigured policies covering:
  - Windows Update configuration (automatic updates, wake timers, restart behavior)
  - Microsoft Defender Antivirus configuration (cloud protection, MAPS, PUA detection)
  - AutoPlay behavior
  - Power management
- LGPO application via `pre.ps1` during OOBE
- LGPO tool delivered via `LGPO.ps1` updater from the companion repository

#### Configuration

- `Control\Bootstrap.ini` — WinPE bootstrap configuration with server, credentials, and domain
- `Control\CustomSettings.ini` — Zero-touch rules (skips wizards, sets `NEWCOMPUTER`, shuts down after deployment)
- `Control\Settings.xml` — Deployment share settings with FeaturePacks for WinPE
- `Control\Medias.xml` — Offline media configuration for DEPLOY USB creation

#### Offline Media

- Full support for DEPLOY-labeled USB flash drive deployments
- Scripts fall back to USB paths when network shares are unavailable
- `C:\Deploy\MDT` folder structure for offline media sets

#### Prerequisites Bundle

- DHCP Server configuration template (`DeploymentConfigTemplate.xml`)
- WDS Server configuration export
- MDT Templates self-extracting archive
- AOMEI PXE Boot server installer (for desktop deployments)
- ScanState tool (`.7z` archive)
- Offline servicing components (`Microsoft-OneCore-DirectX-Database-FOD-Package`)

#### Documentation

- `README.md` — Project overview, features, quick start, scripts reference
- `docs/SETUP.md` — Full server and desktop setup walkthrough
- `docs/SCRIPTS.md` — Detailed script reference
- `docs/OEM.md` — OEM app and driver pack structure
- `docs/OFFLINE-MEDIA.md` — DEPLOY USB creation walkthrough
- `docs/TROUBLESHOOTING.md` — Common errors and fixes
- `CONTRIBUTING.md` — Contribution guidelines and script standards
- `CHANGELOG.md` — This file

#### Repository Infrastructure

- `LICENSE` — MIT License
- `.github/FUNDING.yml` — GitHub Sponsors configuration
- `.github/release.yml` — Auto-categorized release notes from PRs

### Security

- Documented that `Control\Bootstrap.ini` stores credentials in plaintext and requires a least-privilege deployment account with restricted share permissions.
- Documented that `$OEM$\$1\Recovery\OEM\pre.ps1` contains a hardcoded `$AnyDeskPassword` that must be changed before use in any non-lab environment.
- Office activation via Ohook is gated by `Test-OfficeSafeForActivation`, which fails closed if any Office application is running in an interactive user session or if the process list cannot be enumerated.
- Windows activation via `Activate-Windows` captures `/ipk` and `/ato` exit codes separately and falls through to HWID activation if the firmware-key path fails.

---

[Unreleased]: https://github.com/ArthurJDurand/MDT-TS-and-Scripts/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ArthurJDurand/MDT-TS-and-Scripts/releases/tag/v1.0.0
