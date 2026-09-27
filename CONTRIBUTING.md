```markdown
# Contributing to MDT Task Sequences & Custom Scripts

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
| **Documentation** | Clarifying a setup step, fixing a typo, adding a troubleshooting entry |
| **Testing** | Confirming a script works on your hardware and reporting the result |
| **Translation** | Translations of the README or docs (open a Discussion first) |
| **Ideas** | Feature requests, workflow suggestions, or architectural feedback |

If you're unsure whether an idea is in scope, **open a [Discussion](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/discussions) first** before investing time in a PR.

---

## Before You Start

### Check existing issues and PRs

Someone may already be working on the same thing. Search [open issues](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/issues) and [open PRs](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/pulls) before starting.

### Open an issue first for large changes

For anything beyond a typo or obvious bug fix — especially new scripts, task sequence changes, or new OEM packs — **open an issue to discuss the approach first**. This avoids wasted effort if the change doesn't fit the project's direction.

### Small, focused PRs are preferred

One logical change per PR. A PR that fixes a bug *and* adds a feature *and* reformats a script is hard to review and hard to revert if something goes wrong.

---

## Development Setup

To test your changes properly, you need a working MDT environment.

### Minimum requirements

- Windows Server (with DHCP + WDS) **or** Windows desktop (with AOMEI PXE Boot)
- Windows ADK for Windows 11 + Windows PE Addon
- Windows SDK for Windows 11
- Microsoft Deployment Toolkit (MDT) `6.3.8456.1000`
- PowerShell 7
- 7-Zip installed at `C:\Program Files\7-Zip\7z.exe` (required by `pre.ps1` and the payload updater scripts)
- A target machine for testing (physical hardware strongly preferred over a VM for driver-related changes)

### Recommended workflow

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/MDT-TS-and-Scripts.git
   ```
3. Set up a **test deployment share** separate from your production share
4. Merge your fork's contents with your test share
5. Test your changes end-to-end (PXE boot a client, complete a full deployment, complete OOBE)
6. Commit and push to your fork
7. Open a PR against the `main` branch

### Testing requirements by change type

| Change Type | Testing Required |
|---|---|
| Documentation only | None (but proofread carefully) |
| Script bug fix | Reproduce the bug, apply the fix, verify it's resolved, confirm no regression |
| New task sequence script | Full deployment on at least one physical machine |
| Driver pack addition | Deploy to the target model and confirm drivers install |
| Task sequence change | Full deployment on both BIOS and UEFI (if applicable) |
| VMD / storage driver change | Deploy to the target CPU generation |
| `pre.ps1` change | Full deployment through OOBE on at least one physical machine, verify the transcript log at `C:\ProgramData\OEM\Logs\` |
| `SetupComplete.cmd` change | Full deployment through OOBE, verify all three child scripts run and log |
| Payload updater change (`Apps.ps1`, `Drivers.ps1`, `LGPO.ps1`) | Dry run against the live companion repos and against a deliberately wrong Gist hash to confirm the failure path |

**State what hardware you tested on in the PR description.** "Tested on Dell Latitude 5430, BIOS mode, Win11 Pro x64" is far more useful than "tested and works."

---

## Script Standards

Scripts live in two distinct execution contexts. The standards differ.

| Location | Execution Context | WMI/CIM Allowed? |
|---|---|---|
| `Scripts\Custom\` | WinPE (Preinstall, Install, Postinstall phases) | **No** unless `winpe-wmi` is added to FeaturePacks |
| `$OEM$\$1\...` | Full OS (OOBE via `SetupComplete.cmd`) | **Yes** — WMI and CIM are available and safe |

The rules below apply to **both** unless stated otherwise.

### 1. WinPE-safe (applies to `Scripts\Custom\` only)

Scripts in `Scripts\Custom\` run in WinPE during the **Preinstall**, **Install**, and **Postinstall** phases. WinPE is a stripped-down environment — many cmdlets and modules are unavailable.

**Rules:**

- Use the **registry and file system only** for hardware detection
- **Do not use `Get-CimInstance`, `Get-WmiObject`, or `Get-PhysicalDisk`** unless `winpe-wmi` and the Storage module are explicitly added to FeaturePacks
- Do not assume the `Microsoft.PowerShell.Storage` module is available in WinPE
- Do not assume `Get-Volume` returns a single result — see rule 2

**Instead of WMI:**

```powershell
# BAD — WMI is not reliable in WinPE
$model = (Get-CimInstance Win32_ComputerSystem).Model

