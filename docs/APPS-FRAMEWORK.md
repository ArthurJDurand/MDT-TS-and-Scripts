# Apps Framework

This document describes the OEM Apps deployment framework that ships with this project. The framework lives under `DeploymentShare\x64\$OEM$\$1\Recovery\OEM\Apps\` (and the parallel `x86` tree) and is invoked by `pbr.ps1` during deployment.

**The framework is a subsystem of this project.** It is deeply integrated into the deployment chain — it runs at OOBE and at first logon, installs OEM-specific applications, generates Start and taskbar layouts, and reports convergence state. It is not a standalone library, and its own internal design documentation is maintained separately from this repository. This file describes what ships in this repo, how it works, and how to extend it.

---

## Table of Contents

- [Overview](#overview)
- [Directory Layout](#directory-layout)
- [Two-Phase Deployment Model](#two-phase-deployment-model)
- [Framework Modules](#framework-modules)
- [OEM Modules](#oem-modules)
- [Manifests](#manifests)
- [Extension Points](#extension-points)
- [Architectural Invariants](#architectural-invariants)
- [Deployment Chain Integration](#deployment-chain-integration)
- [Logging and State](#logging-and-state)
- [Known Limitations](#known-limitations)
- [Canonical Framework Documentation](#canonical-framework-documentation)

---

## Overview

The framework provides a two-phase deployment engine for OOBE-era Windows machines. It runs at two points during a deployment:

- **SYSTEM phase** — during OOBE, before any user logs in, running as `SYSTEM` (SID `S-1-5-18`)
- **USER phase** — at first logon, running as the first interactive user, triggered by a scheduled task

The framework detects the OEM manufacturer, loads that OEM's module and manifest, iterates the manifest's apps, and installs each one using either a local installer or winget. When all apps have been processed, it generates Start and taskbar layouts (unless AutoApply owns layout) and writes a convergence marker.

Three parties participate in every deployment:

| Party | Supplies |
|---|---|
| **Framework** | OEM detection, profile dispatch, hook invocation, manifest parsing, app iteration, winget engine (USER only), local installer engine, layout generation, stage machine, logging, registry helpers, scheduled-task lifecycle |
| **OEM module** | A `Get-OEMProfile` function returning a profile object, plus optional hook functions for family detection, eligibility, custom installers, and phase-specific work |
| **Manifest** | Apps, installers, eligible families, pinning intent, and any OEM-specific fields consumed by module hooks |

The framework reads only the manifest fields it knows about. Everything else is available to module hooks and ignored by the framework.

---

## Directory Layout

Everything documented here ships in the main repository. Nothing else is required.

```
DeploymentShare\x64\$OEM$\$1\Recovery\OEM\Apps\
├── pbr.ps1                       Entry point (SYSTEM and USER phases)
├── Framework\                    Ten framework modules
│   ├── State.psm1
│   ├── Logging.psm1
│   ├── Registry.psm1
│   ├── AppDetection.psm1
│   ├── WinGet.psm1
│   ├── LocalInstall.psm1
│   ├── Layout.psm1
│   ├── ScheduledTask.psm1
│   ├── Health.psm1
│   └── Engine.psm1
├── OEM\                          Eleven OEM modules
│   ├── OEM.ASUS.psm1
│   ├── OEM.Acer.psm1
│   ├── OEM.Dell.psm1
│   ├── OEM.Dynabook.psm1
│   ├── OEM.Gigabyte.psm1
│   ├── OEM.HP.psm1
│   ├── OEM.Huawei.psm1
│   ├── OEM.Lenovo.psm1
│   ├── OEM.MSI.psm1
│   ├── OEM.Proline.psm1
│   └── OEM.Surface.psm1
└── Manifests\                    Eleven manifest files
    ├── ASUS.json
    ├── Acer.json
    ├── Dell.json
    ├── Dynabook.json
    ├── Gigabyte.json
    ├── HP.json
    ├── Huawei.json
    ├── Lenovo.json
    ├── MSI.json
    ├── Proline.json
    └── Surface.json
