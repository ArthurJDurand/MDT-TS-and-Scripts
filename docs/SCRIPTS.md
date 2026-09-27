# Scripts Reference

Complete reference for every script shipped in this repository. Each entry documents the script's purpose, when it runs, what it depends on, and known limitations.

For the task sequence phases referenced here, see the [Deployment Flow](../README.md#deployment-flow) in the README.

---

## Table of Contents

- [Execution Contexts](#execution-contexts)
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
  - [ExtractOEMAppsx64.ps1](#extractoemappsx64ps1)
  - [ExtractOEMAppsx86.ps1](#extractoemappsx86ps1)
  - [ExtractOEMDrivers.ps1](#extractoemdriversps1)
  - [ApplyOEMDrivers.ps1](#applyoemdriversps1)
  - [WinRE.ps1](#winreps1)
  - [CleanupScripts.ps1](#cleanupscriptsps1)
  - [CopyOEM.wsf](#copyoemwsf)
- [$OEM$ Orchestration Scripts](#oem-orchestration-scripts)
  - [SetupComplete.cmd](#setupcompletecmd)
- [$OEM$ Configuration Scripts](#oem-configuration-scripts)
  - [pre.ps1](#preps1)
  - [Customizations.ps1](#customizationsps1)
  - [Apps\pbr.ps1](#appspbrps1)
- [$OEM$ Activation Scripts](#oem-activation-scripts)
  - [HWID_Activation.cmd](#hwid_activationcmd)
  - [Ohook_Activation.cmd](#ohook_activationcmd)
- [$OEM$ Payload Updaters](#oem-payload-updaters)
  - [Apps.ps1](#appsps1)
  - [Drivers.ps1](#driversps1)
  - [LGPO.ps1](#lgpops1)
- [$OEM$ Application Configurators](#oem-application-configurators)
  - [RustDesk.ps1](#rustdeskps1)
  - [DymaxIOLicense.ps1](#dymaxiolicenseps1)
  - [Update.xml](#updatexml)
- [$OEM$ Post-Deployment Scripts](#oem-post-deployment-scripts)
  - [OEMDriversExport.ps1](#oemdriversexportps1)
  - [ScanWindowsImage64.ps1](#scanwindowsimage64ps1)
  - [ScanStatex64.ps1](#scanstatex64ps1)
- [Common Patterns](#common-patterns)
- [Log File Locations](#log-file-locations)

---

## Execution Contexts

Scripts run in one of three contexts. The rules differ per context.

| Context | Scripts | PowerShell | WMI/CIM | Registry | Notes |
|---|---|---|---|---|---|
| **WinPE** | `Scripts\Custom\` | 5.1 | Only via `winpe-storagewmi` for `Get-PhysicalDisk`; other WMI/CIM unavailable | Full | Runs during Preinstall, Install, Postinstall phases |
| **Full OS (OOBE)** | `$OEM$\$1\...` | 5.1 | Available | Full | Runs via `SetupComplete.cmd` at end of OOBE |
| **Full OS (interactive)** | `$OEM$\$1\Scripts\` | 5.1 or 7 | Available | Full | User-invoked post-deployment on the target machine |

Any script that reads network shares has a fallback to a DEPLOY-labeled USB flash drive. This behaviour is consistent across all scripts.

---

## Task Sequence Scripts

Located in `Scripts\Custom\` in the deployment share. All are **WinPE-safe** unless noted. All run inside the task sequence and communicate status via exit codes.

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

- 7-Zip **not required** (drivers are pre-extracted)
- Share: `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\` or local `Drivers\WinPE\Storage\Intel\x64\`

**Environment variables:**

- `OSDTargetSystemDrive` — read if present
- `%TEMP%` — used for driver staging and marker file

**Exit codes:** Returns normally. Does not `exit` — task sequence captures status from the script's completion.

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

**Environment variables:** None.

**Exit codes:** Returns normally. Failures are non-fatal (task sequence step is configured with `continueOnError="true"`).

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

- Sets `OSDDiskIndex` via `Microsoft.SMS.TSEnvironment` COM object.
- Reads `OSDDiskIndex` in subsequent steps (`Format and Partition Disk`).

**Exit codes:** Returns normally.

**Known limitations:**

- Sorts by **ascending** size — picks the **smallest** qualifying SSD. If you prefer the largest, change `Sort-Object -Property Size` to `Sort-Object -Property Size -Descending`.
- Does not prefer PCIe NVMe over M.2 NVMe — both report as `BusType = NVMe`.
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

**Environment variables:** None — discovers disks via `Get-Disk`/`Get-Partition`.

**Exit codes:** Returns normally. `diskpart` exit code is not explicitly checked.

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
- `gpt attributes=0x8000000000000001` (marks partition as required + hides it from automatic mounting).

**External dependencies:** `diskpart`.

**Environment variables:** None.

**Exit codes:** Returns normally.

**Known limitations:**

- Requires at least 1000 MB of free space on the Windows partition.
- GPT attributes `0x8000000000000001` prevent the recovery partition from getting a drive letter automatically. If you need to access it, use `diskpart` to remove the attribute first.

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

**Environment variables:** None.

**Exit codes:** Returns normally.

**Known limitations:**

- Only handles **one** raw disk. Systems with two additional disks will only have the first formatted.
- Destructive: any data on the raw disk is lost.
- Does not detect "already formatted" data disks — this is by design, since `CleanFixedDrives.ps1` runs before it.

---

### ApplyUpdates10x64.ps1

**Purpose:** Injects Windows 10 x64 updates (`.cab` / `.msu`) into the offline image.

**When it runs:** Install phase, immediately after `Install Operating System` step.

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

**Environment variables:** None.

**Exit codes:** Does **not** check `DISM` exit codes. Script continues even if some packages fail to apply. Check `X:\MININT\SMSOSD\OSDLOGS\` for DISM output.

**Known limitations:**

- All-or-nothing per-package. If DISM fails on one package, it may or may not apply the rest.
- `.msu` files larger than the free space on the Windows partition will fail.
- No verification that the injected packages are actually newer than what's already in the WIM.

---

### ApplyUpdates10x86.ps1

**Purpose:** x86 variant of `ApplyUpdates10x64.ps1`.

Same behaviour, but:

- Source path: `\\SERVER\Shared\Updates\Win10\x86`
- Deploy path on USB: `Updates\Win10\x86`

---

### ApplyUpdates11.ps1

**Purpose:** Windows 11 variant of `ApplyUpdates10x64.ps1`.

Same behaviour, but:

- Source path: `\\SERVER\Shared\Updates\Win11`
- Deploy path on USB: `Updates\Win11`

---

### ExtractOEMAppsx64.ps1

**Purpose:** Extracts manufacturer-specific app archives to `C:\Recovery\OEM`.

**When it runs:** Install phase, after `CopyOEM` and before `ApplyOEMDrivers`.

**What it does:**

1. Locates the Windows volume.
2. Resolves the source:
   - Primary: `\\SERVER\OEM\x64`
   - Fallback: DEPLOY USB at `OEM\x64`
3. Detects the manufacturer via `Get-Manufacturer` (uses WMI/CIM — safe because this runs in the full OS during OOBE, not WinPE).
4. Maps the manufacturer to a `.7z` archive:
   - `Acer`, `ASUS`, `Dell`, `Dynabook`, `Gigabyte`, `HP` / `Hewlett Packard` / `Hewlett-Packard`, `Huawei`, `Lenovo`, `Microsoft`, `Micro-Star` / `MicroStar` / `MSI`, `Proline`
5. Extracts the archive with 7-Zip to `C:\Recovery\OEM\`.

**External dependencies:**

- 7-Zip at `X:\Program Files\7-Zip\7z.exe`
- Network share or DEPLOY USB

**Environment variables:** None.

**Exit codes:** Returns normally. Retries 7-Zip extraction in a `do/while` loop until exit code is 0. **Infinite loop risk** if the archive is corrupt and 7-Zip keeps returning non-zero.

**Known limitations:**

- Hardcoded manufacturer list. New vendors require a script update.
- On systems with a manufacturer string that does not match any known vendor, the script exits silently — no fallback extraction.
- Runs `Get-CimInstance` — this is safe because `ExtractOEMAppsx64.ps1` runs in the full OS (Install phase, after OS apply). If you move this script to a WinPE phase, it will fail.

---

### ExtractOEMAppsx86.ps1

**Purpose:** x86 variant of `ExtractOEMAppsx64.ps1`.

Same behaviour, but:

- Source path: `\\SERVER\OEM\x86`
- Deploy path on USB: `OEM\x86`

---

### ExtractOEMDrivers.ps1

**Purpose:** Extracts the model-specific driver archive to `C:\Recovery\OEM\Drivers`.

**When it runs:** Install phase, after `ExtractOEMAppsx64.ps1`.

**What it does:**

1. Locates the Windows volume via `OSDTargetSystemDrive` or by scanning for `Windows\System32\Config\SOFTWARE`.
2. Resolves the source:
   - Primary: `\\SERVER\Shared\DriverPacks`
   - Fallback: DEPLOY USB at `DriverPacks`
3. Reads CPU name from the registry (WinPE-safe) — this script **is** WinPE-safe despite running in Install phase.
4. Detects:
   - CPU vendor (Intel / AMD / Unknown).
   - CPU generation for Intel (via `Get-IntelProcessorGeneration`).
   - Manufacturer and model via registry (`HKLM:\HARDWARE\DESCRIPTION\System\BIOS`).
5. Builds a priority list of pattern matches:
   - `*<Model>*<Gen>th Gen Intel*`
   - `*<Model>*<Gen>th Gen*`
   - `*<Model>*Gen <Gen>*`
   - `*<Model>*`
   - HP variants: `*<HP Simplified Model>*<Gen>th Gen Intel*`, etc.
   - Lenovo base model matches.
   - Truncated model matches (with suffix removal).
6. Sorts candidate archives by name length (descending) then size (descending) and picks the first match.
7. Extracts to `C:\Recovery\OEM\Drivers\` with 7-Zip (retries up to 3 times).
8. Resolves the driver pack path based on the target OS:
   - Defaults to `Win11`
   - Should be extended to detect `Win10` from the offline registry for Win10 deployments

**External dependencies:**

- 7-Zip at `X:\Program Files\7-Zip\7z.exe` or `C:\Program Files\7-Zip\7z.exe`
- Network share or DEPLOY USB

**Environment variables:**

- Reads `OSDTargetSystemDrive` if present

**Exit codes:** Returns normally.

**Known limitations:**

- `Get-OSFamily` currently hardcodes `Win11`. **This is a latent bug for Win10 deployments** — the Win10 task sequence will look in the Win11 driver pack folder. Fix: read the target OS from the offline registry's `CurrentBuildNumber`.
- Model matching relies on exact or partial string matches. Unknown models (custom builds, whitebox) fall through without a driver pack.
- The archive selection is heuristic — if a similarly named archive exists for a different model, it may be picked.

---

### ApplyOEMDrivers.ps1

**Purpose:** Applies extracted OEM, WLAN, and Intel VMD drivers to the offline Windows image via DISM.

**When it runs:** Install phase, after `ExtractOEMDrivers.ps1`.

**What it does:**

1. Locates the Windows image path (via `OSDTargetSystemDrive` or by scanning).
2. If `C:\Recovery\OEM\Drivers` exists:
   - Reads CPU name from the registry (WinPE-safe).
   - Calls `Get-ProcessorArchitecture` to classify the CPU.
   - Calls `Get-Model` and `Get-Manufacturer` (registry-based).
   - Calls `Find-BestDriverFolder` to locate the model-specific driver folder inside `C:\Recovery\OEM\Drivers`.
   - Runs `DISM.exe /Add-Driver /Recurse` on the found folder with up to 3 retry attempts.
   - Applies WLAN drivers from `C:\Recovery\OEM\Drivers\WLAN` (if present).
   - If the CPU is Intel with a supported generation, applies Intel VMD drivers from `C:\Recovery\OEM\Drivers\Storage\Intel\<version>`.

**External dependencies:**

- `DISM` (in WinPE)
- Registry access

**Environment variables:**

- Reads `OSDTargetSystemDrive` if present

**Exit codes:** Returns normally. Logs failures but does not fail the task sequence step.

**Known limitations:**

- Silent — check `X:\MININT\SMSOSD\OSDLOGS\` or the DISM log at `C:\Windows\Logs\DISM\dism.log` for driver injection results.
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

**Environment variables:** None documented.

**Exit codes:** Uses `exit 1` on unrecoverable errors (missing Windows volume, missing WinRE image, hash mismatch). Otherwise returns normally.

**Known limitations:**

- **VMD marker persistence:** If `LoadWinPEDrivers.ps1` wrote the marker to `%TEMP%` in WinPE, `WinRE.ps1` (running in the full OS during Postinstall) will not find it. This is a known limitation — VMD driver injection into WinRE may not occur. Workaround: modify `LoadWinPEDrivers.ps1` to write the marker to `<Windows>\Temp\VMD_Loaded.txt`.
- Uses `Get-Volume -FileSystemLabel System` / `Recovery` without `Select-Object -First 1`. On systems with multiple partitions that share a label, this can return an array.
- Relies on partition labels. If a user renames a partition, the script fails silently.
- Deletes `<Windows>\Recovery\WindowsRE` and `<Windows>\Recovery\ReAgentOld.xml` after configuring the recovery partition.

---

### CleanupScripts.ps1

**Purpose:** Removes MDT artifacts from the deployed OS after deployment.

**When it runs:** Postinstall phase, after `Add Windows Recovery (WinRE)`.

**What it does:**

Deletes the following from the Windows drive:

- `_SMSTaskSequence`
- `MININT`
- `LTIBootstrap.vbs`

**External dependencies:** None.

**Environment variables:** None.

**Exit codes:** Returns normally.

**Known limitations:**

- Does not remove `C:\Windows\Temp\DeploymentLogs\`. Those persist for troubleshooting.
- Does not remove the OEM logs at `C:\ProgramData\OEM\Logs\`. Those are managed by `SetupComplete.cmd`.

---

### CopyOEM.wsf

**Purpose:** Copies `$OEM$\$1` and `$OEM$\$$` content to the target OS.

**When it runs:** Install phase, after `Apply Updates` and before `Extract OEM Apps`.

**What it does:**

Searches for the `$OEM$` folder in this order:

1. `<DeployRoot>\Control\<TaskSequenceID>\$OEM$`
2. `<SourcePath>\$OEM$`
3. `<DeployRoot>\<Architecture>\$OEM$`
4. `<DeployRoot>\$OEM$`

Then:

- Copies `<sOEM>\$1\*` to `<OSDrive>\` (the root of the Windows volume).
- Copies `<sOEM>\$$\*` to `<OSDrive>\Windows\`.

**External dependencies:** MDT's `ZTIUtility.vbs` and `ZTIDiskUtility.vbs`.

**Environment variables:**

- `DeployRoot`
- `TaskSequenceID`
- `SourcePath`
- `Architecture`

**Exit codes:** Returns normally.

**Known limitations:**

- Based on Michael Niehaus's original `CopyOEM.wsf` (from MDT 2012 Update 1). Not modified from the original.
- If no `$OEM$` folder exists, exits silently.

---

## $OEM$ Orchestration Scripts

Located under `$OEM$\$$\Setup\` — this path is copied to `C:\Windows\Setup\` on the target, where Windows automatically runs `SetupComplete.cmd` at the end of OOBE.

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
5. After all three, cleans up MDT artifacts (`_SMSTaskSequence`, `MININT`, `LiteTouch.lnk`, `LTIBootstrap.vbs`).
6. Sets hidden attributes on the Default user profile folders.
7. Logs completion.

Each child script is run via `powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass`, with stdout/stderr redirected to the log file.

**External dependencies:** PowerShell 5.1 (present in Windows).

**Environment variables:**

- `%ProgramData%`
- `%SystemDrive%`
- `%COMPUTERNAME%`

**Exit codes:**

- Always exits `0` — the deployment itself has completed successfully even if the OEM scripts fail.
- Individual script exit codes are captured via `ERRORLEVEL` and logged.

**Known limitations:**

- If `pre.ps1` hangs (e.g. waiting on user input), `SetupComplete.cmd` will wait indefinitely. The `-NonInteractive` flag on the PowerShell invocation mitigates this, but not completely.
- The `Set-RegistryValue` calls inside `pre.ps1` can fail silently if the Default user hive is not mounted. The script mounts it explicitly via `reg LOAD`.

---

## $OEM$ Configuration Scripts

Located under `$OEM$\$1\Recovery\OEM\`.

---

### pre.ps1

**Version:** 2.2.0

**Purpose:** Master OEM configuration script. Installs drivers, applies LGPO, activates Windows and Office, installs third-party applications, and configures system settings.

**When it runs:** OOBE, via `SetupComplete.cmd`.

**What it does, in order:**

1. Starts a transcript log at `C:\ProgramData\OEM\Logs\pre_<timestamp>.log`.
2. Waits for the system CPU to settle (via `Wait-SystemIdle`).
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
18. Removes legacy Win10 apps: `windowscommunicationsapps`, `People`, `Office.OneNote`.
19. Installs media extensions: AV1, HEIF, HEVC, MPEG2, RawImage, VP9, WebMedia, Webp.
20. Installs and configures AnyDesk.
21. Installs and configures RustDesk.
22. Installs 7-Zip.
23. Installs WinRAR and applies registry.
24. Installs DymaxIO and applies license.
25. Installs Acronis Drive Monitor (only if a spinning HDD is present).
26. Enables Windows RE if disabled.
27. Creates the `OEM\Update` scheduled task from `Update.xml`.
28. Sets hidden attributes on `C:\ProgramData`, `C:\Users\Default`, etc.
29. Cleans up `_SMSTaskSequence`, `MININT`, `LTIBootstrap.vbs`.
30. Writes an installation summary to the transcript.
31. Stops the transcript.

**External dependencies:**

- 7-Zip at `C:\Program Files\7-Zip\7z.exe`
- PowerShell 5.1
- Internet access (for Ohook, HWID activation)
- `pnputil`, `dism`, `reg`, `cmd`, `powershell` available on PATH
- `C:\Recovery\OEM\Activation\HWID_Activation.cmd`
- `C:\Recovery\OEM\Activation\Ohook_Activation.cmd`
- `C:\Recovery\OEM\LGPO\LGPO.exe`
- `C:\Recovery\OEM\Apps\*` (installers)
- `C:\Recovery\OEM\Drivers\*` (extracted driver packs)

**Environment variables:** Reads system environment variables, does not set any that persist.

**Exit codes:** Never `exit`s on failure. A top-level `try/catch` logs errors and continues, so `SetupComplete.cmd` proceeds to `Customizations.ps1` and `pbr.ps1`.

**Hardening notes (from inline version history):**

- v2.1.0: Transcript wrapped in try/finally; RustDesk/AnyDesk installers poll for binary presence; logs consolidated.
- v2.1.1: `Get-Counter` in `Wait-SystemIdle` wrapped in try/catch with WMI and fixed-delay fallbacks; top-level catch added so terminating errors don't kill downstream scripts.
- v2.2.0: Office activation gated by `Test-OfficeSafeForActivation` (fail-closed); `Test-OfficeInstalled` reads the `Path` value instead of testing for a subkey; `Get-OfficeInstallerFolder` sorts by `LastWriteTime`; `Activate-Windows` captures `/ipk` and `/ato` exit codes separately and falls through to HWID; `Install-Office` passes `-WorkingDirectory`.

**Known limitations:**

- **AnyDesk password hardcoded** as `$AnyDeskPassword = 'p@$$w0rd'`. Change this before using AnyDesk in any environment other than an isolated lab.
- ~1000+ lines. Refactor candidate (see CONTRIBUTING.md "Areas Where Help Is Needed").
- UWP version guard `Skip-IfNewerProvisioned` requires the package filename to contain a version string in the format `_X.Y.Z.W_` (four parts). Packages without a versioned filename are always installed.
- The Ohook activation is deferred if any Office application is running in an interactive user session. This is by design, but may leave Office unactivated if a user has Office open during OOBE.
- `Wait-SystemIdle` uses WMI `Win32_Processor.LoadPercentage` as a fallback. On machines where WMI is also broken, it sleeps for 5 seconds and returns.

---

### Customizations.ps1

**Purpose:** Additional OEM customizations beyond what `pre.ps1` handles.

**When it runs:** OOBE, via `SetupComplete.cmd`, after `pre.ps1`.

**What it does:** Not shipped with this repository. Placeholder for user-supplied customizations. If the file is absent, `SetupComplete.cmd` skips it.

**External dependencies:** User-defined.

**Known limitations:** Not documented here because it is a placeholder. See your own implementation.

---

### Apps\pbr.ps1

**Purpose:** Creates the push-button reset provisioned package.

**When it runs:** OOBE, via `SetupComplete.cmd`, after `Customizations.ps1`.

**What it does:** Uses `ScanState` to create a provisioned package at `C:\Recovery\OEM\Apps\<package>` that Windows can use for push-button reset.

**External dependencies:**

- `ScanState` (from USMT)
- `C:\Recovery\OEM\Apps\` write access

**Known limitations:**

- Not shipped in this repository — extract `ScanState` from the companion content.
- If `ScanState` is missing, the script logs an error and continues.

---

## $OEM$ Activation Scripts

Located under `$OEM$\$1\Recovery\OEM\Activation\`.

---

### HWID_Activation.cmd

**Purpose:** HWID-based Windows activation fallback.

**When it runs:** Called by `pre.ps1` when the firmware OEM key activation fails.

**What it does:** Runs Microsoft's HWID activation script (the standard HWID activation flow that contacts Microsoft's activation servers and applies a digital license tied to the hardware).

**External dependencies:** Internet access.

**Exit codes:** Passed through to `pre.ps1` — `pre.ps1` returns `$true` from `Activate-Windows` regardless of the outcome of this call.

**Known limitations:**

- Requires internet connectivity.
- HWID activation only works on hardware that has a Windows 10 or Windows 11 digital license embedded by the OEM.

---

### Ohook_Activation.cmd

**Purpose:** Office activation via Ohook.

**When it runs:** Called by `pre.ps1` when Office is installed and `Test-OfficeSafeForActivation` returns `$true`.

**What it does:** Runs the Ohook activation tool with the `/Ohook` switch.

**External dependencies:**

- Office installed on the target machine.

**Exit codes:** `0` on success, non-zero on failure. Captured by `pre.ps1` and logged.

**Known limitations:**

- **Ohook is not a legitimate activation method.** In environments where license compliance is enforced, replace this with a volume license or Microsoft 365 subscription activation. This script is provided as-is for lab and personal use only.
- Ohook modifies Office binaries in memory. Antivirus software may flag it. `pre.ps1` adds an exclusion for the script path, but not for the activated Office binaries.
- Office updates can break Ohook. Re-application may be needed after major Office updates.

---

## $OEM$ Payload Updaters

Located under `$OEM$\$1\Recovery\OEM\`. All are idempotent and use hash-verified downloads.

---

### Apps.ps1

**Version:** 2.2

**Purpose:** Downloads and extracts the latest Apps `.7z` split archive.

**When it runs:** Not part of the deployment task sequence by default — invoked manually or via `pbr.ps1` to refresh the OEM app payload.

**What it does:**

1. Reads the current SHA-256 from `C:\Recovery\OEM\Logs\Apps.7z.sha256`.
2. Fetches the expected SHA-256 from `https://gist.github.com/52250179/74758d92957c683c282c2670892609f6/raw`.
3. If they match, exits immediately.
4. Otherwise:
   - Queries `https://api.github.com/repos/52250179/Update-PBR-Extensibility-Apps/contents/` for files matching `^Apps\.7z\.\d+$`.
   - Sorts parts by their numeric suffix.
   - Downloads each part with retry and dual-URL fallback:
     - Primary: `raw.githubusercontent.com`
     - Fallback: `github.com/.../raw/refs/heads/...`
   - Rejects HTML error pages served with HTTP 200.
   - Validates the split archive with `7z t` on the first part.
   - Extracts to `C:\Temp\OEM\Apps`.
   - Removes downloaded parts.
   - Writes the new hash to `C:\Recovery\OEM\Logs\Apps.7z.sha256`.

**External dependencies:**

- 7-Zip at `C:\Program Files\7-Zip\7z.exe`
- Internet access
- `C:\Temp\OEM\` write access
- `C:\Recovery\OEM\Logs\` write access

**Environment variables:** None.

**Exit codes:**

- `0` — Archive already up to date (no action) OR update completed successfully.
- `1` — 7-Zip missing, hash retrieval failed, file listing failed, download failed, validation failed, or extraction failed.

**Log location:** `C:\ProgramData\OEM\Logs\AppsArchive_<timestamp>.log`

**Known limitations:**

- Depends on a third-party GitHub repository (`52250179/Update-PBR-Extensibility-Apps`) and Gist. If either becomes unavailable, the script fails.
- No integrity verification of individual parts against a manifest — only the assembled archive is tested with `7z t`.
- Downloaded files are staged in `C:\Temp\OEM` (system drive), not in a location with more space. Large payloads can fill the system drive.

---

### Drivers.ps1

**Version:** 2.2

**Purpose:** Downloads and extracts the latest Drivers `.7z` split archive.

Behaviour identical to `Apps.ps1`, with:

- Gist: `https://gist.github.com/52250179/4bc89a7d30e566d842f1aaabaaae14b0/raw`
- Repo: `52250179/Update-PBR-Extensibility-Drivers`
- File pattern: `^Drivers\.7z\.\d+$`
- Extract destination: `C:\Temp\OEM\Drivers`
- Hash file: `C:\Recovery\OEM\Logs\Drivers.7z.sha256`
- Log: `C:\ProgramData\OEM\Logs\DriversArchive_<timestamp>.log`

---

### LGPO.ps1

**Version:** 2.2

**Purpose:** Downloads and extracts the latest `LGPO.7z`.

Differs from `Apps.ps1` / `Drivers.ps1` because LGPO is a single `.7z` file, not a split archive.

- Gist: `https://gist.github.com/52250179/54cdfbe3d739441aad395e16afbf9bc2/raw`
- Direct URLs (dual fallback):
  - `https://raw.githubusercontent.com/52250179/Update-PBR-Extensibility-LGPO/main/LGPO.7z`
  - `https://github.com/52250179/Update-PBR-Extensibility-LGPO/raw/refs/heads/main/LGPO.7z`
- Extract destination: `C:\Temp\OEM\LGPO`
- Hash file: `C:\Recovery\OEM\Logs\LGPO.7z.sha256`
- Log: `C:\ProgramData\OEM\Logs\LGPOArchive_<timestamp>.log`

Extraction is retried up to 3 times.

---

## $OEM$ Application Configurators

Located under `$OEM$\$1\Recovery\OEM\Apps\`.

---

### RustDesk.ps1

**Purpose:** Applies RustDesk configuration after installation.

**When it runs:** Called by `pre.ps1` via a separate `powershell.exe` process (to isolate its `exit` calls).

**What it does:** Reads configuration from a companion file (relay server, API key, default password), applies it to `C:\Program Files\RustDesk\config\`, and configures the service for persistence.

**Exit codes (interpreted by `pre.ps1`):**

- `0` — Full success (persistence configured)
- `1` — Partial success (config file written, persistence failed)
- `2` — Complete failure
- Any other — Unknown error

**Known limitations:**

- Runs in a separate process to prevent its `exit` from killing `pre.ps1`.
- Behavior depends on RustDesk version. Newer versions may have moved config paths.

---

### DymaxIOLicense.ps1

**Purpose:** Applies the DymaxIO license after installation.

**When it runs:** Called by `pre.ps1` via a separate `powershell.exe` process.

**What it does:** Invokes DymaxIO's licensing executable with the license key.

**Exit codes (interpreted by `pre.ps1`):**

- `0` — License applied successfully
- `2` — DymaxIO not installed (skipped)
- Other — Failure

**Known limitations:** Requires DymaxIO to be installed. If DymaxIO is not present, the script is a no-op (exit code 2).

---

### Update.xml

**Purpose:** Task Scheduler definition for the `OEM\Update` scheduled task.

**When it runs:** Imported by `pre.ps1` via `schtasks /create /tn OEM\Update /xml <path> /f`.

**What it does:** Defines a task that re-runs `Apps.ps1`, `Drivers.ps1`, and `LGPO.ps1` periodically to keep OEM payloads up to date.

**Known limitations:**

- Not a script — this is a Task Scheduler XML definition.
- The task runs as SYSTEM with highest privileges.

---

## $OEM$ Post-Deployment Scripts

Located under `$OEM$\$1\Scripts\`. These are copied to the deployed OS at `C:\Scripts\` and are intended to be run manually by the technician after OOBE completes.

---

### OEMDriversExport.ps1

**Purpose:** Exports drivers from the deployed OS, archives them as `.7z`, and copies to a network share or DEPLOY USB.

**When it runs:** Manually, via `C:\Scripts\3OEMDriversExport.cmd`.

**What it does:**

1. Runs `Export-WindowsDriver` to extract all third-party drivers from the offline image.
2. Archives the extracted drivers as a `.7z` file.
3. Copies the archive to `\\SERVER\Shared\DriverPacks` (or a DEPLOY USB).

**External dependencies:**

- 7-Zip installed on the target machine
- Network share accessible, or DEPLOY USB inserted

**Known limitations:**

- Requires elevated privileges.
- The exported archive name is auto-generated from the model; the naming may not perfectly match the pattern expected by `ExtractOEMDrivers.ps1` on subsequent deployments. Manual renaming may be required.

---

### ScanWindowsImage64.ps1

**Purpose:** Cleans the Driver Store and restores the `Microsoft-OneCore-DirectX-Database-FOD-Package`.

**When it runs:** Manually, via `C:\Scripts\2CleanupDriverStore.cmd`.

**What it does:**

1. Runs DISM `/Cleanup-Image` with `/StartComponentCleanup /ResetBase`.
2. Cleans the Driver Store of unused drivers.
3. Reinstalls the `Microsoft-OneCore-DirectX-Database-FOD-Package` from `\\SERVER\Shared\Servicing\` or a DEPLOY USB. This is required because cleaning the driver store in Windows 11 removes this package, which breaks some DirectX features.

**External dependencies:**

- DISM
- `\\SERVER\Shared\Servicing\Microsoft-OneCore-DirectX-Database-FOD-Package` or DEPLOY USB

**Known limitations:**

- `/ResetBase` makes installed Windows updates non-removable.
- Requires elevated privileges.
- Restoring the DirectX FOD requires the correct architecture version.

---

### ScanStatex64.ps1

**Purpose:** Creates a provisioned package for push-button reset.

**When it runs:** Manually, via `C:\Scripts\4ScanState.cmd`.

**What it does:**

1. Copies `ScanState` from `\\SERVER\Shared\ScanState` or a DEPLOY USB to `C:\Temp\ScanState`.
2. Runs `ScanState` to create a provisioned package for push-button reset.
3. Places the package at a location Windows recognizes for reset purposes.

**External dependencies:**

- `\\SERVER\Shared\ScanState` or DEPLOY USB
- `C:\Temp\` write access

**Known limitations:**

- `ScanState` must match the target OS architecture (x64 for x64 OS).
- The provisioned package takes disk space on the target machine — the size depends on the amount of user data captured.

---

## Common Patterns

All scripts in this repository follow these patterns. Deviations are documented in the script's own header.

### Retry logic

DISM and robocopy operations retry up to 3 times with exponential backoff (delay multiplies by 1.5 each attempt, capped at 30–60 seconds).

### Path resolution

Scripts never hardcode drive letters. Volume letters are resolved via `Get-Volume -FileSystemLabel <label> | Select-Object -First 1`.

### Primary/fallback sources

Scripts that read network shares always fall back to a DEPLOY-labeled USB flash drive if the share is unreachable.

### Idempotence

Payload updaters (`Apps.ps1`, `Drivers.ps1`, `LGPO.ps1`) compare the local SHA-256 to the remote SHA-256 and exit early if unchanged.

### Silent operation

Scripts in `Scripts\Custom\` avoid `Write-Host`. Scripts in `$OEM$` may use `Write-Host` for progress because they run in OOBE with no task sequence UI.

---

## Log File Locations

| Context | Location |
|---|---|
| Task sequence (WinPE) | `X:\MININT\SMSOSD\OSDLOGS\` |
| Task sequence (full OS) | `C:\MININT\SMSOSD\OSDLOGS\` |
| MDT deployment summary | `C:\Windows\Temp\DeploymentLogs\` |
| OEM setup (post-OOBE) | `C:\ProgramData\OEM\Logs\` |
| Payload updaters | `C:\ProgramData\OEM\Logs\AppsArchive_*.log`, `DriversArchive_*.log`, `LGPOArchive_*.log` |
| `pre.ps1` transcript | `C:\ProgramData\OEM\Logs\pre_<timestamp>.log` |
| `SetupComplete.cmd` | `C:\ProgramData\OEM\Logs\SetupComplete.log` |
| DISM (offline image) | `C:\Windows\Logs\DISM\dism.log` (post-deployment) |
| DISM (WinRE) | `C:\Temp\WinREWork\dism_driver.log` (during `WinRE.ps1`) |
| BDD.log (task sequence) | `X:\MININT\SMSOSD\OSDLOGS\BDD.log` (WinPE) or `C:\MININT\SMSOSD\OSDLOGS\BDD.log` (full OS) |

---

*See [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common errors and their fixes.*
