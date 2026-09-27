# Scripts Reference

Complete reference for every script that ships in this repository. Each entry describes the script's purpose, when it runs, what it depends on, and any known limitations.

For the deployment phases referenced throughout, see the [Deployment Flow](../README.md#deployment-flow) in the README. For the OEM Apps framework, see [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md).

---

## Table of Contents

- [Execution Contexts](#execution-contexts)
- [Repository Layout](#repository-layout)
- [Task Sequence Scripts](#task-sequence-scripts)
  - [LoadWinPEDrivers.ps1](#loadwinpedriversps1)
  - [CleanFixedDrives.ps1](#cleanfixeddrivesps1)
  - [SetTargetOSDisk.ps1](#settargetosdiskps1)
  - [CreateRecoveryPartition-BIOS.ps1](#createrecoverypartition-biosps1)
  - [CreateRecoveryPartition-UEFI.ps1](#createrecoverypartition-uefips1)
  - [FormatDataDrive.ps1](#formatdatadriveps1)
  - [ApplyUpdates10x64.ps1](#applyupdates10x64ps1)
  - [ApplyUpdates10x86.ps1](#applyupdates10x86ps1)
  - [ApplyUpdates11.ps1](#applyupdates11ps1)
  - [ExtractOEMAppsx64.ps1 / ExtractOEMAppsx86.ps1](#extractoemappsx64ps1--extractoemappsx86ps1)
  - [ExtractOEMDrivers.ps1](#extractoemdriversps1)
  - [ApplyOEMDrivers.ps1](#applyoemdriversps1)
  - [WinRE.ps1](#winreps1)
  - [CleanupScripts.ps1](#cleanupscriptsps1)
  - [CopyOEM.wsf](#copyoemwsf)
- [Stock MDT Scripts Used](#stock-mdt-scripts-used)
- [$OEM$ Setup and Orchestration](#oem-setup-and-orchestration)
  - [SetupComplete.cmd](#setupcompletecmd)
- [$OEM$ Configuration](#oem-configuration)
  - [pre.ps1](#preps1)
- [$OEM$ Framework](#oem-framework)
- [$OEM$ Activation Scripts](#oem-activation-scripts)
  - [HWID_Activation.cmd](#hwid_activationcmd)
- [$OEM$ Layout and Registry Files](#oem-layout-and-registry-files)
- [$OEM$ Application Configurators](#oem-application-configurators)
  - [RustDesk.ps1](#rustdeskps1)
  - [DymaxIOLicense.ps1](#dymaxiolicenseps1)
  - [DiskeeperLicense.ps1](#diskeeperlicenseps1)
  - [AnyDesk.cmd](#anydeskcmd)
  - [Update.xml](#updatexml)
- [PBR Extensibility Chain](#pbr-extensibility-chain)
- [$OEM$ Post-Deployment Scripts](#oem-post-deployment-scripts)
- [Log File Locations](#log-file-locations)
- [Script Standards for Contributors](#script-standards-for-contributors)

---

## Execution Contexts

Scripts run in one of four contexts. The rules differ per context.

| Context | Location | PowerShell | WMI/CIM | Registry writes |
|---|---|---|---|---|
| **WinPE** | `DeploymentShare\Scripts\Custom\` | 5.1 | Only `Get-PhysicalDisk` via `winpe-storagewmi`; other WMI/CIM unavailable | Via `reg.exe` only |
| **Full OS (OOBE)** | `DeploymentShare\x64\$OEM$\$1\...` and `x86\...` | 5.1 | Available | Via `reg.exe` only |
| **Full OS (interactive)** | `DeploymentShare\x64\$OEM$\$1\Scripts\` | 5.1 or 7 | Available | Via `reg.exe` only |
| **PBR / WinRE** | `DeploymentShare\x64\$OEM$\$1\Recovery\OEM\` | CMD only | Not used | Via `reg.exe` only |

Scripts in `Scripts\Custom\` are WinPE-safe by design. Scripts in `$OEM$` run in the full OS and may use WMI/CIM, but all registry **writes** must go through `reg.exe` — never the PowerShell Registry Provider. See [Script Standards](#script-standards-for-contributors).

Any script that reads a network share has a fallback to a `DEPLOY`-labeled USB flash drive. This is consistent across the project.

---

## Repository Layout

The repository ships two parallel trees, one per architecture:

```
DeploymentShare\
├── Boot\
│   └── Addon\
│       ├── x64\                            Bundled 7-Zip for the x64 boot image
│       └── x86\                            Bundled 7-Zip for the x86 boot image
├── Control\                                Deployment share configuration and task sequences
├── Scripts\
│   ├── CopyOEM.wsf
│   ├── ZTIBde.wsf
│   ├── ZTIUtility.vbs
│   ├── DeployWiz_SelectTS.vbs
│   └── Custom\                             Task sequence scripts
├── Templates\                              Stock MDT unattend templates
├── Tools\
│   ├── x64\                                BGInfo64, Microsoft.BDD.Utility.dll
│   └── x86\                                BGInfo, Microsoft.BDD.Utility.dll
├── x64\
│   └── $OEM$\
│       ├── $$\
│       │   └── Setup\Scripts\SetupComplete.cmd
│       └── $1\
│           ├── Recovery\OEM\              OEM configuration, activation, apps, framework
│           └── Scripts\                   Post-deployment scripts
└── x86\
    └── $OEM$\                             Parallel structure, no framework
```

The x86 tree does not ship the Apps framework. It uses monolith scripts that are not part of this repository. See [Known Limitations](#known-limitations) at the end of this document.

---

## Task Sequence Scripts

Located in `DeploymentShare\Scripts\Custom\`. All are WinPE-safe. All run inside the task sequence and communicate status via exit codes.

---

### LoadWinPEDrivers.ps1

**Purpose:** Loads the correct Intel VMD storage driver in WinPE when internal storage is not detected.

**When it runs:** Preinstall phase, first step, before disk partitioning.

**What it does:**

1. Uses `diskpart` (via `Test-InternalStoragePresence`) to check if any disk is visible.
2. If disks are already visible, exits immediately — no action.
3. If no disks are visible:
   - Reads CPU name from `HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0`.
   - Calls `Get-IntelProcessorGeneration` to determine the generation.
   - Maps the generation to a VMD driver version:
     - Generation ≥ 12 → `20.2.6.1025.3`
     - Generation 11 → `19.5.8.1059.2`
     - Anything else → no action
   - Copies the matching driver folder from `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<version>` or a local `Drivers\WinPE\Storage\Intel\x64\<version>` path to `%TEMP%\Drivers`.
   - Runs `drvload` on each `.inf` file.
   - Writes a marker file (`VMD_Loaded.txt`) with the driver version.

**External dependencies:**

- 7-Zip is **not required** — drivers are pre-extracted
- Share: `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\` or local `Drivers\WinPE\Storage\Intel\x64\`

**Environment variables:**

- Reads `OSDTargetSystemDrive` if present
- Uses `%TEMP%` for driver staging and marker file

**Exit codes:** Returns normally. Does not `exit` — the task sequence captures status from the script's completion.

**Known limitations:**

- Only handles Intel VMD. AMD RAID / NVMe is not covered.
- Driver versions are hardcoded per generation. New CPU generations require a code update.
- The marker file is written to WinPE `%TEMP%`, which does not persist into the full OS. Downstream scripts that need the marker must write their own persistence.
- Requires `winpe-storagewmi` (included in the default boot image FeaturePacks).

---

### CleanFixedDrives.ps1

**Purpose:** Wipes all internal (non-USB) drives.

**When it runs:** Preinstall phase, inside the "New Computer only" group.

**What it does:**

```powershell
Get-Disk | Where-Object { $_.BusType -ne 'USB' } |
    Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
```

**External dependencies:** None beyond the Storage module (in WinPE via `winpe-storagewmi`).

**Exit codes:** Returns normally. Failures are non-fatal — the task sequence step is configured with `continueOnError="true"`.

**Known limitations:**

- Destructive. Removes OEM partitions (Recovery, EFI, MSR) along with data partitions.
- Will wipe any disk the OS recognizes as non-USB. On systems with eSATA or Thunderbolt drives that report as fixed, this can wipe unintended disks.
- Runs in one pass — if any disk cannot be cleared, the disk is left in an inconsistent state.

---

### SetTargetOSDisk.ps1

**Purpose:** Selects the optimal target disk for OS installation.

**When it runs:** Preinstall phase, after `CleanFixedDrives.ps1` and before disk partitioning.

**What it does:**

1. Collects all physical disks excluding USB.
2. Builds an array of SSDs.
3. If any SSDs exist:
   - Prefers NVMe SSDs.
   - Falls back to SATA SSDs.
   - Selects the one with the smallest `Size`.
4. If no SSDs exist, selects the smallest non-USB disk.
5. Sets the `OSDDiskIndex` task sequence variable to the chosen disk's `DeviceID`.

**External dependencies:** `Get-PhysicalDisk` (Storage module, `winpe-storagewmi`).

**Environment variables:**

- Sets `OSDDiskIndex` via the `Microsoft.SMS.TSEnvironment` COM object.
- The `Format and Partition Disk` step reads `OSDDiskIndex`.

**Exit codes:** Returns normally.

**Known limitations:**

- Sorts by **ascending** size — picks the **smallest** qualifying SSD. To prefer the largest, change the sort to `-Descending`.
- Does not distinguish PCIe NVMe from M.2 NVMe — both report `BusType = NVMe`.
- If two identical disks exist, selection is by `DeviceID` after the size sort.

---

### CreateRecoveryPartition-BIOS.ps1

**Purpose:** Shrinks the Windows partition and creates a BIOS recovery partition.

**When it runs:** Preinstall phase, after disk partitioning, BIOS targets only (condition: `IsUEFI notEquals True`).

**What it does:**

1. Reads the boot disk number and Windows partition number.
2. Uses `diskpart` to:
   - `shrink minimum=1000` on the Windows partition.
   - `create partition primary`.
   - `format quick fs=ntfs label=Recovery`.
   - `set id=27` (recovery partition type for BIOS/MBR).

**External dependencies:** `diskpart`.

**Exit codes:** Returns normally. `diskpart`'s exit code is not explicitly checked.

**Known limitations:**

- Requires at least 1000 MB of free space on the Windows partition.
- Does not fall back gracefully if the shrink fails — leaves the disk in a partially-shrunk state.
- Only handles a single boot disk. Multi-boot configurations are not supported.

---

### CreateRecoveryPartition-UEFI.ps1

**Purpose:** Shrinks the Windows partition and creates a UEFI recovery partition.

**When it runs:** Preinstall phase, after disk partitioning, UEFI targets only (condition: `IsUEFI equals True`).

**What it does:**

Same steps as the BIOS variant, but uses:

- `set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac` (Windows Recovery Environment GUID).
- `gpt attributes=0x8000000000000001` (marks the partition as required + hides it from automatic mounting).

**External dependencies:** `diskpart`.

**Exit codes:** Returns normally.

**Known limitations:**

- Requires at least 1000 MB of free space on the Windows partition.
- GPT attributes `0x8000000000000001` prevent the recovery partition from getting a drive letter automatically. To access it, use `diskpart` to remove the attribute first.

---

### FormatDataDrive.ps1

**Purpose:** Formats any additional raw internal disk as a Data drive.

**When it runs:** Preinstall phase, after recovery partition creation.

**What it does:**

1. Finds the first disk with `PartitionStyle -eq 'RAW'`.
2. Initializes it with GPT.
3. Removes any existing partitions.
4. Creates a 128 MB MSR partition with GUID `{e3c9e316-0b5c-4db8-817d-f92df00215ae}`.
5. Creates a primary data partition using the remaining space, with GPT type `{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}`.
6. Assigns a drive letter and formats as NTFS with the label `Data`.

**External dependencies:** Storage module.

**Exit codes:** Returns normally.

**Known limitations:**

- Only handles **one** raw disk. Systems with two additional disks will only have the first formatted.
- Destructive: any data on the raw disk is lost.
- Does not detect "already formatted" data disks — this is by design, since `CleanFixedDrives.ps1` runs before it.

---

### ApplyUpdates10x64.ps1

**Purpose:** Injects Windows 10 x64 updates (`.cab` / `.msu`) into the offline image.

**When it runs:** Install phase, immediately after the `Install Operating System` step.

**What it does:**

1. Locates the Windows volume via `Get-Volume -FileSystemLabel Windows`.
2. Resolves the update source:
   - Primary: `\\SERVER\Shared\Updates\Win10\x64`
   - Fallback: DEPLOY USB at `Updates\Win10\x64`
3. If no `.cab` or `.msu` files exist at the source, exits without changes.
4. Creates `<Windows>\Scratch` and `<Windows>\Updates` directories.
5. Uses `robocopy` with retry (`/ZB`) to copy update packages.
6. Runs `DISM.exe /Image:<Windows>\ /Add-Package /PackagePath:<Windows>\Updates /ScratchDir:<Windows>\Scratch`.
7. Removes the temporary `Updates` and `Scratch` directories.

**External dependencies:**

- `DISM` (present in WinPE)
- `robocopy`
- Network share or DEPLOY USB

**Exit codes:** Does **not** check `DISM` exit codes. The script continues even if some packages fail to apply. Check `X:\MININT\SMSOSD\OSDLOGS\` for DISM output.

**Known limitations:**

- All-or-nothing per package. If DISM fails on one package, it may or may not apply the rest.
- `.msu` files larger than the free space on the Windows partition will fail.
- No verification that injected packages are actually newer than what's in the WIM.

---

### ApplyUpdates10x86.ps1

x86 variant of `ApplyUpdates10x64.ps1`. Same behaviour, but:

- Source path: `\\SERVER\Shared\Updates\Win10\x86`
- Deploy path on USB: `Updates\Win10\x86`

---

### ApplyUpdates11.ps1

Windows 11 variant of `ApplyUpdates10x64.ps1`. Same behaviour, but:

- Source path: `\\SERVER\Shared\Updates\Win11`
- Deploy path on USB: `Updates\Win11`

---

### ExtractOEMAppsx64.ps1 / ExtractOEMAppsx86.ps1

**Purpose:** Extracts the manufacturer-specific OEM app archive to `C:\Recovery\OEM`.

**When it runs:** Install phase, after `CopyOEM` and before `ApplyOEMDrivers`.

**What it does:**

1. Locates the Windows volume.
2. Resolves the source:
   - Primary: `\\SERVER\Shared\OEM\x64` (or `x86`)
   - Fallback: DEPLOY USB at `OEM\x64` (or `x86`)
3. Detects the manufacturer via `Get-Manufacturer` (uses WMI/CIM — safe because this runs in the full OS during OOBE).
4. Maps the manufacturer to a `.7z` archive:
   - `Acer`, `ASUS`, `Dell`, `Dynabook`, `Gigabyte`, `HP` / `Hewlett Packard` / `Hewlett-Packard`, `Huawei`, `Lenovo`, `Microsoft`, `Micro-Star` / `MicroStar` / `MSI`, `Proline`
5. Extracts the archive with 7-Zip to `C:\Recovery\OEM\`.

**External dependencies:**

- 7-Zip at `X:\Program Files\7-Zip\7z.exe`
- Network share or DEPLOY USB

**Exit codes:** Returns normally. Retries 7-Zip extraction in a `do/while` loop until exit code is 0. **Infinite loop risk** if the archive is corrupt and 7-Zip keeps returning non-zero.

**Known limitations:**

- Hardcoded manufacturer list. New vendors require a script update.
- On systems with a manufacturer string that does not match any known vendor, the script exits silently — no fallback extraction.
- Uses `Get-CimInstance` — safe because it runs in the full OS. If you move this script to a WinPE phase, it will fail.

---

### ExtractOEMDrivers.ps1

**Purpose:** Extracts the model-specific driver archive to `C:\Recovery\OEM\Drivers`.

**When it runs:** Install phase, after `ExtractOEMApps`.

**What it does:**

1. Locates the Windows volume via `OSDTargetSystemDrive` or by scanning for `Windows\System32\Config\SOFTWARE`.
2. Resolves the source:
   - Primary: `\\SERVER\Shared\DriverPacks`
   - Fallback: DEPLOY USB at `DriverPacks`
3. Reads CPU name from the registry (WinPE-safe).
4. Detects CPU vendor and generation, plus manufacturer and model via registry (`HKLM:\HARDWARE\DESCRIPTION\System\BIOS`).
5. Builds a priority list of pattern matches (exact model, model + generation, HP/Lenovo simplifications, truncated model).
6. Sorts candidate archives by name length (descending) then size (descending), picks the first match.
7. Extracts to `C:\Recovery\OEM\Drivers\` with 7-Zip (retries up to 3 times).

**External dependencies:**

- 7-Zip at `X:\Program Files\7-Zip\7z.exe` or `C:\Program Files\7-Zip\7z.exe`
- Network share or DEPLOY USB

**Exit codes:** Returns normally.

**Known limitations:**

- `Get-OSFamily` currently hardcodes `Win11`. Latent bug for Win10 deployments — the Win10 task sequence will look in the Win11 driver pack folder. Fix: read the target OS from the offline registry's `CurrentBuildNumber`.
- Model matching relies on exact or partial string matches. Unknown models fall through without a driver pack.
- Archive selection is heuristic — if a similarly named archive exists for a different model, it may be picked.

---

### ApplyOEMDrivers.ps1

**Purpose:** Applies extracted OEM, WLAN, and Intel VMD drivers to the offline Windows image via DISM.

**When it runs:** Install phase, after `ExtractOEMDrivers.ps1`.

**What it does:**

1. Locates the Windows image path (via `OSDTargetSystemDrive` or by scanning).
2. If `C:\Recovery\OEM\Drivers` exists:
   - Reads CPU name from the registry.
   - Calls `Get-ProcessorArchitecture` to classify the CPU.
   - Calls `Get-Model` and `Get-Manufacturer` (registry-based).
   - Calls `Find-BestDriverFolder` to locate the model-specific driver folder.
   - Runs `DISM.exe /Add-Driver /Recurse` on the found folder with up to 3 retry attempts.
   - Applies WLAN drivers from `C:\Recovery\OEM\Drivers\WLAN` (if present).
   - Applies Intel VMD drivers from `C:\Recovery\OEM\Drivers\Storage\Intel\<version>` if the CPU is Intel with a supported generation.

**External dependencies:**

- `DISM` (in WinPE)
- Registry access

**Exit codes:** Returns normally. Logs failures but does not fail the task sequence step.

**Known limitations:**

- Silent — check the DISM log at `C:\Windows\Logs\DISM\dism.log` for driver injection results.
- Applies all `.inf` files in a folder recursively. If the OEM pack has incompatible drivers for other models, they may be applied and cause device errors.
- Intel VMD driver versions are hardcoded. New generations require a code update.

---

### WinRE.ps1

**Purpose:** Deploys and configures Windows Recovery Environment on the recovery partition, with optional VMD driver injection.

**When it runs:** Postinstall phase, after `Apply Patches`.

**What it does:**

1. Detects the OS disk, Windows drive letter, System partition, Recovery partition.
2. Determines the target OS family (Win10 / Win11) and architecture (x64 / x86) by reading the offline registry and checking for `SysWOW64`.
3. Ensures the System and Recovery partitions have drive letters.
4. Locates the source WinRE image:
   - First tries `<Windows>\System32\Recovery\winre.wim`.
   - Then `<Windows>\Recovery\WindowsRE\winre.wim`.
   - Then falls back to `\\SERVER\Shared\WindowsRE\<Win10|Win11>\<x64|x86>\winre.wim`.
   - Then falls back to DEPLOY USB.
5. Copies the WinRE image to a working folder on the Windows drive with retry and SHA-256 integrity verification.
6. Checks for a VMD marker file (from `LoadWinPEDrivers.ps1`) and, if present and the target is x64, injects the corresponding VMD drivers into the WinRE image.
7. Copies the modified WinRE to the Recovery partition.
8. Runs `reagentc.exe /setreimage` and `/enable` with the correct OS GUID from BCD.
9. Updates the `WinREVersion` registry value.
10. Removes the recovery partition's drive letter.

**External dependencies:**

- `reagentc.exe` (present in Windows)
- `bcdedit`
- `dism`
- `reg`
- WinRE source WIM

**Exit codes:** Uses `exit 1` on unrecoverable errors (missing Windows volume, missing WinRE image, hash mismatch). Otherwise returns normally.

**Known limitations:**

- **VMD marker persistence:** If `LoadWinPEDrivers.ps1` wrote the marker to `%TEMP%` in WinPE, `WinRE.ps1` (running in the full OS during Postinstall) will not find it. VMD driver injection into WinRE may therefore not occur.
- Uses `Get-Volume -FileSystemLabel System` / `Recovery` without `Select-Object -First 1`. On systems with multiple partitions sharing a label, this can return an array.
- Relies on partition labels. If a user renames a partition, the script fails silently.
- Deletes `<Windows>\Recovery\WindowsRE` and `<Windows>\Recovery\ReAgentOld.xml` after configuring the recovery partition.

---

### CleanupScripts.ps1

**Purpose:** Removes MDT artifacts from the deployed OS after deployment.

**When it runs:** Postinstall phase, after `Add Windows Recovery (WinRE)`.

**What it does:** Deletes the following from the Windows drive:

- `_SMSTaskSequence`
- `MININT`
- `LTIBootstrap.vbs`

**External dependencies:** None.

**Exit codes:** Returns normally.

**Known limitations:**

- Does not remove `C:\Windows\Temp\DeploymentLogs\`. Those persist for troubleshooting.
- Does not remove the OEM logs at `C:\ProgramData\OEM\Logs\`. Those are managed by `SetupComplete.cmd`.

---

### CopyOEM.wsf

**Purpose:** Copies `$OEM$\$1` and `$OEM$\$$` content to the target OS.

**When it runs:** Install phase, after `Apply Updates` and before `Extract OEM Apps`.

**What it does:** Searches for the `$OEM$` folder in this order:

1. `<DeployRoot>\Control\<TaskSequenceID>\$OEM$`
2. `<SourcePath>\$OEM$`
3. `<DeployRoot>\<Architecture>\$OEM$`
4. `<DeployRoot>\$OEM$`

Then:

- Copies `<sOEM>\$1\*` to the root of the Windows volume.
- Copies `<sOEM>\$$\*` to `<OSDrive>\Windows\`.

**External dependencies:** MDT's `ZTIUtility.vbs` and `ZTIDiskUtility.vbs`.

**Exit codes:** Returns normally.

**Known limitations:**

- Based on Michael Niehaus's original `CopyOEM.wsf` from MDT 2012 Update 1. Not modified from the original.
- If no `$OEM$` folder exists, exits silently.

---

## Stock MDT Scripts Used

This repository does not modify the stock MDT scripts it depends on. They ship as part of the standard MDT installation and are copied into the deployment share. If you upgrade MDT, they may be updated.

| File | Purpose |
|---|---|
| `Scripts\ZTIUtility.vbs` | Core MDT utility library. Referenced by every WSF script. Do not edit. |
| `Scripts\ZTIBde.wsf` | BitLocker enablement script used by the Enable BitLocker task sequence step (disabled by default in this project). |
| `Scripts\DeployWiz_SelectTS.vbs` | The task sequence picker shown by LiteTouch. Not used when `SkipTaskSequence=YES`. |
| `Tools\x64\Bginfo64.exe` | BGInfo (x64). Runs as part of the stock MDT bootstrap to write system information to the desktop wallpaper during deployment. |
| `Tools\x64\microsoft.bdd.utility.dll` | MDT utility library (x64). |
| `Tools\x86\Bginfo.exe` | BGInfo (x86). |
| `Tools\x86\microsoft.bdd.utility.dll` | MDT utility library (x86). |
| `Templates\Unattend_PE_x64.xml` | Stock MDT unattend template used when generating WinPE boot images. |

**Do not edit these files.** They are overwritten when MDT is updated or when the deployment share is regenerated. Customizations belong in `Scripts\Custom\` or in the `$OEM$` trees.

---

## $OEM$ Setup and Orchestration

Located under `DeploymentShare\<arch>\$OEM$\$$\Setup\Scripts\`. This path is copied to `C:\Windows\Setup\Scripts\` on the target, where Windows automatically runs `SetupComplete.cmd` at the end of OOBE.

---

### SetupComplete.cmd

**Purpose:** Orchestrates the OEM post-OOBE configuration chain.

**When it runs:** End of OOBE, automatically invoked by Windows Setup.

**What it does:**

1. Creates the log directory at `C:\ProgramData\OEM\Logs`.
2. Logs start time, date, and computer name.
3. Disables standby timeout on AC power.
4. Runs, in order:
   - `C:\Recovery\OEM\pre.ps1`
   - `C:\Recovery\OEM\Customizations.ps1`
   - `C:\Recovery\OEM\Apps\pbr.ps1`
5. Cleans up MDT artifacts (`_SMSTaskSequence`, `MININT`, `LiteTouch.lnk`, `LTIBootstrap.vbs`).
6. Sets hidden attributes on the Default user profile folders.
7. Logs completion.

Each child script runs via `powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass`, with stdout and stderr redirected to the log file.

**External dependencies:** PowerShell 5.1 (present in Windows).

**Exit codes:** Always exits `0`. Individual child script exit codes are captured via `ERRORLEVEL` and logged.

**Known limitations:**

- If `pre.ps1` hangs, `SetupComplete.cmd` waits indefinitely. The `-NonInteractive` flag mitigates this but does not eliminate it.
- The `pre.ps1` registry writes to the Default user hive are idempotent with the framework's own hardening.

**Note:** An identical copy exists at `$1\Recovery\OEM\SetupComplete.cmd`. It is restored by `AfterImage.cmd` during PBR.

---

## $OEM$ Configuration

Located under `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\`.

---

### pre.ps1

**Purpose:** OEM configuration script. Installs drivers, applies LGPO, activates Windows and Office, installs third-party applications, and configures system settings.

**When it runs:** OOBE, via `SetupComplete.cmd`.

**What it does, in order:**

1. Starts a transcript log at `C:\ProgramData\OEM\Logs\pre_<timestamp>.log`.
2. Waits for the system CPU to settle.
3. Configures Windows Defender (PUA protection, exclusions).
4. Sets BitLocker `PreventDeviceEncryption`.
5. Installs OEM drivers for the detected model.
6. Installs WLAN drivers.
7. Detects CPU generation and installs Intel VMD storage drivers.
8. Applies LGPO policies from `C:\Recovery\OEM\LGPO\Backup`.
9. Sets OEM information registry keys.
10. Imports registry files (`DesktopIcons.reg`, `gpsFix.reg`, `OEMInfo.reg`, `RegionalSettings.reg`).
11. Applies Windows 10-specific registry tweaks.
12. Applies layout modifications (Start menu / taskbar).
13. Activates Windows via `Activate-Windows`.
14. Installs Office from `C:\Recovery\OEM\Apps\Office*` if not already installed.
15. Copies Office shortcuts to the Public Desktop.
16. Activates Office via Ohook if installed and safe.
17. Installs UWP apps: `Microsoft.Todos`, `Microsoft.OutlookForWindows` (Win10), `Microsoft.BingNews` (Win10).
18. Removes legacy Win10 apps.
19. Installs media extensions (AV1, HEIF, HEVC, MPEG2, RawImage, VP9, WebMedia, Webp).
20. Installs and configures AnyDesk.
21. Installs and configures RustDesk.
22. Installs 7-Zip.
23. Installs WinRAR and applies registry.
24. Installs DymaxIO (x64) or Diskeeper (x86) and applies license.
25. Installs Acronis Drive Monitor (only if a spinning HDD is present).
26. Enables Windows RE if disabled.
27. Creates the `OEM\Update` scheduled task from `Update.xml` (x64 only).
28. Sets hidden attributes on `C:\ProgramData`, `C:\Users\Default`, and related paths.
29. Cleans up `_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`.
30. Writes an installation summary to the transcript.

**External dependencies:**

- 7-Zip at `C:\Program Files\7-Zip\7z.exe`
- PowerShell 5.1
- Internet access (for Ohook and HWID activation)
- `pnputil`, `dism`, `reg`, `cmd`, `powershell` on PATH
- `C:\Recovery\OEM\Activation\HWID_Activation.cmd`
- `C:\Recovery\OEM\LGPO\LGPO.exe`
- `C:\Recovery\OEM\Apps\*` (installers)
- `C:\Recovery\OEM\Drivers\*` (extracted driver packs)

**Exit codes:** Never `exit`s on failure. A top-level `try/catch` logs errors and continues, so `SetupComplete.cmd` proceeds to `Customizations.ps1` and `pbr.ps1`.

**Known limitations:**

- **AnyDesk password hardcoded** as `$AnyDeskPassword = 'p@$$w0rd'`. Change this before using AnyDesk outside an isolated lab.
- **Large script** (68 KB x64, 45 KB x86). Refactor candidate.
- The UWP version guard `Skip-IfNewerProvisioned` requires the package filename to contain a version string in the format `_X.Y.Z.W_`. Packages without a versioned filename are always installed.
- Office activation is deferred if any Office application is running in an interactive user session. This can leave Office unactivated if a user has Office open during OOBE.
- `Wait-SystemIdle` uses WMI as a fallback. On machines where WMI is also broken, it sleeps for 5 seconds and returns.
- **x86 variant is monolithic.** The x86 `pre.ps1` inlines logic that the x64 variant delegates to the Apps framework.

---

## $OEM$ Framework

The OEM Apps framework — `pbr.ps1`, the ten framework modules under `Framework\`, the eleven OEM modules under `OEM\`, and the eleven manifest files under `Manifests\` — is documented in **[docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md)**.

The framework ships only in the x64 tree. The x86 tree uses monolith scripts that are not part of this repository.

---

## $OEM$ Activation Scripts

Located under `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Activation\`.

---

### HWID_Activation.cmd

**Purpose:** HWID-based Windows activation fallback.

**When it runs:** Called by `pre.ps1` when the firmware OEM key activation fails.

**What it does:** Runs Microsoft's HWID activation script, which contacts Microsoft's activation servers and applies a digital license tied to the hardware.

**External dependencies:** Internet access.

**Exit codes:** Passed through to `pre.ps1`. `pre.ps1` returns `$true` from `Activate-Windows` regardless of the outcome of this call.

**Known limitations:**

- Requires internet connectivity.
- HWID activation only works on hardware that has a Windows 10 or Windows 11 digital license embedded by the OEM.

---

## $OEM$ Layout and Registry Files

Located at `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\`.

| File | Purpose |
|---|---|
| `LayoutModification.xml` | Base Start menu layout for Windows 10. Extended with manifest-defined pins by the framework (x64) or monolith scripts (x86, not in this repository). |
| `TaskbarLayoutModification.xml` | Base taskbar layout for Windows 11. Extended with manifest-defined pins by the framework. |
| `DesktopIcons.reg` | Registry file that controls which icons appear on the default desktop. Imported by `pre.ps1`. |
| `RegionalSettings.reg` | Registry file that sets regional and locale defaults. Imported by `pre.ps1`. |

If `C:\Recovery\AutoApply` is present, the framework does not touch layout. It is externally owned. See [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md) for the AutoApply contract.

---

## $OEM$ Application Configurators

Located under `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\`.

---

### RustDesk.ps1

**Purpose:** Applies RustDesk configuration after installation.

**When it runs:** Called by `pre.ps1` in a separate `powershell.exe` process.

**What it does:** Reads configuration from a companion file (relay server, API key, default password), applies it to `C:\Program Files\RustDesk\config\`, and configures the service for persistence.

**Exit codes (interpreted by `pre.ps1`):**

- `0` — Full success.
- `1` — Partial success (config written, persistence failed).
- `2` — Complete failure.
- Any other — Unknown error.

**Known limitations:** Behavior depends on RustDesk version. Newer versions may have moved config paths.

---

### DymaxIOLicense.ps1

**Purpose:** Applies the DymaxIO license after installation.

**When it runs:** Called by `pre.ps1` in a separate `powershell.exe` process (x64 tree only).

**What it does:** Invokes DymaxIO's licensing executable with the license key.

**Exit codes (interpreted by `pre.ps1`):**

- `0` — License applied successfully.
- `2` — DymaxIO not installed (skipped).
- Other — Failure.

**Known limitations:** Requires DymaxIO to be installed. If DymaxIO is not present, the script is a no-op.

---

### DiskeeperLicense.ps1

**Purpose:** Applies the Diskeeper license after installation.

**When it runs:** Called by `pre.ps1` in a separate `powershell.exe` process (x86 tree only).

**What it does:** Invokes Diskeeper's licensing executable with the license key.

**Exit codes:** Same contract as `DymaxIOLicense.ps1`.

**Known limitations:** Requires Diskeeper to be installed.

---

### AnyDesk.cmd

**Purpose:** Configures AnyDesk after installation.

**When it runs:** Called by `pre.ps1` after AnyDesk is installed.

**What it does:** Sets the AnyDesk password and options via `anydesk.exe --set-password` and related commands.

**Known limitations:** The password is set from a value in `pre.ps1`, not from this file. This file is a thin wrapper.

---

### Update.xml

**Purpose:** Task Scheduler definition for the `OEM\Update` scheduled task.

**When it runs:** Imported by `pre.ps1` via `schtasks /create /tn OEM\Update /xml <path> /f` (x64 tree only).

**What it does:** Defines a task that performs post-deployment updates on a monthly basis, including updates to extensibility-point apps and scripts.

**Known limitations:**

- Not a script — this is a Task Scheduler XML definition.
- The task runs as SYSTEM with highest privileges.
- **x86 tree has no equivalent.** Post-deployment updates are not supported on x86.

---

## PBR Extensibility Chain

> **These files are internals of the Push-Button Reset extensibility chain. Do not edit them.** They are covered in full by the framework's canonical documentation. The summary below is provided only so contributors recognize the files when they encounter them.

Located at `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\`.

| File | Purpose |
|---|---|
| `ResetConfig.xml` | Windows PBR configuration. Hooks `PreImage.cmd` and `AfterImage.cmd` into four reset phases (`BasicReset_BeforeImageApply`, `BasicReset_AfterImageApply`, `FactoryReset_AfterDiskFormat`, `FactoryReset_AfterImageApply`). Declares the PBR partition layout. |
| `PreImage.cmd` | No-op placeholder for the `BeforeImageApply` hook. Reserves the hook point. |
| `AfterImage.cmd` | Runs after the PBR image is applied. Locates the OS volume, creates `Windows\OEM`, `Recovery\OEM\Apps\Logs`, and `Windows\Setup\Scripts` folders, copies `Recovery\OEM\SetupComplete.cmd` to `Windows\Setup\Scripts`, and copies `Recovery\OEM\unattend.xml` to `Windows\Panther`. |
| `preWINRE.cmd` | Loads boot-critical drivers via `drvload` from `\Drivers\bootcritical\*.inf` during WinRE startup. |
| `ResetPartitions.txt` | Diskpart script for factory reset. Creates EFI (260 MB), MSR (128 MB), Windows (max minus 1000 MB), and Recovery partitions on GPT. |
| `unattend.xml` | OOBE unattend used after a PBR reset. Restored to `Windows\Panther` by `AfterImage.cmd`. Sets locale, timezone, and offline driver paths. |

**Note:** `preWINRE.cmd` uses inconsistent casing across the two architectures — lowercase `pre` for x64, capital `Pre` for x86. This is intentional per the PBR extensibility contract and must not be "corrected" without verifying with the framework's canonical docs.

---

## $OEM$ Post-Deployment Scripts

Located at `DeploymentShare\<arch>\$OEM$\$1\Scripts\`. These are copied to `C:\Scripts\` on the deployed machine and are intended to be run manually by the technician after OOBE completes.

The number prefix indicates the order in which the scripts should be run. Restarts are required between `1Firstrun.cmd` and `2Secondrun.cmd`, and after `2Secondrun.cmd`.

| File | Purpose |
|---|---|
| `0CleanWindowsUpdates.cmd` | Cleans up the Windows component store after Windows Updates. |
| `0Install-AnyDesk.cmd` | Installs AnyDesk interactively if not already present. **x64 tree only.** |
| `0KeepAwake.cmd` | Prevents the machine from sleeping during long-running maintenance. |
| `1Firstrun.cmd` | Interactive first pass. Opens Windows Update, OEM utility setup, and GPU software for the technician to complete. |
| `2Secondrun.cmd` | Interactive second pass after restart. Applies final updates and records marker decisions (e.g., Dell Optimizer, Dell ACC, MSI Center). |
| `3OEMDriversExport.cmd` | Exports drivers from the deployed machine and saves them to `\\SERVER\Shared\DriverPacks` or a DEPLOY-labeled USB at `X:\DriverPacks`. |
| `4ScanState.cmd` | Runs USMT `ScanState` to produce a provisioning package at `C:\Recovery\Customizations`. Transforms `C:\Recovery\OEM` into the AutoApply directory at `C:\Recovery\AutoApply`. |

**Known limitations:**

- These scripts are interactive. They prompt the technician to complete steps in Windows Update, OEM utilities, and other tools.
- Some scripts are optional. The order is authoritative; skipping one may break the ones that follow.
- The x86 tree does not include `0Install-AnyDesk.cmd`.

---

## Log File Locations

| Context | Location |
|---|---|
| Task sequence (WinPE) | `X:\MININT\SMSOSD\OSDLOGS\` |
| Task sequence (full OS) | `C:\MININT\SMSOSD\OSDLOGS\` |
| MDT deployment summary | `C:\Windows\Temp\DeploymentLogs\` |
| OEM setup (post-OOBE) | `C:\ProgramData\OEM\Logs\` |
| `pre.ps1` transcript | `C:\ProgramData\OEM\Logs\pre_<timestamp>.log` |
| `SetupComplete.cmd` | `C:\ProgramData\OEM\Logs\SetupComplete.log` |
| Framework shared log | `C:\ProgramData\OEM\Logs\PBR_Deployment.log` |
| Framework transcript | `C:\ProgramData\OEM\Logs\Master_<Phase>_<PID>_<timestamp>.log` |
| Framework per-app | `C:\ProgramData\OEM\Logs\<AppName>.log` |
| DISM (offline image) | `C:\Windows\Logs\DISM\dism.log` (post-deployment) |
| DISM (WinRE) | `C:\Temp\WinREWork\dism_driver.log` (during `WinRE.ps1`) |

---

## Script Standards for Contributors

All PowerShell scripts in `DeploymentShare\Scripts\Custom\` must follow these standards. Scripts that do not will be asked to change before merging.

### 1. WinPE-safe (for `Scripts\Custom\` only)

- Use the registry and file system for hardware detection.
- Do **not** use `Get-CimInstance`, `Get-WmiObject`, or `Get-PhysicalDisk` unless `winpe-storagewmi` is explicitly available.
- Do not assume `Get-Volume` returns a single result.

Scripts in `$OEM$` run in the full OS and are exempt from the WMI/CIM restriction.

### 2. Defensive lookups

Always pipe through `Select-Object -First 1` or wrap in `@()` when the result could be an array.

### 3. Retry logic

DISM and robocopy operations must retry with exponential backoff.

### 4. Silent operation

Scripts in `Scripts\Custom\` must not use `Write-Host` unless the message is critical. Scripts in `$OEM$` may use it for progress.

### 5. Preserve exit codes

Never mask a failure with a silent `try/catch`. Use `$LASTEXITCODE` after native commands.

### 6. Header documentation

Every script must include a `.SYNOPSIS`, `.DESCRIPTION`, and `.NOTES` block.

### 7. No hardcoded drive letters

Discover volume letters via `Get-Volume -FileSystemLabel`.

### 8. Registry writes via `reg.exe` only

Never use `New-ItemProperty` or the PowerShell Registry Provider for writes. This applies project-wide. Reads via the provider are permitted.

### 9. PowerShell 5.1 compatibility

Scripts must run under the WinPE and Windows OOBE versions of PowerShell, which are **5.1**. No PS7-only syntax.

### 10. No `exit` in task sequence scripts

Return rather than `exit`. Scripts invoked from `SetupComplete.cmd` are standalone and may use `exit`.

### 11. Do not edit stock MDT scripts

Files under `Scripts\` (outside `Scripts\Custom\`), `Tools\`, and `Templates\` are stock MDT content. They are overwritten when MDT is updated. Customizations belong in `Scripts\Custom\` or in the `$OEM$` trees.

---

*See [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common errors and their fixes, and [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md) for the OEM Apps framework.*