```

The `x86` tree contains a parallel structure, adapted for 32-bit deployments. Framework module contents are architecturally identical; manifests and OEM modules may differ where a given OEM does not ship 32-bit app packs.

---

## Two-Phase Deployment Model

The framework runs in exactly one of two phases per invocation, determined by the security context in which `pbr.ps1` executes.

### SYSTEM Phase

Runs at OOBE, invoked by `SetupComplete.cmd`. Runs as `SYSTEM`.

What happens, in order:

1. `Invoke-SystemPhase` (in `Engine.psm1`) is entered.
2. `OnSystemPreInstall` hook fires if the OEM module declares it.
3. `Get-SystemFamilyFromProfile` determines the system family (via the `GetSystemFamily` hook, or the framework default).
4. For each app in the manifest:
   - Eligibility is checked: phase, product family, prerequisites, conflicts, service gates.
   - Presence is tested. If already present, the app is recorded and skipped.
   - The install method is invoked. SYSTEM phase uses **local installers only** — winget is never invoked.
5. `OnSystemPostInstallPreLayout` hook fires.
6. Layout is generated unless `C:\Recovery\AutoApply` is present.
7. `OnSystemPostLayout` hook fires.
8. The resume task is registered (via `RegisterResumeTask` hook, or the framework default).
9. `TestSystemCompletionRequirements` hook fires. If it returns false, SYSTEM does not converge.
10. If no failures occurred and the completion check passed, `Set-DeploymentStage` writes `SYSTEM_DONE`.

An app declared `InstallPhase: UserOnly`, or one that requires interactivity, is skipped and recorded in `DeferredApps`.

### USER Phase

Runs at first logon, invoked by the resume task registered during SYSTEM phase. Runs as the first interactive user.

What happens, in order:

1. `Invoke-UserPhase` is entered.
2. Time synchronization and TLS 1.2 configuration are applied.
3. `OnUserPreInstall` hook fires.
4. `Initialize-WinGetSession` reads the baseline bypass state and enables bypass if the baseline is known-disabled.
5. Framework-level global prerequisites are attempted (see [Global Prerequisites](#global-prerequisites)).
6. `Get-SystemFamilyFromProfile` is called again.
7. For each app in the manifest, the same eligibility checks run, with two differences:
   - Winget is available. If the app declares a `WingetAppId`, winget runs — **regardless of presence**. This is how the framework obtains telemetry for winget-sourced apps.
   - Interactive installers are permitted.
8. Layout is generated unless AutoApply is present.
9. `OnUserPostInstall` hook fires.
10. `Invoke-PostDeploymentHealthCheck` verifies that every expected app is present. Health check failures block convergence.
11. If nothing failed and health passed, `Set-DeploymentStage` writes `USER_DONE`.
12. The resume task is unregistered.
13. The winget session is restored.

**Phase ordering is permissive.** USER phase may run before SYSTEM phase has completed. This is intentional, not a defect. A machine whose SYSTEM phase failed can still reach `USER_DONE`, and `SYSTEM_DONE` may be backfilled later or never.

---

## Framework Modules

All ten modules live under `Framework\`. They are imported alphabetically by `pbr.ps1` at startup.

### State.psm1

Owns per-run context and hardware detection.

**Exports:** `Get-SystemManufacturer`, `Get-SystemModel`, `Get-IntelGenerationFromName`, `Get-AmdGenerationFromName`, `New-DeploymentContext`, `New-DeploymentMutex`, `Release-DeploymentMutex`, `Get-DeploymentStage`, `Set-DeploymentStage`, `Get-CurrentExecutionPhase`, `Add-UniqueValue`, `Invoke-ProfileHook`, `Invoke-ProfileBoolHook`, `ConvertTo-ScalarBool`, `Get-DeploymentClassification`.

**Depends on:** `Registry.psm1`.

### Logging.psm1

Owns all log output.

**Exports:** `Initialize-FrameworkLogging`, `Write-DeploymentLog`, `Write-AppDetailLog`, `Write-AppOutcome`, `Complete-FrameworkLogging`, `Compress-FrameworkLogs`.

**Depends on:** nothing.

### Registry.psm1

Owns all registry access.

**Exports:** `Set-RegistryValueSilent`, `Set-OfflineHiveValueSet`, `Get-DefaultUserSpotlightKeys`, `Invoke-DefaultUserHiveHardening`, `Invoke-LiveUserSpotlightSuppression`.

**Depends on:** `Logging.psm1`.

**Write discipline:** all registry **writes** use `reg.exe` exclusively. Reads via the PowerShell provider are permitted. This is a framework-wide invariant — see [Architectural Invariants](#architectural-invariants). The rationale is that the PowerShell provider's handle retention blocks offline-hive unload, and a policy that requires per-site reasoning is a policy the next write site will violate.

### AppDetection.psm1

Owns application presence detection, with five independent caches.

**Exports:** `Clear-ApplicationCaches`, `Get-AppxProvisionedPackageSafe`, `Get-CachedProvisionedPackages`, `Get-AppxPackageSafe`, `Get-UninstallCache`, `Get-PackageCache`, `Get-AppxCache`, `Get-UserAppxCache`, `Test-ApplicationInstalled`, `Get-ApplicationVersion`.

**Depends on:** `Logging.psm1`.

**Cache contract:** each cache returns `@()` on a genuine empty result and `$null` on a query failure. The initialisation flag is set only on a non-null result, so a transient failure does not disable detection for the process lifetime.

### WinGet.psm1

Owns winget invocation.

**Exports:** `Get-WingetExePath`, `Get-WingetBypassSetting`, `Invoke-WingetAdminCommand`, `Invoke-WingetProcess`, `Initialize-WinGetSession`, `Restore-WinGetSession`, `Invoke-WingetInstallSafe`, `Test-WingetPackageInstalled`, `Write-PinnedCertDiagnostic`, `Write-WingetProcessOutput`.

**Depends on:** `Logging.psm1`, `AppDetection.psm1`.

**Contract:** USER phase only. Machine scope first, source-independent. Uses `winget install`, never `winget upgrade`. Transient exit codes retry the same scope up to three times. Terminal classification is state-derived, with one override: the pinned-certificate mismatch code `0x8A15005E` forces classification as `Failed` regardless of detected state.

### LocalInstall.psm1

Owns local installer execution (MSI, MSP, EXE, CMD, AppX, MSIX, and bundles).

**Exports:** `Get-InstallationPackage`, `Wait-ForMSI`, `Invoke-LocalInstaller`, `Invoke-ProcessWithTimeout`, `Invoke-AppxProvision`, `Test-NewerProvisionedWarrantsSkip`, `Write-LocalInstallOutcome`.

**Depends on:** `Logging.psm1`, `AppDetection.psm1`.

Handles sibling, package-local, and global dependency resolution for AppX-family packages.

### Layout.psm1

Owns Start and taskbar layout generation.

**Exports:** `Write-Utf8NoBomFile`, `Write-ContentIfDifferent`, `New-Win11StartLayoutJson`, `New-Win11TaskbarLayoutXml`, `Merge-Win10Layout`, `Test-AutoApplyLayoutPresent`, `Resolve-AumidForPin`, `Get-EligiblePins`, `Invoke-LayoutGeneration`.

**Depends on:** `Logging.psm1`, `AppDetection.psm1`, `Registry.psm1`, `State.psm1`.

Files are the source of truth. Idempotency is content-based — layout is only rewritten when its content would change. AutoApply ownership is authoritative and suppresses framework layout in both phases, including under `-Force`.

### ScheduledTask.psm1

Owns the resume task that triggers USER phase at first logon.

**Exports:** `Register-ResumeTask`, `Test-ResumeTask`, `Unregister-ResumeTask`.

**Depends on:** `Logging.psm1`.

The task is registered via `conhost.exe --headless` wrapping `powershell.exe`. The trigger is `AtLogOn`. The principal is `Administrators` (`S-1-5-32-544`) at `Highest` run level. The settings permit starting on battery and do not stop on AC removal.

`Register-ResumeTask` checks for a valid existing task first and returns early if one is present. This is deliberate — see [Architectural Invariants](#architectural-invariants) and the failure model discussion in [Known Limitations](#known-limitations).

### Health.psm1

Owns the post-USER-phase health check.

**Exports:** `Invoke-PostDeploymentHealthCheck`.

**Depends on:** `Engine.psm1` (for `Test-AppPresence` and eligibility helpers), `AppDetection.psm1`, `State.psm1`, `Logging.psm1`.

The health check rebuilds the expected app set from `Context.Manifest.apps` using the same eligibility logic the install loop uses, then verifies each expected app is present. Detection is retried up to three times to accommodate AppX registration latency. An app recorded in `SkippedApps` or `DeferredApps` and not also in a success bucket is excluded from the expected set — this is the custom-installer decline contract.

**Circularity note:** `Engine.psm1` calls `Health.psm1`, and `Health.psm1` uses helpers from `Engine.psm1`. This is safe because both modules are imported before `Start-OEMDeployment` runs and PowerShell resolves function calls at invocation, not at load.

### Engine.psm1

Owns orchestration — the top-level entry points for both phases.

**Exports:** `Start-OEMDeployment`, `Get-SystemFamilyFromProfile`, `Test-AppPresence`, `Test-ProductFamilyMatch`, `Test-PrereqsMet`, `Test-ConflictsPresent`, `Test-AppPhaseEligibility`, `Test-AppEligibilityForPhase`, `Test-ServiceGatedReady`, `Install-WingetPackage`, `Invoke-GlobalPrerequisites`, `Invoke-SystemPhase`, `Invoke-UserPhase`, `Invoke-AppInstall`, `Complete-AppInstall`, `Invoke-SupplementalWingetIfDeclared`, `Wait-ForNamedService`, `Get-FrameworkOSInfo`, `Write-CleanSummary`, `Write-AppOutcomeFromContext`.

**Depends on:** all modules above.

**Preflight:** `Start-OEMDeployment` runs structural checks before any phase work. It throws on a missing or empty profile field, a manifest filename mismatch, a missing `apps` key, a missing `AppName`, a duplicate `AppName`, an invalid `InstallPhase`, `SystemOnly` combined with `RequiresInteractive`, `SystemOnly` with no system-capable install method, a malformed `Pinning` block, a non-integer or negative `PinPriority`, a `CustomInstaller` not registered in the profile, a `CustomInstaller` without `InstallerArgs`, and an app with no install method at all.

### Dependency Graph

Load-time shape, low to high:

```
State   Logging
   \     /
    \   /
  Registry   AppDetection   ScheduledTask
       \       |             /
        \      |            /
         \     |           /
          WinGet   LocalInstall
               \     /
                \   /
               Layout
                  \
                   \
                  Engine
                 /      \
                /        \
             Health   (OEM module hooks)