# GOOD — registry is always available
$model = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -Name SystemProductName).SystemProductName
```

Scripts in `$OEM$` are **exempt** from this rule because they run in the full OS.

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

Scripts in `Scripts\Custom\` run inside a task sequence — user-facing output disrupts the deployment UI.

- **No `Write-Host`** unless the message is diagnostic and critical
- **No `Write-Output`** unless the output is meant to be captured
- Redirect verbose tool output to `$null` or a log file
- Preserve `$LASTEXITCODE` — do not use `| Out-Null` on native commands if you need the exit code

Scripts in `$OEM$` may use `Write-Host` freely for progress reporting, because they run in OOBE with no task sequence UI to disturb.

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

Never hardcode `C:`, `D:`, etc. Always discover via volume label.

```powershell
# BAD
$WindowsImage = "C:\"

# GOOD
$WindowsDrive = (Get-Volume -FileSystemLabel Windows | Select-Object -First 1).DriveLetter
$WindowsImage = "${WindowsDrive}:\"
```

### 8. Path fallbacks

Scripts that read from network shares should fall back to a DEPLOY-labeled USB drive, matching the pattern used in `ApplyUpdates*.ps1` and `ExtractOEM*.ps1`.

### 9. PowerShell 5.1 compatibility

Scripts must run under the WinPE version of PowerShell, which is **5.1**. Do not use syntax or cmdlets exclusive to PowerShell 7 (e.g., ternary operator `? :`, `??`, `-Parallel`).

### 10. No `exit` in task sequence scripts

MDT scripts should **return** rather than `exit`, so the task sequence can capture failures. Use `exit` only when the script is intentionally standalone. Scripts invoked from `SetupComplete.cmd` are standalone and may use `exit`.

### 11. Idempotence for payload updaters

The `Apps.ps1`, `Drivers.ps1`, and `LGPO.ps1` scripts must be idempotent. Before downloading anything, they compare the current SHA-256 in the local `.sha256` file against the remote hash and exit early if they match. Any new updater must follow this pattern.

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

- `apply-drivers`, `apply-updates`, `winre`, `disk`, `oem`, `lgpo`, `setup`, `pre`, `apps`, `drivers`, `docs`, `readme`

### Examples

```
feat(apply-drivers): add support for 14th Gen Intel VMD
fix(winre): persist VMD marker on target OS drive
docs(setup): clarify WDS boot image import steps
refactor(disk): use Select-Object -First 1 for volume lookups
```

### Breaking changes

If a change breaks existing deployments, add `!` after the type/scope and include a `BREAKING CHANGE:` footer:

```
feat(apply-updates)!: require OSDVersion TS variable

BREAKING CHANGE: ApplyUpdates11.ps1 now reads the OSDVersion
task sequence variable to pick the update source folder. Update
your task sequences to set OSDVersion before upgrading.
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

---

## Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main` using the naming convention above
3. **Make your changes** following the script standards
4. **Update `CHANGELOG.md`** — add your change under `[Unreleased]` in the appropriate section (`Added`, `Changed`, `Fixed`, `Removed`, `Security`)
5. **Test end-to-end** on real hardware where applicable
6. **Push** to your fork
7. **Open a PR** against `main` with:
   - A clear title (matching the Conventional Commits format)
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
- Added 14th Gen to generation map
- Updated LoadWinPEDrivers.ps1 to use the new version

## Testing
- Tested on HP EliteBook 840 G11, UEFI, Win11 Pro x64
- Full deployment completed successfully through OOBE
- VMD driver version 20.2.6.1025.3 loaded in WinPE

## Related Issue
Closes #42

