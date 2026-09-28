<!--
  Thanks for submitting a pull request! Before you continue, please:

  1. Read CONTRIBUTING.md — especially the Script Standards section.
  2. Ensure your branch is based on the latest `main`.
  3. Make sure all applicable checkboxes below are ticked.

  For large or architectural changes, please open an issue or a Discussion
  first so we can agree on the approach before you invest significant time.
-->

## Summary

<!--
  One or two sentences describing WHAT this PR changes and WHY.
  Link the related issue if one exists.
-->

Closes #

## Type of Change

<!--
  Tick all that apply. This informs the reviewer and the auto-generated
  release notes (see .github/release.yml).
-->

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] 🚀 New feature (non-breaking change that adds functionality)
- [ ] ⚠️ Breaking change (fix or feature that changes existing behaviour; may require users to update their deployment share, task sequence, or configuration)
- [ ] 🔧 Driver or hardware support (new model, new CPU generation, new VMD/RAID driver)
- [ ] 📦 OEM pack addition (driver pack or app archive for a new vendor/model)
- [ ] 🧩 OEM Apps framework change (module, manifest, hook, or framework internal)
- [ ] 📝 Documentation only (no script changes)
- [ ] 🧹 Refactor or maintenance (no functional change)
- [ ] 🔒 Security fix

## Affected Area

<!--
  Which parts of the project does this PR touch? Tick all that apply.
  This helps reviewers focus and helps users know what to re-test.
-->

- [ ] `DeploymentShare\Scripts\Custom\` — task sequence scripts (WinPE-safe)
- [ ] `DeploymentShare\<arch>\$OEM$\$$\Setup\` — `SetupComplete.cmd` orchestrator
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\` — OOBE scripts (`pre.ps1`, `Customizations.ps1`, activation, layout)
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\Framework\` — OEM Apps framework modules
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\OEM\` — OEM modules
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\Manifests\` — OEM manifest files
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Recovery\OEM\Apps\pbr.ps1` — framework entry point
- [ ] `DeploymentShare\<arch>\$OEM$\$1\Scripts\` — post-deployment scripts
- [ ] `DeploymentShare\Control\` — MDT configuration (`Bootstrap.ini`, `CustomSettings.ini`, `Settings.xml`, `Medias.xml`)
- [ ] `DeploymentShare\Task Sequences\` — task sequence definitions or `Unattend.xml`
- [ ] `MDT\Content\` — offline media set
- [ ] `Prerequisites\` — server/desktop setup configs
- [ ] `docs\` — documentation
- [ ] Repository infrastructure (`.github/`, `LICENSE`, `CHANGELOG.md`, `.gitignore`)

## Changes Made

<!--
  A bullet list of the specific changes. Keep it scannable.
  Reference specific files or functions where relevant.
-->

-
-
-

## Testing

<!--
  Describe exactly how you tested this. "It works" is not enough.
  The more detail, the easier it is to review with confidence.
-->

**Hardware tested on:**

<!--
  Example: Dell Latitude 5430, Intel Core i5-1245U (12th Gen), BIOS 1.22.1
-->

**Firmware mode:**

<!-- Tick all that apply -->

- [ ] UEFI (with Secure Boot)
- [ ] UEFI (Secure Boot disabled)
- [ ] Legacy BIOS / MBR
- [ ] Not applicable

**Operating system deployed:**

- [ ] Windows 11 Pro x64 (`WIN11PROX64`)
- [ ] Windows 10 Pro x64 (`WIN10PROX64`)
- [ ] Windows 10 Pro x86 (`WIN10PROX86`)
- [ ] Not applicable

**Testing steps performed:**

<!--
  Example:
  1. PXE booted the target machine.
  2. Ran task sequence WIN11PROX64 end-to-end.
  3. Verified VMD driver loaded in WinPE (checked X:\MININT\SMSOSD\OSDLOGS\BDD.log).
  4. Completed OOBE and confirmed Office activation deferred correctly.
  5. Checked C:\ProgramData\OEM\Logs\pre_*.log for errors.
-->

1.
2.
3.

**Result:**

<!--
  Example: Full deployment completed successfully. All scripts exited 0.
  VMD driver version 20.2.6.1025.3 loaded as expected.
-->

## Known Issues / Limitations

<!--
  Anything that doesn't work, needs follow-up, or is known to be a
  partial implementation. Be honest — reviewers would rather know now.
-->

- None.

## Screenshots or Logs

<!--
  If this PR fixes a visible bug or adds a new UI/behaviour, include
  before/after evidence. Drag and drop images directly into this box.
  For logs, attach as a file or upload to a Gist — do not paste long
  logs inline.
-->

## Checklist

<!--
  Every box must be ticked before a reviewer will look at the PR.
  If a box doesn't apply, explain why in the Notes section below.
-->

### Script Standards (see CONTRIBUTING.md)

- [ ] Scripts in `Scripts\Custom\` are **WinPE-safe** (registry and file system only; no WMI/CIM/Storage module unless a FeaturePack was added)
- [ ] Scripts in `$OEM$` and the framework follow the same quality standards where applicable (defensive lookups, retry logic, exit-code preservation)
- [ ] All volume/disk lookups use `Select-Object -First 1` or equivalent defensive handling
- [ ] DISM and robocopy operations include retry logic
- [ ] Task sequence scripts are silent — no spurious `Write-Host` or `Write-Output`
- [ ] Exit codes are preserved and visible to the caller — no silent `try/catch` swallowing
- [ ] No hardcoded drive letters — paths are discovered via volume labels
- [ ] Scripts are PowerShell 5.1 compatible (no PS7-only syntax)
- [ ] Every script has an updated `.SYNOPSIS` / `.DESCRIPTION` / `.NOTES` header block
- [ ] **Registry writes use `reg.exe` exclusively** — no PowerShell Registry Provider writes
- [ ] Framework changes respect the architectural invariants in `docs/APPS-FRAMEWORK.md`

### Repository Hygiene

- [ ] `CHANGELOG.md` updated under `[Unreleased]` in the appropriate section (`Added`, `Changed`, `Fixed`, `Removed`, `Security`)
- [ ] No large binaries committed outside the intentional binary locations documented in `.gitignore`
- [ ] No credentials, API keys, tokens, or secrets committed
- [ ] No unrelated files, formatting changes, or drive-by refactors included
- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat(scope): …`, `fix(scope): …`, etc.)
- [ ] Branch is based on the latest `main` and rebased if necessary
- [ ] PR title matches the Conventional Commits format

### Documentation

- [ ] User-facing documentation updated (`README.md` or `docs/*`) if behaviour changed
- [ ] If a new script was added, it is listed in the Scripts Reference (README or `docs/SCRIPTS.md`)
- [ ] If a new OEM pack was added, `docs/OEM.md` reflects the new directory structure
- [ ] If a new OEM module was added, `docs/APPS-FRAMEWORK.md` lists the OEM and its hooks
- [ ] If a new configuration file was added, it is listed in the Configuration Files to Edit table

### Testing

- [ ] Tested on real hardware (or explained below why a VM was sufficient)
- [ ] Reproduced the original bug (for bug fixes) or validated the new feature works end-to-end
- [ ] No regressions observed in adjacent scripts or phases

## Notes for Reviewers

<!--
  Anything else the reviewer should know. Call out tricky parts, areas
  you're unsure about, or questions you'd like feedback on.
-->

- None.

---

<!--
  By submitting this pull request, you agree that your contribution is
  licensed under the MIT License that governs this project. See
  CONTRIBUTING.md → "License of Contributions" for details.
-->