```

---

## OEM Modules

Each OEM module is a `.psm1` file named `OEM.<Brand>.psm1` under `OEM\`. Only `Get-OEMProfile` is required. A module with only `Get-OEMProfile` and no hooks is legal and functional.

### Profile Object

The profile returned by `Get-OEMProfile` carries the OEM's identity and configuration. Six fields are required:

| Field | Purpose |
|---|---|
| `Name` | OEM token. Must match the module filename. |
| `ManifestFile` | Manifest filename, e.g. `Dell.json`. |
| `MarkerRegistryPath` | Registry key for stage markers, e.g. `HKLM:\SOFTWARE\OEM\Dell`. Must be distinct per OEM. |
| `ResumeTaskName` | Scheduled task name, e.g. `Dell_PBR_Resume`. |
| `LogDirectory` | Log output directory. All OEMs use `C:\ProgramData\OEM\Logs`. |
| `EventSourceName` | Windows Event Log source, e.g. `DellPBR`. |

Optional fields with defaults:

| Field | Default |
|---|---|
| `StageName` | `'DeploymentStage'` |
| `ServiceName` | `''` |
| `WinGetTimeoutSeconds` | `600` |
| `LocalTimeoutSeconds` | `600` |
| `ServiceWaitSeconds` | `180` |
| `DependenciesPath` | `C:\Recovery\OEM\Apps\Dependencies` |

### Hook Catalogue

Return-value hooks default to the value shown. Missing hooks are not errors.

| Hook | Default | Called |
|---|---|---|
| `GetSystemFamily` | `'Unknown'` | Once per phase, before app iteration. |
| `TestStaticEligibility` | `$true` | Per app, per phase. |
| `TestDynamicEligibility` | `$true` | Per app, per phase, after static. |
| `TestAppPresence` | framework default | Per app, per phase, multiple times. May return `$null` to decline and hand the app back to the framework chain. |
| `ResolvePinAumid` | framework default | Per pinned app during layout. |
| `WaitForService` | framework `Wait-ForNamedService` | First service-gated app per phase. |
| `TestSystemCompletionRequirements` | `$true` | End of SYSTEM phase. |
| `TestAdditionalHealth` | `$true` | End of USER phase, after package checks. |
| `GetAdditionalTaskbarPins` | `@()` | During layout generation. |
| `RegisterResumeTask` | framework default | End of SYSTEM phase. |

Side-effect hooks are no-ops when absent.

| Hook | Called |
|---|---|
| `OnSystemPreInstall` | Start of SYSTEM phase, before apps. |
| `OnSystemPostInstallPreLayout` | After apps, before layout. |
| `OnSystemPostLayout` | After layout, before task arming. |
| `OnUserPreInstall` | Start of USER phase, before winget. |
| `OnUserPostInstall` | End of USER phase, before health check. |

Side-effect hooks receive `$Context` with `FailedApps`, `SkippedApps`, `Profile`, `IsSystem`, `IsUser`, and other per-run state.

### Custom Installers

A module can register custom installers via a `CustomInstallers` hashtable in the profile, mapping names to scriptblocks with this signature:

```powershell
param($App, $Context, $WingetResult)
```

Return contract:

- `$true` — success.
- `$false` — failure. The framework adds the app to `FailedApps`.
- `$false` after the app has been recorded in `SkippedApps` or `DeferredApps` — the framework honours the decline. The app is not promoted to `FailedApps`.

### Rules for OEM Modules

OEM modules must not:

- Access the registry for **writes** directly. Use `Set-RegistryValueSilent` or `Set-OfflineHiveValueSet`. Reads via the provider are permitted.
- Manage the scheduled task directly unless overriding `RegisterResumeTask`.
- Write stage markers directly. Use `Set-DeploymentStage`.
- Log outside `LogDirectory`. Use `Write-DeploymentLog`.

---

## Manifests

Each manifest is a JSON file in `Manifests\`, named `<Brand>.json`, whose name must match the OEM module's `ManifestFile` field exactly. The top-level shape is:

```json
{
  "name": "<Brand>",
  "apps": [ /* app objects */ ]
}
```

`name` is reserved — the framework does not consume it today.

### Identity Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `AppName` | string | yes | Logical identity. Used in logs, summaries, bucket keys, and dependency references. Must be unique within `apps[]`. |
| `AlternateAppNames` | string[] | no | Variants the generic detector tries when neither `AppxPackageName` nor `AppName` matches. |
| `AppxPackageName` | string | no | AppX package identity. Optional — not every app is AppX. |
| `WingetAppId` | string | no | If present, USER phase attempts winget. Also used as the preferred installed-state identity for USER-phase presence. |
| `WingetSource` | string | no | `'winget'` or `'msstore'`. Inferred from ID shape if empty (`^9[A-Za-z0-9]{11,}$` → msstore). Explicit source is authoritative. |

### Local Installer Fields

| Field | Type | Notes |
|---|---|---|
| `InstallerPath` | string | File or folder containing the installer. |
| `InstallerFilter` | string | Glob filter for selection within a folder. Applies only to the generic local installer. |
| `InstallerCandidates` | string[] | Ordered list of candidate paths. Takes precedence over `InstallerPath`. |
| `InstallerArgs` | string | Arguments passed to the installer. Required when `CustomInstaller` is declared (empty string is legal). Ignored on AppX-family packages. |
| `CustomInstaller` | string | Name of a custom installer registered in the profile's `CustomInstallers` map. |

### Supplemental Winget Install Fields

| Field | Type | Notes |
|---|---|---|
| `SupplementalWingetAppID` | string | Second winget package attempted after the main app. |
| `SupplementalWingetSource` | string | `'winget'` or `'msstore'`. |
| `SupplementalAppxPackageName` | string | Detection identity. One of this or `SupplementalAppName` is required. |
| `SupplementalAppName` | string | Friendly name for logs. |

### Eligibility Fields

| Field | Type | Notes |
|---|---|---|
| `ProductFamilies` | string[] | Families the app applies to. Empty or absent matches all families. |
| `PrerequisiteApps` | string[] | App names that must be present first. |
| `ConflictingApps` | string[] | If any listed app is present, this app is skipped or failed per `Required`. |
| `ServiceGated` | bool | Framework waits for `Profile.ServiceName` before attempting. |

A `ServiceGated` app whose service is not ready is added to `FailedApps` and blocks convergence, regardless of `Required`.

### Phase and Interaction Fields

| Field | Type | Notes |
|---|---|---|
| `InstallPhase` | string | `'Any'`, `'SystemOnly'`, or `'UserOnly'`. Default `'Any'`. |
| `RequiresInteractive` | bool | Skipped in SYSTEM. Visible window in USER. Cannot combine with `SystemOnly`. |
| `Required` | bool | If true, conflict or failure blocks convergence. |

### Pinning Fields

`Pinning` is either `null` or an object:

```json
{ "Type": "AUMID", "Id": "<PFN>!<AppId>", "Taskbar": true, "PinPriority": 30 }
```

| Field | Type | Notes |
|---|---|---|
| `Type` | string | `'AUMID'` or `'Desktop'`. Required if `Pinning` is set. |
| `Id` | string | AUMID or link path. Required. |
| `Taskbar` | bool | Add to taskbar, subject to the 3-pin cap. |
| `Start` | bool | Add to Start, subject to the 12-pin cap. |
| `PinPriority` | int | Sort rank among Start and taskbar pins; lower sorts first. Unset sorts last. Never affects install order. |

The order of `apps[]` is the **installation order**. Do not reorder for pin order — use `PinPriority`. The taskbar cap is 3 pins, and one slot may be occupied by a framework profile pin. The Start cap is 12 pins.

### Module-Consumed Fields

Any field not listed above is available to module hooks and ignored by the framework. Examples in use:

- `MobileOnly` (ASUS, Dynabook, Lenovo)
- `RequireOptimizerSupport` (Dell)
- `SkipIfDellOptimizerSupported` (Dell)

Adding new module-consumed fields requires no framework change.

---

## Extension Points

Three extension dimensions, in increasing scope:

**Module-level field extension.** An OEM module can add any field to any manifest app object. The framework does not read it; the module's hooks do. No framework change is required.

**Framework-level field extension.** Adding a new field that the framework consumes requires the field to be optional with a documented default. Adding a required field would break every existing manifest.

**Hook extension.** An OEM module can implement any hook in the contract. Hooks that return values are permissive when absent (missing = pass or true). Hooks that perform side effects are no-ops when absent.

---

## Architectural Invariants

These must always hold. A change that violates one is a design change, not a bug fix.

1. **Convergence markers are terminal.** `USER_DONE` never transitions to a different state except by an explicit `-Force` re-run. A factory or push-button reset re-images the machine and the marker is gone; the invariant applies within a single Windows installation.
2. **AutoApply owns layout absolutely.** Its presence suppresses framework layout generation even under `-Force`. The framework does not detect or reconcile partial AutoApply states — either AutoApply owns layout completely or the framework does.
3. **Local installers are install-if-absent.** They do not upgrade and do not self-repair. The sole exception is the `0x8A15005E` pinned-certificate mismatch recovery path, where the state check cannot be trusted and a single idempotent reinstall of a present app is permitted.
4. **Winget runs in USER phase only.** SYSTEM phase never invokes winget.
5. **`WingetAppId` implies winget runs.** In USER phase, an app with a winget ID is attempted via winget regardless of presence. Winget's execution is how the framework obtains telemetry for winget-sourced apps.
6. **Registry markers are written only on verified success.** "Verified" means the marker is read back after the write and compared against the intended value. A `reg.exe` return code of `0` does not by itself prove the value landed.
7. **Registry writes use `reg.exe` exclusively.** No PowerShell Registry Provider writes, anywhere in the framework. The offline-hive path is where the provider's handle retention was first observed blocking hive unload, but the discipline applies uniformly. Reads via the provider are permitted.
8. **OEM module hooks are optional.** A missing hook is not an error; it means the module has no opinion on that concern.
9. **The framework consumes only the manifest fields it knows about.** Additional fields are available to module hooks and ignored by the framework.

### Force Semantics

`-Force` bypasses the stage-based early exits. It causes the phase to re-run even if its completion marker is already set. It does **not** change what the phase does:

- Local installers remain install-if-absent. A present app is not reinstalled.
- Winget still runs for apps that declare a `WingetAppId`, regardless of presence.
- Layout injection still skips when AutoApply owns layout. `-Force` does not override AutoApply's ownership.

`-Force` is a maintenance tool. It re-evaluates state and re-records markers. It does not reinstall, does not repair, and does not fight the user's existing configuration.

---

## Deployment Chain Integration

The framework is one link in a longer chain. It assumes the chain runs in the stated order. It does not enforce or verify it.

```
Windows Setup → SetupComplete.cmd
  ├─ pre.ps1                     Local provisioning of prerequisites
  ├─ Customizations.ps1          OEM branding, offline hive hardening
  └─ pbr.ps1                     This framework (SYSTEM phase)

