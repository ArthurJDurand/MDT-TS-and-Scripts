# OEM Content Guide

This document describes how OEM content — driver packs, application archives, activation scripts, updates, and supporting tools — is organized on the network shares and on offline media, how the scripts consume it, and how to add new packs.

The scripts never hardcode model-specific content. They detect the target hardware at deployment time and pull the matching pack from a known folder. This document is the reference for what those folders should look like.

---

## Table of Contents

- [Overview](#overview)
- [Where OEM Content Lives](#where-oem-content-lives)
- [Network Share Layout](#network-share-layout)
- [Offline Media Layout](#offline-media-layout)
- [Directory Reference](#directory-reference)
  - [OEM Apps](#oem-apps)
  - [Driver Packs](#driver-packs)
  - [LGPO](#lgpo)
  - [Updates](#updates)
  - [WindowsRE](#windowsre)
  - [Servicing](#servicing)
  - [ScanState](#scanstate)
- [Archive Naming Conventions](#archive-naming-conventions)
- [Driver Pack Structure](#driver-pack-structure)
- [App Pack Structure](#app-pack-structure)
- [Vendor Detection](#vendor-detection)
- [Adding a New OEM App Pack](#adding-a-new-oem-app-pack)
- [Adding a New Driver Pack](#adding-a-new-driver-pack)
- [Updating an Existing Driver Pack](#updating-an-existing-driver-pack)
- [Payload Updaters and Companion Repos](#payload-updaters-and-companion-repos)
- [Best Practices](#best-practices)

---

## Overview

The OEM content is what makes this project more than a stock MDT deployment. It provides:

- **Model-specific driver packs** — extracted and injected into the offline image during deployment
- **Manufacturer-specific application packs** — extracted into `C:\Recovery\OEM` on the target and installed during OOBE
- **Activation scripts** — HWID and Ohook for Windows and Office
- **Local Group Policy** — LGPO tool and policy backups
- **Windows Recovery Environment** — WinRE images for BIOS/UEFI systems
- **Offline servicing components** — DirectX FOD package for driver store cleanup
- **ScanState** — USMT tool for push-button reset package creation
- **Windows updates** — cumulative updates and .msu/.cab packages for offline image injection

None of this content is stored in Git. It is distributed via the [companion OneDrive folder](https://1drv.ms/u/s!AgS7zfLQOVekkLIt0kn2tt8g-8WNAg?e=4ziRu6) and can be delivered either from a network share or from a DEPLOY-labeled USB flash drive for offline deployments.

---

## Where OEM Content Lives

OEM content is consumed from two locations, in this priority order:

| Priority | Location | Used When |
|---|---|---|
| 1 | **Network share** | The deployment has network connectivity (server-based or desktop-based PXE) |
| 2 | **DEPLOY USB flash drive** | The deployment is fully offline (no server, no network) |

Every extraction script checks the network share first and falls back to the USB. You can populate both, or just one.

### Network shares

| Share | Purpose |
|---|---|
| `\\SERVER\Shared\OEM\x64` | 64-bit OEM application archives |
| `\\SERVER\Shared\OEM\x86` | 32-bit OEM application archives (if any) |
| `\\SERVER\Shared\DriverPacks` | Model-specific driver `.7z` archives |
| `\\SERVER\Shared\Updates\Win10\x64` | Windows 10 x64 cumulative updates |
| `\\SERVER\Shared\Updates\Win10\x86` | Windows 10 x86 cumulative updates |
| `\\SERVER\Shared\Updates\Win11` | Windows 11 cumulative updates |
| `\\SERVER\Shared\WindowsRE\<OS>\<arch>` | WinRE images |
| `\\SERVER\Shared\Servicing` | Offline servicing components (DirectX FOD) |
| `\\SERVER\Shared\ScanState` | USMT ScanState tool |
| `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<version>` | Intel VMD drivers for WinPE boot image |

> **Note:** The path for OEM apps is `\\SERVER\Shared\OEM\x64` in the scripts. If your deployment was set up with `\\SERVER\OEM` as a standalone share, either create the `Shared\OEM` structure or edit `Get-SourceOEMAppPath` in `ExtractOEMAppsx64.ps1` and `ExtractOEMAppsx86.ps1` to match your layout.

### Share permissions

All shares are **read-only** for the deployment service account. No write access is required during deployment.

| Share | Permission |
|---|---|
| `\\SERVER\Shared` | `Network User` — Read |
| `\\SERVER\Shared\OEM` | `Network User` — Read |
| `\\SERVER\Shared\DriverPacks` | `Network User` — Read, `Administrators` — Full |
| `\\SERVER\Shared\Updates` | `Network User` — Read |
| `\\SERVER\Shared\WindowsRE` | `Network User` — Read |
| `\\SERVER\Shared\Servicing` | `Network User` — Read |
| `\\SERVER\Shared\ScanState` | `Network User` — Read |

---

## Network Share Layout

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
│       └── (x86 app packs if you support 32-bit hardware)
│
├── DriverPacks\
│   ├── Dell Latitude 5430 12th Gen Intel.7z
│   ├── Dell Latitude 5430.7z
│   ├── HP EliteBook 840 G9.7z
│   ├── HP EliteBook 840 G10 13th Gen Intel.7z
│   ├── Lenovo ThinkPad T14 Gen 3.7z
│   └── ... (one .7z per supported model)
│
├── Updates\
│   ├── Win10\
│   │   ├── x64\
│   │   │   ├── windows10.0-kb50xxxxx-x64.msu
│   │   │   └── ... (all cumulative and SSU packages)
│   │   └── x86\
│   │       └── ...
│   └── Win11\
│       ├── windows11.0-kb50xxxxx-x64.msu
│       └── ... (all cumulative and SSU packages)
│
├── WindowsRE\
│   ├── Win10\
│   │   ├── x64\
│   │   │   └── winre.wim
│   │   └── x86\
│   │       └── winre.wim
│   └── Win11\
│       └── x64\
│           └── winre.wim
│
├── Servicing\
│   └── Microsoft-OneCore-DirectX-Database-FOD-Package\
│       ├── Microsoft-OneCore-DirectX-Database-FOD-Package~31bf3856ad364e35~amd64~~.cab
│       └── ... (any dependencies)
│
├── ScanState\
│   ├── amd64\
│   │   ├── scanstate.exe
│   │   └── ... (USMT components)
│   └── x86\
│       ├── scanstate.exe
│       └── ... (USMT components for x86)
│
└── Drivers\
    └── WinPE\
        └── Storage\
            └── Intel\
                └── x64\
                    ├── 19.5.8.1059.2\    (Intel 11th Gen VMD)
                    │   ├── iaStorVD.inf
                    │   └── ...
                    └── 20.2.6.1025.3\    (Intel 12th Gen+ VMD)
                        ├── iaStorVD.inf
                        └── ...
```

---

## Offline Media Layout

For deployments without a server, the same content lives on a USB flash drive labeled `DEPLOY` (FAT32, active partition). The scripts detect this drive by label and pull content from it.

```
DEPLOY (USB root)\
├── OEM\
│   ├── x64\
│   │   └── ... (same .7z archives as the network share)
│   └── x86\
│       └── ...
│
├── DriverPacks\
│   └── ... (same .7z driver archives)
│
├── Updates\
│   ├── Win10\
│   │   ├── x64\
│   │   └── x86\
│   └── Win11\
│
├── WindowsRE\
│   └── ... (same structure as network share)
│
├── Servicing\
│   └── Microsoft-OneCore-DirectX-Database-FOD-Package\
│
├── ScanState\
│   └── ... (amd64 and x86 subfolders)
│
└── Content\
    └── ... (MDT offline media payload — this is what gets written by MDT when you generate media)
```

The USB drive is FAT32, which has a **4 GB per-file limit**. Any archive larger than 4 GB must be split into `.7z.001`, `.7z.002`, ... parts. The payload updater scripts split files automatically when generating archives.

> **NTFS alternative:** If your target machines support UEFI NTFS boot, you can format the USB as NTFS and skip the split-archive complexity. However, most pre-UEFI hardware will not boot from an NTFS USB drive, and the MDT boot image layout assumes FAT32.

---

## Directory Reference

### OEM Apps

**Path:** `\\SERVER\Shared\OEM\x64` or `\\SERVER\Shared\OEM\x86` (or `DEPLOY:\OEM\x64`)
**Consumed by:** `ExtractOEMAppsx64.ps1`, `ExtractOEMAppsx86.ps1`
**Extracted to:** `C:\Recovery\OEM` on the target

**Purpose:** Per-vendor application installers, bundled as `.7z` archives. The correct archive is selected by matching the target machine's manufacturer string.

**Contents of each `.7z`:** Whatever you want installed on the target. By convention:

```
<vendor>.7z
├── Apps\
│   ├── <vendor>CommandUpdate.exe
│   ├── <vendor>SupportAssistant.exe
│   └── ... (OEM utilities)
├── LGPO\
│   └── ... (vendor-specific policy files)
├── pre.ps1            (optional vendor-specific setup script)
└── ... (any other content)
```

The exact structure inside the `.7z` is up to you — `ExtractOEMAppsx64.ps1` simply extracts the archive into `C:\Recovery\OEM`, preserving the internal folder structure.

**One `.7z` per vendor.** The scripts do not combine archives.

### Driver Packs

**Path:** `\\SERVER\Shared\DriverPacks` (or `DEPLOY:\DriverPacks`)
**Consumed by:** `ExtractOEMDrivers.ps1`
**Extracted to:** `C:\Recovery\OEM\Drivers` on the target

**Purpose:** One archive per supported model, containing all drivers for that model. The correct archive is selected by matching the target machine's model and CPU generation against the archive filename.

**Naming convention:** The filename is the primary matching surface. See [Archive Naming Conventions](#archive-naming-conventions) for the exact patterns the scripts use.

### LGPO

**Path:** Downloaded by `LGPO.ps1` from the companion repo, extracted to `C:\Temp\OEM\LGPO`
**Consumed by:** `pre.ps1` (looks in `C:\Recovery\OEM\LGPO\LGPO.exe`)
**Purpose:** The Microsoft Local Group Policy Object utility plus a `Backup` folder containing `.pol` files that LGPO applies.

**Structure after staging:**

```
C:\Recovery\OEM\LGPO\
├── LGPO.exe
├── Backup\
│   ├── {GUID}\DomainSysvol\GPO\User\...
│   └── {GUID}\DomainSysvol\GPO\Machine\...
└── (any other policy files)
```

**Applying policies:** `pre.ps1` runs:

```powershell
LGPO.exe /g C:\Recovery\OEM\LGPO\Backup
```

**Creating your own policy backup:** On a reference machine with the policies you want applied, run:

```powershell
LGPO.exe /b C:\LGPO-Backup
```

Then replace the contents of `Backup\` in your staged `LGPO` folder with the generated files.

### Updates

**Path:** `\\SERVER\Shared\Updates\Win10\x64`, `\\SERVER\Shared\Updates\Win10\x86`, or `\\SERVER\Shared\Updates\Win11`
**Consumed by:** `ApplyUpdates10x64.ps1`, `ApplyUpdates10x86.ps1`, `ApplyUpdates11.ps1`
**Applied to:** the offline Windows image via DISM, before first boot

**Purpose:** Cumulative updates, servicing stack updates, .NET updates, and any other `.msu` or `.cab` packages you want baked into the image.

**Sources:**

- [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/) — download cumulative updates and SSUs directly
- [WSUS Offline Update](http://www.wsusoffline.net/) — a well-known tool that downloads all updates for a target OS
- Your existing WSUS server export

**Important:** Only `.msu` and `.cab` files are processed. Any other file format is ignored.

**Order of application:** DISM applies all `.msu`/`.cab` files in the folder in alphabetical order. This matters because some updates depend on prior updates (e.g. cumulative updates require the latest SSU). Name files with a numeric prefix to enforce order if needed:

```
01-ssu-2024-11-x64.msu
02-cumulative-2024-11-x64.msu
03-netfx-2024-11-x64.msu
```

### WindowsRE

**Path:** `\\SERVER\Shared\WindowsRE\<Win10|Win11>\<x64|x86>\winre.wim`
**Consumed by:** `WinRE.ps1`
**Copied to:** `C:\Recovery\WindowsRE\winre.wim` on the target's recovery partition

**Purpose:** A WinRE image for each OS and architecture. `WinRE.ps1` first tries to use the WinRE already present inside the deployed OS (`C:\Windows\System32\Recovery\winre.wim`). The network-share copy is a fallback used when the OS image has no WinRE or when the deployed WinRE is corrupt.

**Where to get the WinRE image:**

- Extract it from a clean Windows ISO: `install.wim` → `Windows\System32\Recovery\winre.wim`
- Or from the `WinRE.wim` inside the `sources\` folder of a Windows ISO

**Optional VMD injection:** If `LoadWinPEDrivers.ps1` wrote a `VMD_Loaded.txt` marker during deployment, `WinRE.ps1` will inject the same Intel VMD driver into the WinRE image. This is needed on newer Intel platforms where WinRE must see the internal storage to function. See the "Known Limitations" section of the [README](../README.md#known-limitations) for a caveat about marker persistence.

### Servicing

**Path:** `\\SERVER\Shared\Servicing`
**Consumed by:** `ScanWindowsImage64.ps1`
**Purpose:** Offline servicing components needed to restore the DirectX FOD after driver store cleanup.

**Structure:**

```
\\SERVER\Shared\Servicing\
└── Microsoft-OneCore-DirectX-Database-FOD-Package\
    ├── Microsoft-OneCore-DirectX-Database-FOD-Package~31bf3856ad364e35~amd64~~.cab
    └── ... (dependencies if any)
```

**Background:** `ScanWindowsImage64.ps1` runs `DISM /Cleanup-Image /ResetBase` followed by a driver store cleanup. On Windows 11, the driver store cleanup removes the DirectX FOD package, which breaks some DirectX features. The script restores the package from this folder.

**Where to get the FOD package:** The package is included in this repository's companion OneDrive folder under `Shared\Servicing`.

### ScanState

**Path:** `\\SERVER\Shared\ScanState`
**Consumed by:** `ScanStatex64.ps1`
**Copied to:** `C:\Temp\ScanState` on the target
**Purpose:** The USMT `ScanState` tool, used to create a push-button reset provisioned package.

**Structure:**

```
\\SERVER\Shared\ScanState\
├── amd64\
│   ├── scanstate.exe
│   ├── migcore.dll
│   ├── ... (all USMT amd64 components)
└── x86\
    ├── scanstate.exe
    ├── ... (all USMT x86 components)
```

**Where to get USMT:** USMT is part of the Windows ADK. After installing the ADK, the tool is at `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool\<version>\`.

Copy both the `amd64` and `x86` folders into `\\SERVER\Shared\ScanState`.

---

## Archive Naming Conventions

The scripts select archives by filename pattern matching. The naming convention is not enforced by any code — it is a convention you must follow for the matching to work.

### OEM App Archives

**Pattern:** `<Vendor>.7z` or `<Vendor>.7z.001`, `.002`, ...

**Examples:**

```
Dell.7z
HP.7z
Lenovo.7z.001
Lenovo.7z.002
Lenovo.7z.003
```

**Vendor names the scripts recognize:** `Acer`, `ASUS`, `Dell`, `Dynabook`, `Gigabyte`, `HP` / `Hewlett Packard` / `Hewlett-Packard`, `Huawei`, `Lenovo`, `Microsoft`, `Micro-Star` / `MicroStar` / `MSI`, `Proline`.

The match is case-insensitive and substring-based. A manufacturer string of `"HP"` matches the `HP.7z` archive. A manufacturer string of `"Hewlett-Packard Company"` also matches, because the pattern checks for `Hewlett-Packard` as a substring.

### Driver Pack Archives

**Pattern:** Free-form. The script generates candidate patterns from the detected model and CPU generation. See [Driver Pack Structure](#driver-pack-structure) for the exact matching logic.

**Recommended conventions:**

- `<Vendor> <Model> <Gen>th Gen Intel.7z` — most specific, preferred
- `<Vendor> <Model>.7z` — model-only match, used as fallback
- `<Vendor> <Series> <Gen>th Gen Intel.7z` — for series-wide packs (e.g. `HP EliteBook 8xx 12th Gen Intel.7z`)

**Examples:**

```
Dell Latitude 5430 12th Gen Intel.7z
Dell Latitude 5430.7z
HP EliteBook 840 G10 13th Gen Intel.7z
HP EliteBook 840 G10.7z
Lenovo ThinkPad T14 Gen 3 12th Gen Intel.7z
```

**Split archives:** If a driver pack exceeds 4 GB, split it with 7-Zip's volume feature. The script discovers parts by matching `^<ArchiveName>\.7z\.\d+$`.

### Split Archive Parts

**Format:** `<ArchiveName>.7z.001`, `.002`, `.003`, ...

Split archives are treated as a single logical archive by the scripts. `ExtractOEMDrivers.ps1` and the payload updaters:

1. Sort all parts by their numeric suffix.
2. Download or copy all parts.
3. Validate with `7z t <first-part>`.
4. Extract with `7z x <first-part>` — 7-Zip reads the split volume from `.001` and continues automatically.

**Creating split archives:**

```powershell
# Split Dell.7z into 3 GB parts
7z a -v3g "Dell.7z" "C:\Staging\Dell\"
```

This produces `Dell.7z.001`, `Dell.7z.002`, etc. The 3 GB part size leaves headroom for FAT32's 4 GB limit.

---

## Driver Pack Structure

The scripts apply the driver pack by running DISM with `/Add-Driver /Recurse` on the extracted folder. That means the extracted folder can contain any number of subdirectories with `.inf` files, and DISM will recurse through all of them.

**Recommended structure inside each driver pack `.7z`:**

```
Dell Latitude 5430 12th Gen Intel.7z
├── Chipset\
│   ├── <inf files>
│   └── ...
├── Storage\
│   └── Intel\
│       └── <inf files>
├── Network\
│   ├── Ethernet\
│   └── WLAN\
├── Audio\
├── Graphics\
├── Bluetooth\
├── Camera\
├── CardReader\
└── ... (any other categories)
```

**WLAN special case:** `ApplyOEMDrivers.ps1` looks for a folder named `WLAN` under `C:\Recovery\OEM\Drivers` and applies it **in addition** to the model-specific folder. Place your WLAN drivers either inside the model pack (anywhere in the tree) or in a shared `WLAN\` folder that gets extracted alongside the model pack.

**Intel VMD special case:** `ApplyOEMDrivers.ps1` looks for Intel VMD drivers under `C:\Recovery\OEM\Drivers\Storage\Intel\<version>`. The `<version>` is determined by CPU generation:

| CPU Generation | VMD Driver Version |
|---|---|
| 11th Gen | `19.5.8.1059.2` |
| 12th Gen and above | `20.2.6.1025.3` |

Include the appropriate VMD folder in every driver pack for a 10th Gen+ Intel platform.

**Matching algorithm:** See the `Find-BestDriverFolder` function in `ExtractOEMDrivers.ps1` and `ApplyOEMDrivers.ps1`. It builds candidate folder names from the target model and CPU generation, then picks the first match found in `C:\Recovery\OEM\Drivers`.

---

## App Pack Structure

The scripts extract the vendor `.7z` into `C:\Recovery\OEM` without any filtering. Whatever is inside the archive gets placed on the target machine.

**Recommended structure:**

```
Dell.7z
├── Apps\
│   ├── DellCommandUpdate.exe
│   ├── DellDigitalDelivery.exe
│   ├── DellOptimizer.exe
│   ├── SupportAssist.exe
│   └── ...
├── LGPO\
│   ├── LGPO.exe
│   └── Backup\
│       └── ... (vendor-specific policy backup)
├── Activation\
│   ├── HWID_Activation.cmd
│   └── Ohook_Activation.cmd
├── Drivers\
│   └── ... (optional, if you want to bundle drivers with apps)
├── pre.ps1            (optional vendor-specific setup script)
└── ...
```

Anything under `Apps\` is available to `pre.ps1` (which scans `C:\Recovery\OEM\Apps\` for installers).

**Office installers:** `pre.ps1` calls `Get-OfficeInstallerFolder` which looks for a folder under `C:\Recovery\OEM\Apps\` starting with `Office`. By convention, name your Office installer folder `Office2021`, `Office365`, or similar.

---

## Vendor Detection

`ExtractOEMAppsx64.ps1` detects the manufacturer using three WMI/CIM sources:

```powershell
(Get-CimInstance Win32_BaseBoard).Manufacturer
(Get-CimInstance Win32_ComputerSystem).Manufacturer
(Get-CimInstance Win32_ComputerSystemProduct).Vendor
```

Values that match any of these are excluded as invalid:

```
Default string
Not Applicable
Not Available
System Manufacturer
To be filled by O.E.M.
```

The remaining values are grouped and the most frequent one is selected. If values disagree (e.g. baseboard says `ASUSTeK` but chassis says `ASUS`), the script picks whichever appears most often.

**Practical implications for OEM pack naming:**

- Use the vendor name as it appears in WMI, not the marketing name. `Hewlett-Packard` and `HP` both work because the match is substring-based. `Dell Inc.` matches `Dell`.
- If you have two similarly named vendors (`ASUS` and `ASUSTeK`), name your archive to match the most common string.

---

## Adding a New OEM App Pack

Suppose you want to add support for a new vendor, `Framework`.

### 1. Gather the installers

Download the vendor's utilities and save them into a staging folder:

```
C:\Staging\Framework\
├── Apps\
│   ├── FrameworkControlPanel.exe
│   └── FrameworkDriverBundle.exe
└── ...
```

### 2. Create the archive

```powershell
# Split into 3 GB parts for FAT32 compatibility
7z a -v3g "Framework.7z" "C:\Staging\Framework\"
```

This produces `Framework.7z.001`, `Framework.7z.002`, etc. (or a single `Framework.7z` if the content is under 3 GB).

### 3. Copy to the network share

```powershell
Copy-Item "Framework.7z*" "\\SERVER\Shared\OEM\x64\"
```

### 4. Copy to offline media (optional)

If you support offline deployments, copy the archive to the DEPLOY USB root at `OEM\x64\`.

### 5. Add the vendor to the extraction script

Open `\\SERVER\DeploymentShare\Scripts\Custom\ExtractOEMAppsx64.ps1` and find the `switch` statement that maps manufacturers to archives:

```powershell
$SourceOEMApps = switch -Wildcard ($Manufacturer) {
    {$_ -like '*Acer*'}     { Join-Path -Path $SourceOEMAppPath -ChildPath "Acer.7z" }
    {$_ -like '*ASUS*'}     { Join-Path -Path $SourceOEMAppPath -ChildPath "ASUS.7z" }
    # ... existing entries ...
    default                 { $null }
}
```

Add an entry for the new vendor:

```powershell
    {$_ -like '*Framework*'} { Join-Path -Path $SourceOEMAppPath -ChildPath "Framework.7z" }
```

### 6. Test

Deploy to a Framework machine and verify that `C:\Recovery\OEM\Apps\FrameworkControlPanel.exe` exists after OOBE.

---

## Adding a New Driver Pack

Suppose you want to add support for a new model, `Dell Latitude 7450` with a 13th Gen Intel CPU.

### 1. Download the vendor driver pack

From the vendor's support site, download the enterprise driver pack for that model. Dell, HP, and Lenovo all publish consolidated driver packages (`.cab`, `.exe`, or `.zip`).

- **Dell:** [Dell Command | Deploy Driver Packs](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)
- **HP:** [HP Client Driver Packs](https://ftp.hp.com/pub/caps-softpaq/cmit/HP_Driverpack_Matrix_x64.html)
- **Lenovo:** [Lenovo System Update Driver Packs](https://support.lenovo.com/us/en/solutions/ht037099)

### 2. Extract the driver pack

Most vendor packs are self-extracting `.exe` files. Extract them to a staging folder:

```
C:\Staging\Dell Latitude 7450\
├── Chipset\
├── Storage\
│   └── Intel\
│       └── 20.2.6.1025.3\
├── Network\
│   ├── Ethernet\
│   └── WLAN\
├── Graphics\
└── ... (other categories)
```

### 3. Add the Intel VMD driver (if missing)

Some vendor packs omit the Intel VMD driver. If your target has a 12th Gen+ Intel CPU, copy the VMD driver from an existing pack into the new one:

```
C:\Staging\Dell Latitude 7450\Storage\Intel\20.2.6.1025.3\
├── iaStorVD.inf
└── ...
```

### 4. Create the archive

```powershell
7z a -v3g "Dell Latitude 7450 13th Gen Intel.7z" "C:\Staging\Dell Latitude 7450\"
```

### 5. Copy to the network share

```powershell
Copy-Item "Dell Latitude 7450*.7z*" "\\SERVER\Shared\DriverPacks\"
```

### 6. Test

Deploy to the target model and check `C:\ProgramData\OEM\Logs\pre_*.log` for a line like:

```
[✓] Found driver folder: Dell Latitude 7450 13th Gen Intel
```

If the log shows `No driver folder found for model: Dell Latitude 7450`, the script could not match the archive name to the detected model. Check the model string that the script extracted (search the log for `Model:`), and rename the archive to match.

---

## Updating an Existing Driver Pack

Vendors release driver updates regularly. When you update a driver pack, the target machine's drivers will only be updated on the next deployment — the existing installation is not touched.

**Best practice:** Keep the model + generation in the filename but bump an internal version marker so you can tell versions apart:

```
Dell Latitude 7450 13th Gen Intel (2024-11).7z
Dell Latitude 7450 13th Gen Intel (2025-03).7z
```

The matching algorithm uses a `*<model>*<generation>*` pattern, so any filename containing both the model and the generation will match. The script picks the **longest matching filename** when multiple archives match. This means a filename with a date suffix will win over a filename without one, but it also means the specific date matters.

**Alternative — replace in place:** Overwrite the existing archive with the same filename. This is simpler but loses the ability to roll back.

**Copy to offline media** if applicable, then test a deployment.

---

## Payload Updaters and Companion Repos

The scripts `Apps.ps1`, `Drivers.ps1`, and `LGPO.ps1` automatically download the latest payloads from three companion GitHub repositories:

| Repository | Payload | Extracts to |
|---|---|---|
| [`52250179/Update-PBR-Extensibility-Apps`](https://github.com/52250179/Update-PBR-Extensibility-Apps) | OEM app archives | `C:\Temp\OEM\Apps` |
| [`52250179/Update-PBR-Extensibility-Drivers`](https://github.com/52250179/Update-PBR-Extensibility-Drivers) | Driver packs | `C:\Temp\OEM\Drivers` |
| [`52250179/Update-PBR-Extensibility-LGPO`](https://github.com/52250179/Update-PBR-Extensibility-LGPO) | LGPO tool + policies | `C:\Temp\OEM\LGPO` |

Each payload is a split `.7z` archive. The updater fetches a SHA-256 hash from a Gist and compares it to the local hash before deciding whether to download.

### Using your own repos

If you want to host your own payloads, edit the following variables at the top of each updater script:

```powershell
$GistUrl     = "https://gist.github.com/<your-user>/<your-gist-id>/raw"
$RepoOwner   = "<your-github-user>"
$RepoName    = "<your-repo-name>"
$FilePattern = '^Apps\.7z\.\d+$'
```

Then update the corresponding Gist with the new SHA-256 when you push a new payload version.

### Staging paths

The payload updaters extract to `C:\Temp\OEM\<Apps|Drivers|LGPO>`. The `pre.ps1` script expects these payloads at `C:\Recovery\OEM\<Apps|Drivers|LGPO>`. If you use the payload updaters as part of an offline media build, you need to copy from `C:\Temp\OEM\*` to `C:\Recovery\OEM\*` (or the corresponding network share) before running a deployment.

---

## Best Practices

### File format

- Use `.7z` for archives. It compresses well and the scripts are built around 7-Zip.
- Split archives over 3 GB to stay under FAT32's 4 GB limit.
- Test every archive with `7z t <archive>` before publishing.

### Naming

- Be consistent with vendor names. `Dell` not `DELL`. `HP` not `Hp`.
- For driver packs, always include the CPU generation when the drivers differ by generation (Intel 11th vs 12th vs 13th Gen).
- Never include characters that are invalid on FAT32 (`\ / : * ? " < > |`).

### Contents

- Never include trialware, adware, or third-party promotional software in an OEM app pack.
- Include only the vendor's own utilities and drivers. Third-party apps (7-Zip, RustDesk, etc.) belong in `$OEM$\$1\Recovery\OEM\Apps\`, not in the vendor pack.
- Keep the archive focused. A 20 GB driver pack that contains drivers for 50 models is slower to deploy than 20 small packs for the models you actually support.

### Versioning

- Keep at least two versions of each driver pack if you might need to roll back a bad deployment.
- Log every change to your OEM content in a spreadsheet or ticketing system. The scripts don't version content for you.
- When you replace a payload on the network share, document why. Future-you will thank present-you.

### Testing

- Always test a new or updated driver pack on real hardware before rolling it out to a production share.
- Test at least one BIOS and one UEFI deployment if your environment supports both.
- Verify the extracted folder structure with `C:\Recovery\OEM\Drivers\` on the target machine after OOBE.

### Security

- Scan all vendor content with antivirus before adding it to a shared location.
- Only download driver packs and app archives from the vendor's official support site.
- Never include OEM content from unofficial sources.
- Do not store credentials, license keys, or activation data in OEM content — those belong in `pre.ps1` or `Control\`.

---

*See [docs/SCRIPTS.md](SCRIPTS.md) for the scripts that consume this content, and [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md) for building the DEPLOY USB.*