## Checklist
- [x] Follows script standards (WinPE-safe where required)
- [x] CHANGELOG.md updated under [Unreleased]
- [x] Tested on real hardware
- [x] No hardcoded drive letters
- [x] Retry logic for DISM/robocopy
```

---

## What Reviewers Look For

When reviewing your PR, I check:

| Item | Why |
|---|---|
| **WinPE safety** | No WMI/CIM/Storage modules in `Scripts\Custom\` unless FeaturePacks are updated |
| **Defensive lookups** | `Select-Object -First 1` on volume/disk commands |
| **Retry logic** | DISM and robocopy operations retry on failure |
| **Silent operation** | No spurious `Write-Host` or `Write-Output` in task sequence scripts |
| **Exit code preservation** | Failures are visible to the caller |
| **Header documentation** | SYNOPSIS/DESCRIPTION/NOTES block present |
| **CHANGELOG entry** | Added under `[Unreleased]` |
| **No drive letter hardcoding** | Paths discovered via volume labels |
| **PowerShell 5.1 compatible** | No PS7-only syntax |
| **Idempotence** | Payload updaters exit early when nothing changed |
| **Tested on hardware** | PR description states the hardware used |
| **Small, focused scope** | One logical change per PR |

---

## Areas Where Help Is Needed

Some specific things I'd love help with:

### 1. OEM license edition detection

A script that reads the OEM digital license from the BIOS (`OA3xOriginalProductKeyDescription`), determines the licensed edition (e.g., Home Single Language, Home, Pro), and sets the deployed OS edition to match during deployment.

Currently, `pre.ps1` only activates if the OEM license is Professional — non-Pro licenses are not applied, and LGPO policies are applied regardless of edition.

**Where to hook in:** `$OEM$\$1\Recovery\OEM\pre.ps1` and the task sequence State Restore phase.

### 2. Additional OEM packs

Driver packs and app archives for:

- Panasonic Toughbook
- Fujitsu LifeBook
- Samsung / LG laptops
- Toshiba Dynabook (existing pack needs updating)
- Clevo / Tongfang / XMG / Schenker
- System76 / Framework (Linux-first, but Windows works)

### 3. Newer Intel / AMD storage drivers

- Intel VMD for 14th Gen and beyond (Meteor Lake, Arrow Lake)
- AMD RAID / NVMe drivers for Ryzen 7000/8000/9000 series

### 4. Script improvements

- Refactoring `WinRE.ps1` to be less monolithic
- Adding a `-DryRun` mode to destructive scripts (`CleanFixedDrives.ps1`, `FormatDataDrive.ps1`)
- Refactoring `pre.ps1` into smaller modules — the current file is over 1000 lines
- Adding Pester tests for pure functions (CPU generation detection, model normalization, OEM key matching)
- Adding structured logging to a file alongside the existing transcript

### 5. Payload updater improvements

- Adding a fallback path to a secondary mirror when both the primary and fallback URLs fail
- Adding a `-Force` switch to bypass the local hash check and re-download
- Adding SHA-256 verification of each downloaded part against a manifest (currently only the assembled archive is validated with `7z t`)
- Replacing the external Gist dependency with a signed manifest file stored in the main repo

### 6. Documentation

- Expanding `docs/TROUBLESHOOTING.md` with real-world error scenarios
- Adding a "known working hardware" table to the README
- Adding screenshots to the setup guide
- Documenting the `SetupComplete.cmd` → `pre.ps1` → `Customizations.ps1` → `pbr.ps1` chain in `docs/OEM.md`

If any of these interest you, **open a Discussion first** so we can scope it together.

---

## Reporting Bugs

Found a bug? [Open an issue](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/issues/new) with:

- **Description** — what you expected vs. what happened
- **Steps to reproduce** — exact task sequence step, phase, or command
- **Hardware** — make, model, CPU, BIOS/UEFI mode
- **OS being deployed** — Win10 x64 / Win10 x86 / Win11 x64
- **Relevant log file** — MDT logs are in `X:\MININT\SMSOSD\OSDLOGS\` (WinPE) or `C:\MININT\SMSOSD\OSDLOGS\` (full OS) during deployment; OEM logs are in `C:\ProgramData\OEM\Logs\` after OOBE
- **Screenshots** if applicable

**Please don't paste full logs inline** — attach them as files or link to a Gist.

---

## License of Contributions

By submitting a pull request to this project, you agree that your contribution is licensed under the same [MIT License](LICENSE) that governs the project.

You confirm that:

- You have the right to submit the contribution
- The contribution is your original work, or you have obtained permission to submit it under the MIT License
- Any third-party code included in your contribution is compatible with the MIT License and clearly attributed

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

In short: be respectful, be patient, assume good faith, and focus on the technical problem. Harassment, personal attacks, and dismissive behavior are not tolerated. Violations can be reported to the maintainer via a [private GitHub security advisory](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/security/advisories/new).

---

## Questions?

- **General questions or ideas:** [GitHub Discussions](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/discussions)
- **Bug reports:** [GitHub Issues](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/issues)
- **Security vulnerabilities:** [Private security advisory](https://github.com/ArthurJDurand/MDT-TS-and-Scripts/security/advisories/new)
- **Direct contact:** See the [author's GitHub profile](https://github.com/ArthurJDurand)

---

## Thank You

Whether you submit a driver pack, fix a typo, or just report a bug on a machine you have access to — **your contribution matters**. This project is built on community knowledge, and every improvement helps someone deploy Windows a little faster.

Thank you for being part of it.

---

<div align="center">

**Happy deploying!** 🚀

</div>
```
