# Windows Installation Media

This document explains how to obtain or build the Windows installation image (`install.wim` or an ISO containing one) that you will import into your MDT deployment share.

This project does **not** ship Windows images. You must provide your own. There are two ways to do that:

- **Build your own with UUPDump** — recommended, free, produces an image that matches your scripts exactly
- **Use an existing image** — from Microsoft, VLSC, or your organization

The first path is documented in detail below. The second is a note at the end.

---

## Table of Contents

- [Why Build Your Own](#why-build-your-own)
- [Prerequisites](#prerequisites)
- [Overview of the Build Workflow](#overview-of-the-build-workflow)
- [Step 1 — Choose a Windows Version and Edition](#step-1--choose-a-windows-version-and-edition)
- [Step 2 — Build the ISO with UUPDump](#step-2--build-the-iso-with-uupdump)
- [Step 3 — Extract install.wim from the ISO](#step-3--extract-installwim-from-the-iso)
- [Step 4 — Import into MDT](#step-4--import-into-mdt)
- [Customizing the Image (Audit Mode)](#customizing-the-image-audit-mode)
- [Which Editions to Include](#which-editions-to-include)
- [Which Architectures](#which-architectures)
- [Refreshing the Image Over Time](#refreshing-the-image-over-time)
- [Deep Guide in the Companion Repository](#deep-guide-in-the-companion-repository)
- [Using an Existing Image Instead](#using-an-existing-image-instead)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Why Build Your Own

Building your own image with UUPDump has several advantages:

- **Always current.** You can build from the latest Windows feature update or cumulative update on demand.
- **Custom editions.** You pick exactly which editions appear in the ISO (Pro, Pro for Workstations, Enterprise, and so on). This project only needs Pro.
- **.NET 3.5 integration.** UUPDump can integrate .NET Framework 3.5 into the image during the build, so your task sequence does not need to enable it separately.
- **Ownership.** The image is yours. There is no dependency on a maintainer's cloud storage or a personal OneDrive that may disappear.
- **Consistency.** Every technician builds from the same recipe. There is no "which OneDrive link is the latest" problem.
- **No rate limits.** Microsoft's CDN and UUPDump are not subject to the download limits or quota issues of personal file hosting.

The one downside is that you have to run the build yourself. Expect 30–60 minutes for the first build, less on subsequent builds once the tools are cached.

---

## Prerequisites

### Software

| Tool | Purpose | Download |
|---|---|---|
| **Any modern browser** | Download the UUPDump package | Any |
| **7-Zip** | Extract the UUPDump package and the ISO | [7-zip.org](https://www.7-zip.org/) |
| **A Windows build host** | Run the UUPDump download script | Windows 10, Windows 11, or a VM |

You can also build on Linux or macOS using the shell script UUPDump provides, but the walkthrough below assumes Windows.

### Disk space

| Item | Approximate size |
|---|---|
| UUPDump package download | 100–600 MB |
| Downloaded component files | 3–6 GB |
| Extracted ISO | 5–8 GB |
| Temp space during build | 10–15 GB |

Allow **at least 30 GB** of free disk space on the build host.

### Time

| Phase | Time |
|---|---|
| Downloading the UUPDump package | 1 min |
| Downloading Windows components | 10–30 min (depends on connection) |
| Building the ISO | 10–25 min |
| Extracting `install.wim` from the ISO | 2–5 min |
| Importing into MDT | 5–15 min |

---

## Overview of the Build Workflow

```
1. Pick a Windows version and edition on uupdump.net
2. Download a small package
3. Extract the package
4. Run the package's download script
   → Downloads Windows components from Microsoft
   → Builds an ISO
5. Extract install.wim from the ISO
6. Import install.wim into MDT
7. (Optional) Customize the image in audit mode
8. (Optional) Capture the customized image and re-import
```

Steps 1–6 are covered in detail below. Steps 7–8 are covered under [Customizing the Image (Audit Mode)](#customizing-the-image-audit-mode) and expanded further in the companion repository.

---

## Step 1 — Choose a Windows Version and Edition

### Version

Open [uupdump.net](https://uupdump.net/) in a browser.

Choose:

- **Windows 11** for a current deployment target (recommended)
- **Windows 10** only if you have legacy hardware or an existing Win10 workflow

For Windows 11, select the **latest stable build**. For Windows 10, select **22H2** (build 19045). Avoid Insider builds unless you have a specific reason.

### Edition

UUPDump lets you select which editions to include in the ISO. For this project:

- **Pro** — required
- **Home** — optional; include it if you ever expect to deploy to Home-licensed machines
- **Pro for Workstations**, **Enterprise**, **Education** — optional; skip unless you have a licensing reason to include them

The fewer editions you include, the smaller the ISO and the shorter the build.

### Language

Choose **en-US** or the language that matches your target environment. If you need multiple languages, you will have to run UUPDump once per language.

### Architecture

- **amd64 (x64)** — required for Windows 11 and Windows 10 x64
- **x86** — only for Windows 10 x86, which is a legacy target. Windows 11 does not ship as x86.

If you deploy only 64-bit Windows, build only amd64.

---

## Step 2 — Build the ISO with UUPDump

### 2.1 — Generate the download package

On the UUPDump page for your chosen version:

1. Click **Download and convert to ISO**
2. In the pop-up, configure the conversion options:
   - **Integrate .NET Framework 3.5** — **check this box**
   - Leave other options at their defaults unless you have a specific reason to change them
3. Click **Create download package**

Your browser downloads a `.zip` file named something like `22621.xxxx_amd64_en-us_professional_<uuid>.zip`.

### 2.2 — Extract the package

Extract the `.zip` file to a folder on your build host. Use 7-Zip or the Windows built-in extractor.

The extracted folder contains:

- A shell script (`uup_download_windows.cmd` on Windows)
- An `aria2c.exe` or `curl.exe` downloader
- A `.json` file describing the download
- Other supporting files

### 2.3 — Run the download script

Open the extracted folder and run `uup_download_windows.cmd` (double-click or run as administrator from a command prompt).

The script:

1. Downloads the Windows component packages from Microsoft's servers
2. Verifies each package against a SHA-1 hash
3. Builds an ISO using `dism`, `oscdimg`, and other built-in Windows tools
4. Places the resulting ISO in the same folder

Expect 10–30 minutes depending on connection speed. The script prints progress to the console.

When it completes, you should see a file named something like `22621.xxxx.240xxx-xxxx_x64fre_en-us_professional_<uuid>.ISO`.

### 2.4 — Verify the ISO

The script reports a SHA-256 hash at the end. Copy that hash for your records.

You can also confirm the ISO file size is in the expected range (5–8 GB for a single-edition ISO).

---

## Step 3 — Extract install.wim from the ISO

MDT imports the `.wim` file from the ISO. You have two ways to get there.

### Option A — Import the ISO directly into MDT

MDT can import directly from a mounted ISO:

1. Mount the ISO (double-click it on Windows 10/11)
2. In Deployment Workbench, right-click **Operating Systems** → **Import Operating System**
3. Choose **Full set of source files**
4. Browse to the mounted ISO's root (e.g. `E:\`)
5. Complete the wizard

This is the fastest path and is recommended for first-time users. MDT handles the `install.wim` extraction internally.

### Option B — Extract install.wim manually

If you want to keep the ISO around but also have the WIM available as a standalone file:

1. Mount or extract the ISO with 7-Zip
2. Navigate to `sources\`
3. Find `install.wim` (or `install.esd` on some editions)
4. Copy `install.wim` to a stable location on your build host

If the ISO ships `install.esd` instead of `install.wim`:

```powershell
# Convert install.esd to install.wim (standard compression)
dism /Export-Image /SourceImageFile:C:\path\to\install.esd /SourceIndex:1 /DestinationImageFile:C:\path\to\install.wim /Compress:max /CheckIntegrity
```

Repeat with different `/SourceIndex` values to export additional editions.

### Verify the WIM

```powershell
dism /Get-WimInfo /WimFile:C:\path\to\install.wim
```

This lists the editions and their index numbers. Note the index for the edition you plan to deploy (usually Pro).

---

## Step 4 — Import into MDT

Once you have either the mounted ISO or an extracted `install.wim`:

1. Open **Deployment Workbench**
2. Expand your deployment share
3. Right-click **Operating Systems** → **Import Operating System**
4. Choose:
   - **Full set of source files** — if importing from a mounted ISO
   - **Custom image file** — if importing a standalone `install.wim`
5. Browse to the source
6. **Destination name:** give the OS a name that matches what the task sequences expect. Default names:
   - `Windows 10 Pro (64-bit)`
   - `Windows 10 Pro (32-bit)`
   - `Windows 11 Pro (64-bit)`
7. If prompted for the WIM image index, choose the index that corresponds to the Pro edition
8. Complete the wizard

MDT copies the image into `C:\DeploymentShare\Operating Systems\<name>\`.

### 4.1 — Point the task sequences at the new OS

Each task sequence has an `Install Operating System` step that references a specific OS. If you named your imported OS exactly as above, the task sequences will pick it up automatically. If you used a different name:

1. Open the task sequence in Deployment Workbench
2. Find the **Install Operating System** step
3. Set the **Operating system to install** dropdown to your imported OS

Repeat for each task sequence (`WIN11PROX64`, `WIN10PROX64`, `WIN10PROX86`).

### 4.2 — Verify

```powershell
Get-ChildItem "C:\DeploymentShare\Operating Systems"
```

You should see a folder per imported OS containing `install.wim` and supporting files.

---

## Customizing the Image (Audit Mode)

If you want to bake additional customizations into the image before deployment — extra drivers, pre-installed applications, registry tweaks, or a customized default user profile — do this in **audit mode** on a reference machine.

The workflow:

1. Boot the reference machine from a USB made from your ISO (or from MDT using a task sequence that stops in audit mode)
2. Use the shipped `autounattend.xml` to bypass OOBE and enter audit mode automatically
3. Apply customizations
4. Run `sysprep /generalize /oobe /shutdown`
5. Capture the sealed image with `dism /Capture-Image`
6. Import the captured image into MDT

**This workflow is documented in detail in the companion repository [MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder).** That repository is the authoritative source for:

- The `autounattend.xml` files used to enter audit mode
- Hyper-V virtual machine setup for customization
- Application installation patterns and their silent switches
- Registry tweaks that should be baked into the image
- Sysprep pitfalls and how to avoid them
- Image capture best practices
- Troubleshooting the capture and re-import steps

The companion repository is optional. If you are happy with a stock Windows image plus the OEM customizations that this project applies at deployment time, you do not need to build a custom image.

---

## Which Editions to Include

| Edition | Include? | Notes |
|---|---|---|
| **Pro** | Yes, required | The task sequences in this project target Pro |
| **Home** | Optional | Include only if you deploy to OEM Home-licensed machines |
| **Home Single Language** | Optional | Only relevant in regions where this is the OEM default |
| **Pro for Workstations** | Optional | Only if you license this edition |
| **Enterprise** | Optional | Only if you have a volume license |
| **Education** | Optional | Only if you deploy to education environments |

The fewer editions you include, the smaller the ISO and the shorter the build. If you only deploy to Pro machines, build a Pro-only ISO.

---

## Which Architectures

| Architecture | Notes |
|---|---|
| **amd64 (x64)** | Required for Windows 11 and Windows 10 x64. If you only deploy 64-bit Windows, this is the only ISO you need. |
| **x86** | Only for Windows 10 x86. This project's `WIN10PROX86` task sequence targets it, but the OEM Apps framework does not ship in the x86 tree. See the README's Known Limitations. |

Windows 11 does not ship as x86.

---

## Refreshing the Image Over Time

Windows ships cumulative updates roughly once a month. Rebuilding the ISO every month is not necessary. A reasonable refresh cadence is:

- **Every 6 months** — rebuild the ISO from UUPDump to pick up the accumulated updates
- **At major feature updates** — rebuild from UUPDump to get the new feature branch
- **When you need a specific fix** — rebuild on demand

Alternatively, you can leave the base image alone and let the `ApplyUpdates` task sequence step inject updates into the offline image during deployment. This project's `ApplyUpdates*.ps1` scripts support that workflow — see [docs/SCRIPTS.md](SCRIPTS.md#applyupdates10x64ps1).

The trade-off:

- **Rebuild the image** — larger image, but a faster deployment (fewer updates to apply)
- **Keep the base image** — smaller image, but more updates to apply during deployment

For most environments, a 6-month refresh cadence with the `ApplyUpdates` step catching the rest works well.

---

## Deep Guide in the Companion Repository

The full workflow for building and customizing Windows installation media — including audit mode, Hyper-V setup, application installation, sysprep, and capture — is documented in the companion repository:

**[github.com/ArthurJDurand/MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder)**

That repository is separate because image building has a different audience and lifecycle than deployment-share management. It changes when Microsoft releases new builds; this repository changes when the scripts and OEM content change.

If the companion repository is not yet published, this document is sufficient to produce a stock Windows image and import it. The companion repository adds the audit-mode customization workflow on top.

---

## Using an Existing Image Instead

If you already have a Windows ISO or `install.wim` from Microsoft, VLSC, your organization, or a hardware vendor, you can import it directly. Skip Steps 1–3 above and go straight to [Step 4 — Import into MDT](#step-4--import-into-mdt).

Requirements for the imported image:

- **Windows 10 or Windows 11 Pro** — the task sequences target Pro editions
- **x64 for Win10 x64 and Win11 x64** — the framework and most OEM packs are x64-only
- **x86 for Win10 x86** — legacy target; framework does not ship for x86
- **A `install.wim` file** — if the source is `install.esd`, convert it first (see Step 3)

The same deployment-share and task-sequence steps apply regardless of where the image came from.

---

## Troubleshooting

### UUPDump fails to download some components

**Cause:** Microsoft's CDN rate-limits or briefly rejects a download.

**Fix:**

1. Re-run `uup_download_windows.cmd`. It caches successful downloads and retries failed ones.
2. If specific files keep failing, try a different network (off VPN or a different ISP route).
3. Try the aria2 downloader option if UUPDump offers one for your build.

### UUPDump builds the ISO but the file is corrupt

**Cause:** One or more component files are incomplete.

**Fix:**

1. Delete the output ISO and the `UUPs` folder
2. Re-run `uup_download_windows.cmd`
3. Verify the SHA-256 hash reported at the end matches the expected hash on the UUPDump page for your build

### `install.wim` is missing from the ISO

**Cause:** Some editions ship `install.esd` instead of `install.wim`.

**Fix:** Convert the ESD to WIM as described in [Step 3](#step-3--extract-installwim-from-the-iso).

### MDT import fails with "The specified image file is invalid"

**Cause:** The `install.wim` is corrupt, or you pointed MDT at the wrong file.

**Fix:**

1. Verify the WIM with `dism /Get-WimInfo /WimFile:<path>`. If this fails, the WIM is corrupt.
2. Re-extract the WIM from the ISO, or re-download the ISO.
3. Verify the path is exactly `<ISO root>\sources\install.wim`.

### Task sequence cannot find the imported OS

**Cause:** The task sequence's `Install Operating System` step references an OS name that does not match the imported one.

**Fix:**

1. Open the task sequence
2. Find the `Install Operating System` step
3. Set the **Operating system to install** dropdown to your imported OS

### Sysprep fails during audit mode

**Cause:** Sysprep does not like certain applications, Store app updates, or user profile state.

**Fix:** See the companion repository [MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) for the sysprep troubleshooting guide.

---

## Best Practices

### Keep one ISO per major Windows branch

Do not try to maintain a single image that covers Windows 10 and Windows 11. Build one ISO per branch:

- Windows 10 22H2 x64
- Windows 10 22H2 x86 (if you support it)
- Windows 11 24H2 or the current stable x64

Import each into MDT as a separate OS entry and point the matching task sequence at it.

### Document your build recipe

Keep a text file alongside your ISOs listing:

- The UUPDump build ID (from the URL)
- The date you built it
- Which editions were included
- Any UUPDump options you changed
- The SHA-256 of the resulting ISO

When you need to rebuild six months later, the recipe saves guesswork.

### Verify before you deploy

Before using a newly built ISO in production:

1. Import it into a **test** deployment share
2. Run a full deployment on a physical test machine
3. Complete OOBE and verify all framework phases converge
4. Only then roll it into your production share

### Do not customize the base image unless you have to

The framework and the task sequence apply most customizations at deployment time. Adding the same customizations to the base image duplicates work and risks drift between image and deployment-share behavior.

Customize the base image only for things that cannot be applied at deployment time:

- Language packs and language settings that must be present at first boot
- Optional Windows features that take too long to enable at deployment
- Applications that must be installed before first logon

### Store ISOs and WIMs outside the repository

Do not commit ISOs, WIMs, or ESDs to Git. They are multi-GB binaries and belong in local storage, a network share, or your own file hosting. The `.gitignore` in this repository excludes them by default.

---

*See [docs/SETUP.md](SETUP.md) for the deployment share setup that consumes the imported image, and [MDT-Windows-Image-Builder](https://github.com/ArthurJDurand/MDT-Windows-Image-Builder) for the deep audit-mode and capture workflow.*
