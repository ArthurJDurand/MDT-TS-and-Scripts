# OEM Content Guide

This document describes how OEM content — driver packs, application archives, activation scripts, layout files, and supporting tools — is organized on the network shares and on offline media, how the scripts consume it, and how to add new packs.

The deployment scripts never hardcode model-specific content. They detect the target hardware at deployment time and pull the matching pack from a known location. This document is the reference for what those locations should look like.

The OEM app archives themselves are built by the companion repository [`MDT-OEM-Extensibility`](https://github.com/ArthurJDurand/MDT-OEM-Extensibility). This document describes how the deployment share consumes them, not how they are assembled.

---

## Table of Contents

- [Overview](#overview)
- [Where OEM Content Lives](#where-oem-content-lives)
- [Network Share Layout](#network-share-layout)
- [Offline Media Layout](#offline-media-layout)
- [Directory Reference](#directory-reference)
  - [OEM Apps](#oem-apps)
  - [Driver Packs](#driver-packs)
  - [Updates](#updates)
  - [WindowsRE](#windowsre)
  - [Servicing](#servicing)
  - [ScanState](#scanstate)
  - [WinPE Storage Drivers](#winpe-storage-drivers)
- [Archive Naming Conventions](#archive-naming-conventions)
- [Driver Pack Structure](#driver-pack-structure)
- [App Pack Structure](#app-pack-structure)
- [Vendor Detection](#vendor-detection)
- [Adding a New OEM App Pack](#adding-a-new-oem-app-pack)
- [Adding a New Driver Pack](#adding-a-new-driver-pack)
- [Updating an Existing Driver Pack](#updating-an-existing-driver-pack)
- [Best Practices](#best-practices)

---

## Overview

The OEM content is what makes this project more than a stock MDT deployment. It provides:

- **Model-specific driver packs** — extracted and injected into the offline image during deployment
- **Manufacturer-specific application archives** — extracted into `C:\Recovery\OEM` on the target and installed during OOBE or by the Apps framework
- **Activation scripts** — HWID for Windows and Ohook for Office
- **Local Group Policy** — LGPO tool and policy backups
- **Windows Recovery Environment images** — per OS and architecture
- **Offline servicing components** — DirectX FOD package for driver store cleanup
- **ScanState** — USMT tool for push-button reset package creation
- **Windows updates** — cumulative updates and `.msu`/`.cab` packages for offline image injection
- **WinPE storage drivers** — Intel VMD drivers loaded at boot when internal storage is not detected

None of this content is stored in Git. It is delivered from a network share or from a `DEPLOY`-labeled USB flash drive for offline deployments.

---

## Where OEM Content Lives

OEM content is consumed from two locations, in this priority order:

| Priority | Location | Used When |
|---|---|---|
| 1 | **Network share** | The deployment has network connectivity |
| 2 | **DEPLOY USB flash drive** | The deployment is fully offline |

Every extraction script checks the network share first and falls back to the USB. Populate both, or just one.

### Network shares

| Share | Purpose |
|---|---|
| `\\SERVER\Shared\OEM\x64` | 64-bit OEM application archives |
| `\\SERVER\Shared\OEM\x86` | 32-bit OEM application archives |
| `\\SERVER\Shared\DriverPacks` | Model-specific driver `.7z` archives |
| `\\SERVER\Shared\Updates\Win10\x64` | Windows 10 x64 cumulative updates |
| `\\SERVER\Shared\Updates\Win10\x86` | Windows 10 x86 cumulative updates |
| `\\SERVER\Shared\Updates\Win11` | Windows 11 cumulative updates |
| `\\SERVER\Shared\WindowsRE\<OS>\<arch>` | WinRE images |
| `\\SERVER\Shared\Servicing` | Offline servicing components (DirectX FOD) |
| `\\SERVER\Shared\ScanState` | USMT ScanState tool |
| `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<version>` | Intel VMD drivers for the WinPE boot image |

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

The `Administrators` write access on `DriverPacks` is used by `3OEMDriversExport.cmd` when a technician exports drivers from a deployed machine.

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
│       └── ... (x86 app packs for vendors you support on 32-bit)
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
│   │   │   └── ... (cumulative and SSU packages)
│   │   └── x86\
│   │       └── ...
│   └── Win11\
│       ├── windows11.0-kb50xxxxx-x64.msu
│       └── ...
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
│       └── ...
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
├── Boot\                 (from the MDT media set)
├── Control\              (from the MDT media set)
├── Operating Systems\    (from the MDT media set, SWM-split)
├── Scripts\              (from the MDT media set)
├── Task Sequences\       (from the MDT media set)
├── $OEM$\                (from the MDT media set)
├── OEM\
│   ├── x64\
│   └── x86\
├── DriverPacks\
├── Updates\
│   ├── Win10\
│   └── Win11\
├── WindowsRE\
├── Servicing\
├── ScanState\
└── Drivers\
    └── WinPE\
```

The USB is FAT32, which has a **4 GB per-file limit**. Any archive larger than 4 GB must be split into `.7z.001`, `.7z.002`, ... parts. See [Handling FAT32's 4 GB limit](OFFLINE-MEDIA.md#handling-fat32s-4-gb-limit).

---

## Directory Reference

### OEM Apps

**Path:** `\\SERVER\Shared\OEM\x64` or `\\SERVER\Shared\OEM\x86` (or `DEPLOY:\OEM\x64`)
**Consumed by:** `ExtractOEMAppsx64.ps1`, `ExtractOEMAppsx86.ps1`
**Extracted to:** `C:\Recovery\OEM` on the target

**Purpose:** Per-vendor application installers, bundled as `.7z` archives. The correct archive is selected by matching the target machine's manufacturer string.

**Contents of each `.7z`:** Whatever you want extracted into `C:\Recovery\OEM`. By convention:

```
<vendor>.7z
├── Apps\
│   ├── <vendor>CommandUpdate.exe
│   ├── <vendor>SupportAssistant.exe
│   └── ...
├── Drivers\
│   └── ... (optional, if you bundle drivers with apps)
└── ... (any other content)
```

The exact structure is up to you — `ExtractOEMAppsx64.ps1` extracts the archive into `C:\Recovery\OEM` preserving its internal folder structure.

**One `.7z` per vendor.** The scripts do not combine archives.

**Building the archives:** The archives are produced by the companion repository [`MDT-OEM-Extensibility`](https://github.com/ArthurJDurand/MDT-OEM-Extensibility). That repository contains the per-vendor recipes, the download tooling, and the packer that produces the `.7z` files. It is the source of truth for what goes into each vendor's archive.

### Driver Packs

**Path:** `\\SERVER\Shared\DriverPacks` (or `DEPLOY:\DriverPacks`)
**Consumed by:** `ExtractOEMDrivers.ps1`
**Extracted to:** `C:\Recovery\OEM\Drivers` on the target

**Purpose:** One archive per supported model containing all drivers for that model. The correct archive is selected by matching the target machine's model and CPU generation against the archive filename.

**Naming convention:** The filename is the primary matching surface. See [Archive Naming Conventions](#archive-naming-conventions).

### Updates

**Path:** `\\SERVER\Shared\Updates\Win10\x64`, `\\SERVER\Shared\Updates\Win10\x86`, or `\\SERVER\Shared\Updates\Win11`
**Consumed by:** `ApplyUpdates10x64.ps1`, `ApplyUpdates10x86.ps1`, `ApplyUpdates11.ps1`
**Applied to:** The offline Windows image via DISM, before first boot

**Purpose:** Cumulative updates, servicing stack updates, .NET updates, and any other `.msu` or `.cab` packages you want baked into the image.

**Sources:**

- [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/)
- [WSUS Offline Update](http://www.wsusoffline.net/)
- An export from your WSUS server

**Important:** Only `.msu` and `.cab` files are processed. Other formats are ignored.

**Order of application:** DISM applies packages in alphabetical order. If order matters (e.g. SSU before cumulative update), prefix filenames with numbers:

```
01-ssu-2024-11-x64.msu
02-cumulative-2024-11-x64.msu
03-netfx-2024-11-x64.msu
```

### WindowsRE

**Path:** `\\SERVER\Shared\WindowsRE\<Win10|Win11>\<x64|x86>\winre.wim`
**Consumed by:** `WinRE.ps1`
**Copied to:** `C:\Recovery\WindowsRE\winre.wim` on the target's recovery partition

**Purpose:** A WinRE image per OS and architecture. `WinRE.ps1` first tries the WinRE already present inside the deployed OS (`C:\Windows\System32\Recovery\winre.wim`). The network-share copy is a fallback used when the OS image has no WinRE or when the deployed WinRE is corrupt.

**Where to get the WinRE image:**

- Extract from a clean Windows ISO: `install.wim` → `Windows\System32\Recovery\winre.wim`
- Or from `WinRE.wim` inside the `sources\` folder of a Windows ISO

**Optional VMD injection:** If `LoadWinPEDrivers.ps1` wrote a `VMD_Loaded.txt` marker during deployment, `WinRE.ps1` will inject the same Intel VMD driver into the WinRE image. This is needed on newer Intel platforms where WinRE must see internal storage. See the Known Limitations section in [docs/SCRIPTS.md](SCRIPTS.md#winreps1) for a caveat about marker persistence.

### Servicing

**Path:** `\\SERVER\Shared\Servicing`
**Consumed by:** `ScanWindowsImage64.ps1` (invoked from the post-deployment `3OEMDriversExport.cmd` workflow)
**Purpose:** Offline servicing components needed to restore the DirectX FOD after driver store cleanup.

**Structure:**

```
\\SERVER\Shared\Servicing\
└── Microsoft-OneCore-DirectX-Database-FOD-Package\
    ├── Microsoft-OneCore-DirectX-Database-FOD-Package~31bf3856ad364e35~amd64~~.cab
    └── ... (dependencies if any)
```

**Background:** Cleaning the driver store on Windows 11 removes the DirectX FOD package, which breaks some DirectX features. The offline servicing workflow restores the package from this folder.

### ScanState

**Path:** `\\SERVER\Shared\ScanState`
**Consumed by:** `4ScanState.cmd` (invoked post-deployment)
**Copied to:** `C:\Temp\ScanState` on the target
**Purpose:** The USMT `ScanState` tool, used to create a push-button reset provisioned package.

**Structure:**

```
\\SERVER\Shared\ScanState\
├── amd64\
│   ├── scanstate.exe
│   ├── migcore.dll
│   └── ... (all USMT amd64 components)
└── x86\
    ├── scanstate.exe
    └── ...
```

**Where to get USMT:** USMT is part of the Windows ADK. After installing the ADK, the tool is at `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool\<version>\`. Copy both the `amd64` and `x86` folders into `\\SERVER\Shared\ScanState`.

### WinPE Storage Drivers

**Path:** `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<version>`
**Consumed by:** `LoadWinPEDrivers.ps1`
**Purpose:** Intel VMD drivers loaded in WinPE when internal storage is not detected.

**Structure per version:**

```
20.2.6.1025.3\
├── iaStorVD.inf
├── iaStorVD.sys
├── iaStorVD.cat
├── RstMwService.exe
└── ...
```

**Version mapping:** `LoadWinPEDrivers.ps1` selects the version based on CPU generation:

| CPU Generation | Driver Version |
|---|---|
| 11th Gen | `19.5.8.1059.2` |
| 12th Gen and above | `20.2.6.1025.3` |

**Where to get the drivers:** Download the Intel Rapid Storage Technology driver package from Intel and extract the `VMD` subfolder.

---

## Archive Naming Conventions

The scripts select archives by filename pattern matching. The naming convention is not enforced by code — follow it so the matching works.

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

The match is case-insensitive and substring-based. A manufacturer string of `Hewlett-Packard Company` matches the `HP.7z` archive because `Hewlett-Packard` is a substring.

### Driver Pack Archives

**Pattern:** Free-form. The script generates candidate patterns from the detected model and CPU generation. See [Driver Pack Structure](#driver-pack-structure).

**Recommended conventions:**

- `<Vendor> <Model> <Gen>th Gen Intel.7z` — most specific, preferred
- `<Vendor> <Model>.7z` — model-only match, used as fallback
- `<Vendor> <Series> <Gen>th Gen Intel.7z` — for series-wide packs

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

`ExtractOEMDrivers.ps1` and `ExtractOEMApps*.ps1`:

1. Sort all parts by numeric suffix.
2. Copy all parts.
3. Validate with `7z t <first-part>`.
4. Extract with `7z x <first-part>` — 7-Zip reads the split volume from `.001` and continues automatically.

**Creating split archives:**

```powershell
# Split Dell.7z into 3 GB parts
7z a -v3g "Dell.7z" "C:\Staging\Dell\"
```

This produces `Dell.7z.001`, `Dell.7z.002`, and so on. The 3 GB part size leaves headroom for FAT32's 4 GB limit.

---

## Driver Pack Structure

The scripts apply the driver pack by running DISM with `/Add-Driver /Recurse` on the extracted folder. The extracted folder can contain any number of subdirectories with `.inf` files, and DISM recurses through all of them.

**Recommended structure inside each driver pack `.7z`:**

```
Dell Latitude 5430 12th Gen Intel.7z
├── Chipset\
├── Storage\
│   └── Intel\
│       └── 20.2.6.1025.3\
│           └── ... (VMD driver files)
├── Network\
│   ├── Ethernet\
│   └── WLAN\
├── Audio\
├── Graphics\
├── Bluetooth\
├── Camera\
├── CardReader\
└── ... (other categories)
```

**WLAN special case:** `ApplyOEMDrivers.ps1` looks for a folder named `WLAN` under `C:\Recovery\OEM\Drivers` and applies it **in addition** to the model-specific folder. Place your WLAN drivers either inside the model pack (anywhere in the tree) or in a shared `WLAN\` folder that gets extracted alongside the model pack.

**Intel VMD special case:** `ApplyOEMDrivers.ps1` looks for Intel VMD drivers under `C:\Recovery\OEM\Drivers\Storage\Intel\<version>`. Include the appropriate VMD folder in every driver pack for a 10th Gen+ Intel platform.

---

## App Pack Structure

`ExtractOEMAppsx64.ps1` extracts the vendor `.7z` into `C:\Recovery\OEM` without any filtering. Whatever is inside the archive gets placed on the target machine.

**Recommended structure:**

```
Dell.7z
├── Customizations.ps1             Vendor-specific pre-install script
├── csup.txt                       Vendor metadata consumed by SetupComplete
├── gpsFix.reg                     Registry tweaks
├── OEMinfo.reg                    OEM branding registry
├── unattend.xml                   OEM-attend overlay for PBR
├── OEM.7z                         Infrastructure extracted to C:\OEM
├── Customizations\
│   ├── Dell.7z                    Wallpapers and themes (default family)
│   └── G-series.7z                Additional assets for the G-series family
└── Apps\
    ├── CommandCenter\
    │   ├── v5\Alienware-Command-Center-5-x-Full-Installer.exe
    │   └── v6\Alienware-Command-Center-Application-Full-Installer.exe
    ├── CommandUpdate\
    │   ├── Dell-Command-Update-Windows-Universal-Application.exe
    │   ├── PreinstallKit\windowsdesktop-runtime-10.0.11-win-x64.exe
    │   └── UWP\DellCommandUpdate.appxbundle
    ├── FusionService\
    ├── MyAlienware\
    ├── Optimizer\
    ├── PowerManagerService\
    ├── PrecisionOptimizer\
    └── SupportAssist\
```

Anything under `Apps\` is available to `pre.ps1` (which scans `C:\Recovery\OEM\Apps\` for installers) and to the OEM Apps framework (which reads manifests under `Apps\Manifests\`).

**Office installers:** `pre.ps1` calls `Get-OfficeInstallerFolder`, which looks for a folder under `C:\Recovery\OEM\Apps\` starting with `Office`. Name your Office installer folder `Office2021`, `Office365`, or similar.

---

## Vendor Detection

`ExtractOEMAppsx64.ps1` detects the manufacturer using three WMI/CIM sources:

```powershell
(Get-CimInstance Win32_BaseBoard).Manufacturer
(Get-CimInstance Win32_ComputerSystem).Manufacturer
(Get-CimInstance Win32_ComputerSystemProduct).Vendor
```

Values matching these are excluded as invalid:

```
Default string
Not Applicable
Not Available
System Manufacturer
To be filled by O.E.M.
```

The remaining values are grouped, and the most frequent one is selected. If values disagree (e.g. baseboard says `ASUSTeK` but chassis says `ASUS`), the script picks whichever appears most often.

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

### 3. Copy to the network share

```powershell
Copy-Item "Framework.7z*" "\\SERVER\Shared\OEM\x64\"
```

### 4. Copy to offline media (optional)

Copy the archive to the DEPLOY USB at `OEM\x64\`.

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

**Note:** If you are adding a vendor to the OEM Apps framework as well, the recipe and manifest for that vendor live in the companion repository [`MDT-OEM-Extensibility`](https://github.com/ArthurJDurand/MDT-OEM-Extensibility). The deployment share consumes the resulting archives; it does not build them.

---

## Adding a New Driver Pack

Suppose you want to add support for a new model, `Dell Latitude 7450` with a 13th Gen Intel CPU.

### 1. Download the vendor driver pack

From the vendor's support site, download the enterprise driver pack for that model.

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

**Best practice:** Keep the model and generation in the filename but add an internal version marker so you can tell versions apart:

```
Dell Latitude 7450 13th Gen Intel (2024-11).7z
Dell Latitude 7450 13th Gen Intel (2025-03).7z
```

The matching algorithm uses a `*<model>*<generation>*` pattern, so any filename containing both the model and the generation will match. The script picks the **longest matching filename** when multiple archives match.

**Alternative — replace in place:** Overwrite the existing archive with the same filename. This is simpler but loses the ability to roll back.

Copy the updated archive to offline media if applicable, then test a deployment.

---

## Best Practices

### File format

- Use `.7z` for archives. It compresses well and the scripts are built around 7-Zip.
- Split archives over 3 GB to stay under FAT32's 4 GB limit.
- Test every archive with `7z t <archive>` before publishing.

### Naming

- Be consistent with vendor names. `Dell`, not `DELL`. `HP`, not `Hp`.
- For driver packs, always include the CPU generation when the drivers differ by generation (Intel 11th vs 12th vs 13th Gen).
- Never include characters invalid on FAT32 (`\ / : * ? " < > |`).

### Contents

- Never include trialware, adware, or third-party promotional software in an OEM app pack.
- Include only the vendor's own utilities and drivers. Third-party apps belong in the framework's manifest, not in the vendor pack.
- Keep each archive focused. A 20 GB driver pack containing drivers for 50 models is slower to deploy than 20 smaller packs for the models you actually support.

### Versioning

- Keep at least two versions of each driver pack if you might need to roll back a bad deployment.
- Log every change to your OEM content in a spreadsheet or ticketing system. The scripts do not version content for you.
- When you replace a payload on the network share, document why. Future-you will thank present-you.

### Testing

- Always test a new or updated driver pack on real hardware before rolling it out to a production share.
- Test at least one BIOS and one UEFI deployment if your environment supports both.
- Verify the extracted folder structure with `C:\Recovery\OEM\Drivers\` on the target machine after OOBE.

### Security

- Scan all vendor content with antivirus before adding it to a shared location.
- Only download driver packs and app archives from the vendor's official support site.
- Never include OEM content from unofficial sources.
- Do not store credentials, license keys, or activation data in OEM content. Those belong in `pre.ps1`, the framework's configuration, or `Control\`.

---

*See [docs/SCRIPTS.md](SCRIPTS.md) for the scripts that consume this content, [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md) for the framework that installs OEM apps, and [docs/OFFLINE-MEDIA.md](OFFLINE-MEDIA.md) for building the DEPLOY USB. The OEM archives themselves are built by [`MDT-OEM-Extensibility`](https://github.com/ArthurJDurand/MDT-OEM-Extensibility).*