First logon → scheduled task → pbr.ps1   (USER phase)

Operator sequence (image preparation):
  firstrun.ps1 → restart → secondrun.ps1 → restart
  → ScanState capture → push-button reset
```

### Framework-side contracts on the chain

- `SetupComplete.cmd` invokes `pbr.ps1` in SYSTEM context. If it fails or is skipped, USER phase still converges (permissive ordering).
- `pre.ps1` provisions AnyDesk, 7-Zip, WinRAR, and the Store media extensions from local media. The framework's `GlobalPrerequisites` list in `Engine.psm1` matches that list; the framework's winget calls for the same IDs are update and verification, not primary installation.
- `Customizations.ps1` writes to the Default User hive. Overlap with the framework's `OnSystemPreInstall` hardening is idempotent.
- `secondrun.ps1` is authoritative for the marker decisions the framework reads during eligibility evaluation.
- ScanState `OEMCustomizations.xml` **captures** durable machine facts and **excludes** convergence and install-success markers, plus the framework log tree.
- `C:\Recovery\AutoApply` presence is written by the ScanState step and signals that layout is externally owned.

### Global Prerequisites

Attempted in every USER phase, after `Initialize-WinGetSession`:

| ID | Source | Friendly name |
|---|---|---|
| `AnyDesk.AnyDesk` | winget | AnyDesk |
| `7zip.7zip` | winget | 7-Zip |
| `RARLab.WinRAR` | winget | WinRAR |
| `9MVZQVXJBQ9V` | msstore | AV1 Video Extension |
| `9PMMSR1CGPWG` | msstore | HEIF Image Extension |
| `9N4WGH0Z6VHQ` | msstore | HEVC Video Extensions from Device Manufacturer |
| `9N95Q1ZZPMH4` | msstore | MPEG-2 Video Extension |
| `9NCTDW2W1BH8` | msstore | Raw Image Extension |
| `9N4D0MSMP0PT` | msstore | VP9 Video Extensions |
| `9N5TDP8VCMHS` | msstore | Web Media Extensions |
| `9PG2DK419DRG` | msstore | WebP Image Extension |

Failures route to `SkippedApps` and do not block convergence.

---

## Logging and State

### Stage Markers

Registry location: under `Profile.MarkerRegistryPath`, value name `Profile.StageName` (default `'DeploymentStage'`).

| Value | Meaning |
|---|---|
| `NONE` or absent | No phase has converged. |
| `SYSTEM_DONE` | SYSTEM converged; USER still expected. |
| `USER_DONE` | USER converged. Terminal for normal invocations. |

The single value records the current converged stage, not a complete history. A machine at `USER_DONE` does not by itself prove that SYSTEM converged.

### In-Memory State

Per-run context, not persisted: `InstalledApps`, `UpdatedApps`, `AlreadyCurrent`, `SkippedApps`, `DeferredApps`, `FailedApps`, `RebootRequired`, `ServiceReady`, `WingetSession`, `AppOutcomes`, `SystemFamily`, `MarkerPath`, `StageName`.

### Log Files

Written under `Profile.LogDirectory` (`C:\ProgramData\OEM\Logs`):

- `PBR_Deployment.log` — shared structured log
- `Master_<Phase>_<PID>_<timestamp>.log` — PowerShell transcript
- `<AppName>.log` — per-app log, only for apps the framework worked on

Per-app outcome lines follow this format:

```
OUTCOME: <AppName> — <Class> (<parts>)
```

`Class` is one of `Installed`, `Updated`, `Already current`, `Failed`. `Parts` is a comma-separated list of version, method, reboot flag, exit code, and (for failures) reason.

All logs are written UTF-8 without BOM.

---

## Known Limitations

- **The framework does not self-heal.** Once converged, it does not re-verify or reinstall. Drift correction is deliberate, via `-Force` or a monthly maintenance script.
- **The framework does not fight the user.** If a user removes an app after convergence, the framework does not restore it on the next run.
- **Failures are explicit and blocking.** A failed app is added to `FailedApps` and blocks phase convergence. There is no persistent failure state across runs — the next `-Force` retries.
- **Phase history is not preserved.** The single marker records the last converged phase, not both. `SYSTEM_DONE` may be missing on a machine at `USER_DONE`.
- **Marker downgrade on SYSTEM `-Force` re-run.** Running `pbr.ps1 -Force` in SYSTEM context on a machine at `USER_DONE` currently overwrites the marker with `SYSTEM_DONE`. This is a recorded open decision.
- **Partial AutoApply states are not detected.** Either AutoApply owns layout completely, or the framework does. There is no middle ground.
- **Layout files are the only working pin-delivery mechanism** on Windows 10 version 1903 and later, and on all Windows 11 builds. The `Shell.Application` `taskbarpin` and `startpin` COM verbs were removed by Microsoft in 1903. This is why the framework ships a layout subsystem rather than relying on COM.
- **Registry writes must go through the framework helpers.** Direct writes will violate invariant 7 and risk the offline-hive unload problem.

---

## Canonical Framework Documentation

The framework has its own design and reference documentation, maintained separately from this repository. Those documents are the authoritative source for framework internals and are not shipped here. They cover:

- Framework architecture and module internals
- Full manifest schema reference
- OEM module authoring contract
- Design philosophy and invariants
- Deployment chain mechanics
- Validation state and deferred items
- Operator runbook

If you are extending the framework or writing a new OEM module, treat this document as a user-facing overview and consult the canonical docs before making design changes. This file describes what ships in the repository; the canonical docs describe why it is shaped the way it is.

If the canonical docs are ever open-sourced, this section should be updated with links.
