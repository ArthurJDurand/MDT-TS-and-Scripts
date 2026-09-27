# Troubleshooting Guide

This document covers common errors, their likely causes, and how to resolve them across every phase of a deployment.

If you cannot find your issue here, see [Getting Help](#getting-help) at the bottom.

---

## Table of Contents

- [Log Locations](#log-locations)
- [How to Read an MDT Log](#how-to-read-an-mdt-log)
- [WinPE and Boot Issues](#winpe-and-boot-issues)
- [Task Sequence Phase Failures](#task-sequence-phase-failures)
- [Script-Specific Issues](#script-specific-issues)
- [OOBE and SetupComplete Issues](#oobe-and-setupcomplete-issues)
- [Framework Issues](#framework-issues)
- [Hardware-Specific Issues](#hardware-specific-issues)
- [Post-Deployment Issues](#post-deployment-issues)
- [Useful Diagnostic Commands](#useful-diagnostic-commands)
- [Getting Help](#getting-help)

---

## Log Locations

Different phases write logs to different locations. Knowing where to look cuts troubleshooting time dramatically.

| Phase | Log Location | Notes |
|---|---|---|
| **WinPE** (Initialization through Postinstall) | `X:\MININT\SMSOSD\OSDLOGS\` | WinPE RAM disk — logs lost on reboot unless copied |
| **WinPE — consolidated** | `X:\MININT\SMSOSD\OSDLOGS\BDD.log` | The single most useful log. Start here. |
| **Full OS** (State Restore and later) | `C:\MININT\SMSOSD\OSDLOGS\` | Persists until `CleanupScripts.ps1` removes `MININT` |
| **MDT summary** | `C:\Windows\Temp\DeploymentLogs\` | Human-readable deployment summary |
| **OOBE orchestration** | `C:\ProgramData\OEM\Logs\SetupComplete.log` | Post-OOBE chain runner |
| **`pre.ps1` transcript** | `C:\ProgramData\OEM\Logs\pre_<timestamp>.log` | Detailed OEM setup log |
| **Framework shared log** | `C:\ProgramData\OEM\Logs\PBR_Deployment.log` | Shared structured log for both framework phases |
| **Framework transcript** | `C:\ProgramData\OEM\Logs\Master_<Phase>_<PID>_<timestamp>.log` | Per-phase PowerShell transcript |
| **Framework per-app** | `C:\ProgramData\OEM\Logs\<AppName>.log` | Only for apps the framework actually worked on |
| **DISM (offline image)** | `C:\Windows\Logs\DISM\dism.log` | Only after first boot into the deployed OS |
| **DISM (WinRE)** | `C:\Temp\WinREWork\dism_driver.log` | Created by `WinRE.ps1`, removed on success |
| **Deployment share** | `\\SERVER\DeploymentShare$\Logs\` | Server-side log of deployments (if configured) |

### Retrieving WinPE logs before reboot

WinPE logs in `X:\` are lost when the machine reboots. To preserve them:

**Option 1 — Add a task sequence step** that runs:

```cmd
net use Z: \\SERVER\Logs$\%ComputerName%
copy X:\MININT\SMSOSD\OSDLOGS\*.log Z:\
```

**Option 2 — Before rebooting, press F8** during the deployment and select **Command Prompt**, then run the same commands.

**Option 3 — View the logs directly.** In WinPE, run:

```cmd
notepad X:\MININT\SMSOSD\OSDLOGS\BDD.log
```

---

## How to Read an MDT Log

MDT logs are text files with timestamped entries in this format:

```
<![LOG[message]LOG]!><time="HH:MM:SS.mmm+000" date="MM-DD-YYYY" component="ComponentName" context="" type="N" thread="1234" file="filename">
```

The critical field is `type`:

| Type | Meaning |
|---|---|
| `1` | Info — normal operation |
| `2` | Warning — non-fatal but notable |
| `3` | Error — something failed |
| `4` | Fatal — deployment cannot continue |

### Quick filtering

Find all errors and warnings in a log:

```powershell
Select-String -Path "C:\MININT\SMSOSD\OSDLOGS\BDD.log" -Pattern 'type="[34]"' | Select-Object -Last 50
```

### Tracing a failure

When a task sequence step fails:

1. Find the failed step's name in the deployment summary.
2. Search `BDD.log` for that step name.
3. Look at the ~30 lines before the failure — the cause is usually there.
4. Cross-reference with the step-specific log (e.g. `ZTIDiskpart.log` for partitioning).

---

## WinPE and Boot Issues

### PXE client hangs at "Contacting DHCP" or "No boot filename received"

**Cause:** DHCP is not serving the PXE boot options, or WDS is not responding.

**Fix:**

1. Verify DHCP Option 066 (Boot Server Host Name) is set to the IP of the WDS server.
2. Verify DHCP Option 067 (Bootfile Name) is `boot\x64\wdsnbp.com`.
3. Verify WDS is authorized in AD (domain-joined) or is in Standalone mode (workgroup).
4. Check the WDS event log on the server:
   ```
   eventvwr.msc → Applications and Services Logs → Microsoft → Windows → Deployment-Services-Diagnostics
   ```
5. Verify no other DHCP server on the same subnet is intercepting the request.

### PXE client boots but the WIM fails to download

**Cause:** Boot image is corrupt or missing, or the WDS server cannot reach the client.

**Fix:**

1. Verify both boot images are imported and enabled in WDS.
2. In WDS, right-click the boot image → **Properties** → **Verify** the file hash.
3. Confirm the client can ping the server on the deployment VLAN.
4. Verify `TFTP` traffic (UDP 69) is allowed through any firewall.

### PXE client downloads the boot image but hangs at "Windows is loading files..."

**Cause:** The boot image is incompatible with the client hardware, or a needed driver is missing.

**Fix:**

1. Regenerate the boot image with more drivers included (see `Control\Settings.xml` `Boot.x64.SelectionProfile`).
2. Add network and storage drivers to the boot image explicitly.
3. For Intel VMD systems, verify the VMD driver is included in the boot image — otherwise the machine may not see the disk and the deployment will fail later.

### Machine boots to the local OS instead of PXE

**Cause:** Boot order, or the machine has a valid boot sector on the local disk.

**Fix:**

1. Enter BIOS/UEFI and confirm network boot is first.
2. If the OS is already installed, some firmware prefers the local disk. Use the boot menu (F12, F9, F10, or Esc during POST) to force network boot.
3. On UEFI systems, verify PXE is enabled and Secure Boot is either disabled or properly configured.

### LiteTouch WinPE boots but no task sequence picker appears

**Cause:** `SkipTaskSequence=YES` in `CustomSettings.ini`, or no task sequences are available.

**Fix:**

1. Open `Control\CustomSettings.ini` in the deployment share.
2. Locate `SkipTaskSequence=YES`.
3. Either change to `SkipTaskSequence=NO`, or set `TaskSequenceID=WIN11PROX64` (or your preferred TS) so the correct sequence is picked automatically.

### "Unable to find a Deployment Share" error

**Cause:** The `DeployRoot` path in `Bootstrap.ini` is wrong, or the deployment share is not reachable.

**Fix:**

1. In WinPE, press **F8** to open a command prompt.
2. Run:
   ```cmd
   net use \\SERVER\DeploymentShare$
   ```
3. If this fails, the share is unreachable. Check:
   - Network connectivity (`ping SERVER`)
   - Share permissions (`Network User` must have Read access)
   - Credentials in `Bootstrap.ini` are correct
4. If the share is reachable, verify `Bootstrap.ini` has the correct `DeployRoot` value.

---

## Task Sequence Phase Failures

### Validation phase

#### "Check BIOS" step fails

**Cause:** BIOS/UEFI detection returns an unexpected value, or the script cannot read the firmware type.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\ZTIBIOSCheck.log`.
2. Verify the target firmware is UEFI or Legacy BIOS (not CSM).
3. If the machine is in an unusual mode (e.g. UEFI with CSM enabled), disable CSM in firmware.

#### "Validate" step fails on hardware

**Cause:** The target does not meet the minimum requirements in `CustomSettings.ini`.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\ZTIValidate.log`.
2. Look for the failed check (RAM, CPU speed, disk size).
3. If the target is intentionally below the thresholds, edit `Control\CustomSettings.ini` to lower the minimums.

### State Capture phase

#### "Capture User State" fails

**Cause:** USMT is not available, or the source machine's user profile is corrupt.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\ZTIUserState.log`.
2. Verify `USMTOfflineMigration` is not set to `TRUE` for a Refresh deployment.
3. For New Computer deployments, user state capture is skipped by design.

### Preinstall phase

#### "Format and Partition Disk" fails

**Cause:** The disk is in use, has an unexpected partition table, or the disk number is wrong.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\ZTIDiskpart.log`.
2. Verify `OSDDiskIndex` matches the target disk:
   ```cmd
   diskpart
   list disk
   ```
3. If `SetTargetOSDisk.ps1` picked the wrong disk (e.g. a USB drive), verify the USB is not enumerated as a non-USB bus type.
4. Manually wipe the disk before retrying:
   ```cmd
   diskpart
   select disk 0
   clean
   ```

#### "Load WinPE Drivers" fails or no disks are visible

**Cause:** The Intel VMD driver is not loaded, so WinPE cannot see the internal storage.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log` for `LoadWinPEDrivers` entries.
2. Verify the target CPU generation is supported by the script:
   ```powershell
   (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString
   ```
3. Verify the VMD driver folder exists at `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<version>` or on the DEPLOY USB.
4. If the CPU generation is not mapped in `LoadWinPEDrivers.ps1`, add a mapping:
   ```powershell
   $IntelVMDVersion = switch ($IntelGen) {
       { $_ -ge 12 } { "20.2.6.1025.3" }
       11            { "19.5.8.1059.2" }
       default       { $null }
   }
   ```
5. If the driver loads but the disk is still not visible, try a newer VMD driver version.

#### "Clean All Fixed Drives" fails

**Cause:** A disk is offline, read-only, or in use.

**Fix:**

1. Check the task sequence log for the specific error.
2. Open a command prompt in WinPE and run:
   ```cmd
   diskpart
   list disk
   select disk <N>
   detail disk
   ```
3. If a disk is marked read-only:
   ```cmd
   attributes disk clear readonly
   ```
4. If a disk is offline:
   ```cmd
   online disk
   ```
5. If the drive is a USB device being wiped unintentionally, disconnect it before deployment.

#### "Create Recovery Partition" fails

**Cause:** Insufficient free space on the Windows partition, or `diskpart` cannot shrink it.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\ZTIDiskpart.log`.
2. Confirm the Windows partition has at least 1 GB of free space after apply. Adjust partition sizes in the task sequence if needed:
   - `OSDPartitions1Size` (Windows partition size as `%` of disk)
3. If `diskpart` fails to shrink due to unmovable files, run defragmentation on the target first, or increase the recovery partition size beyond the minimum.

### Install phase

#### "Install Operating System" fails

**Cause:** The WIM is missing, corrupt, or the wrong index is specified.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\LTIApply.log`.
2. Verify the OS WIM exists at the path in `OperatingSystems.xml`:
   ```
   Operating Systems\Win11Prox64\install.wim
   ```
3. Verify the WIM image index:
   ```cmd
   dism /Get-WimInfo /WimFile:install.wim
   ```
4. Verify the task sequence's `Install Operating System` step points at the correct OS entry.

#### "Apply Updates" fails

**Cause:** Update packages are corrupt, or DISM cannot apply them.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log` for `ApplyUpdates` entries.
2. Verify the update source exists:
   ```powershell
   Test-Path "\\SERVER\Shared\Updates\Win11"
   ```
3. If using the DEPLOY USB, verify:
   ```powershell
   Test-Path "E:\Updates\Win11"
   ```
4. Manually test each `.msu` file:
   ```cmd
   dism /Image:C:\ /Add-Package /PackagePath:<path>
   ```
5. If a specific `.msu` is corrupt, re-download it from the Microsoft Update Catalog.

#### "Copy OEM files" fails

**Cause:** The `$OEM$` folder is not found, or the destination is not writable.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log` for `CopyOEM` entries.
2. Verify `$OEM$` exists under `<DeployRoot>\x64\` or `<DeployRoot>\x86\` (not at the deployment share root).
3. Verify the destination Windows volume is mounted and writable.

#### "Extract OEM Apps" fails

**Cause:** 7-Zip is not available in WinPE, or the vendor `.7z` is not found.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log`.
2. Verify 7-Zip is present in the boot image:
   ```powershell
   Test-Path "X:\Program Files\7-Zip\7z.exe"
   ```
3. If missing, ensure `Boot.x64.ExtraDirectory` in `Settings.xml` points to `...\Boot\Addon\x64` and that the folder contains the 7-Zip files.
4. Verify the source path exists:
   ```powershell
   Test-Path "\\SERVER\Shared\OEM\x64"
   ```
5. If the manufacturer is not matched, check the log for the detected manufacturer string, then either:
   - Rename the vendor archive to match the detected name, or
   - Add a new case to the `switch` in `ExtractOEMAppsx64.ps1`.

#### "Extract OEM Drivers" fails or no driver pack found

**Cause:** The model string does not match any archive name, or the archive is not present.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log` for the detected model.
2. Look for a line similar to:
   ```
   Detected model: Dell Latitude 5430
   ```
3. Verify a matching `.7z` exists:
   ```powershell
   Get-ChildItem "\\SERVER\Shared\DriverPacks" | Where-Object Name -like "*Latitude 5430*"
   ```
4. If the archive name does not match, rename it. The script matches:
   - Exact model name
   - Model + CPU generation (e.g. `Dell Latitude 5430 12th Gen Intel`)
   - Truncated model (HP simplifies, Lenovo base models)
5. If the model string in the log is unexpected (e.g. `System Product Name`), the BIOS is not populating the model correctly. Check the BIOS/UEFI SMBIOS settings.

#### "Apply OEM Drivers" fails or drivers are not applied

**Cause:** The driver pack folder is missing, or DISM cannot inject a specific driver.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log`.
2. Verify the extracted drivers are present:
   ```powershell
   Test-Path "C:\Recovery\OEM\Drivers"
   ```
3. Check the DISM log for individual driver errors:
   ```cmd
   dism /Image:C:\ /Get-Drivers
   ```
4. If a specific `.inf` fails, remove it from the driver pack and re-archive.

### Postinstall phase

#### "Add Windows Recovery (WinRE)" fails

**Cause:** WinRE image is missing, or `reagentc` cannot configure the recovery partition.

**Fix:**

1. Check `X:\MININT\SMSOSD\OSDLOGS\BDD.log` and any `dism_driver.log` under `C:\Temp\WinREWork`.
2. Verify the source WinRE exists:
   ```powershell
   Test-Path "\\SERVER\Shared\WindowsRE\Win11\x64\winre.wim"
   ```
3. Verify the recovery partition has a drive letter (temporarily assigned):
   ```cmd
   diskpart
   list volume
   ```
4. Manually configure WinRE on the target:
   ```cmd
   reagentc /setreimage /path R:\Recovery\WindowsRE /target C:\Windows
   reagentc /enable
   reagentc /info
   ```

#### "Cleanup Scripts" fails

**Cause:** A file is locked by another process.

**Fix:**

1. The step is configured with `continueOnError="true"`, so a failure is non-fatal.
2. Check for processes still running from `MININT`:
   ```powershell
   Get-Process | Where-Object Path -like "*MININT*"
   ```
3. If cleanup consistently fails, delete the leftover MDT files manually after the deployment completes.

### State Restore phase

#### "Install Applications" fails

**Cause:** Application GUID is invalid, or the application source is missing.

**Fix:**

1. Check `C:\MININT\SMSOSD\OSDLOGS\ZTIApplications.log`.
2. Verify the application GUID in the task sequence matches an application in `Applications.xml`.
3. Verify the application source is accessible:
   ```powershell
   Test-Path "\\SERVER\DeploymentShare$\Applications\<AppName>"
   ```

#### "Restore User State" fails

**Cause:** USMT cannot restore the captured state, or the state store is missing.

**Fix:**

1. Check `C:\MININT\SMSOSD\OSDLOGS\ZTIUserState.log`.
2. Verify the state store exists at `C:\UserState` or `\\SERVER\UserState`.
3. For New Computer deployments, restore is skipped.

#### "Apply Local GPO Package" fails

**Cause:** LGPO is not present, or the policy backup is corrupt.

**Fix:**

1. Check the task sequence log.
2. Verify LGPO is present:
   ```powershell
   Test-Path "C:\Recovery\OEM\LGPO\LGPO.exe"
   ```
3. Verify the policy backup exists:
   ```powershell
   Test-Path "C:\Recovery\OEM\LGPO\Backup"
   ```
4. Re-create the backup if needed with the LGPO tool.

---

## Script-Specific Issues

### LoadWinPEDrivers.ps1

#### No VMD driver loaded even though the CPU is 11th Gen or newer

**Symptoms:** Log shows no VMD driver activity, or the script exits without loading.

**Possible causes and fixes:**

1. **Storage is already visible.** The script checks `diskpart` first. If any disk is visible, it exits. Verify the target actually needs VMD:
   ```cmd
   diskpart
   list disk
   ```
   If disks are listed, no VMD driver is needed.

2. **Driver folder is missing.** Verify the driver exists:
   ```powershell
   Test-Path "\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\20.2.6.1025.3"
   ```

3. **CPU detection failed.** Check the CPU name reported:
   ```powershell
   (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString
   ```
   If the CPU is not recognized, add a mapping in `Get-IntelProcessorGeneration`.

4. **Generation-specific mapping is missing.** For a new CPU generation, add it to the switch:
   ```powershell
   $IntelVMDVersion = switch ($IntelGen) {
       { $_ -ge 16 } { "22.x.x.xxxx" }
       { $_ -ge 12 } { "20.2.6.1025.3" }
       11            { "19.5.8.1059.2" }
       default       { $null }
   }
   ```

### SetTargetOSDisk.ps1

#### The wrong disk is selected as the target

**Symptoms:** OS is installed to a small disk when a larger one exists, or the OS goes to a USB drive.

**Fix:**

1. Verify the USB drive is not being treated as a fixed disk:
   ```powershell
   Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, BusType, MediaType, Size
   ```
   If the USB reports `BusType = USB` (correct), it will be excluded.
2. If the sort order is wrong (you want the largest SSD, not the smallest), edit the script:
   ```powershell
   $OSDisk = $NVMeSSDs | Sort-Object -Property Size -Descending | Select-Object -First 1 -ExpandProperty DeviceID
   ```

### ExtractOEMDrivers.ps1

#### Wrong driver pack extracted

**Symptoms:** A driver pack for a different model is extracted, or a more generic pack is picked over a specific one.

**Fix:**

1. The script sorts candidates by filename length (descending) then archive size (descending). The longest matching filename wins.
2. To force a specific pack, use a longer, more specific name:
   ```
   Dell Latitude 5430 12th Gen Intel (2024-11).7z   ← wins over
   Dell Latitude 5430 12th Gen Intel.7z
   Dell Latitude 5430.7z
   ```

### ApplyOEMDrivers.ps1

#### Drivers are applied but hardware still has missing drivers

**Cause:** The driver pack is missing a category, or DISM rejected a specific driver.

**Fix:**

1. Check the DISM log for injection results:
   ```cmd
   dism /Image:C:\ /Get-Drivers /Format:Table
   ```
2. Verify all expected categories are present in the extracted pack:
   ```powershell
   Get-ChildItem "C:\Recovery\OEM\Drivers" -Directory
   ```
3. Missing categories: check the source driver pack. Add missing drivers and re-archive.

### WinRE.ps1

#### WinRE is not deployed, or VMD is not injected into WinRE

**Cause:** Source WinRE is missing, or the VMD marker file is not found.

**Fix:**

1. **VMD marker issue.** The marker file is written to `%TEMP%` in WinPE, which does not persist. Check whether the marker was ever found:
   ```powershell
   Test-Path "$env:TEMP\VMD_Loaded.txt"
   ```
   If missing (expected), VMD will not be injected into WinRE. To fix, modify `LoadWinPEDrivers.ps1` to write the marker to the target OS drive:
   ```powershell
   $WindowsDrive = (Get-Volume -FileSystemLabel Windows | Select-Object -First 1).DriveLetter
   $MarkerFile = "${WindowsDrive}:\Windows\Temp\VMD_Loaded.txt"
   ```

2. **Source WinRE missing.** Verify:
   ```powershell
   Test-Path "\\SERVER\Shared\WindowsRE\Win11\x64\winre.wim"
   ```
   If missing, extract from a Windows ISO.

3. **Recovery partition not accessible.** Check if the partition has a drive letter:
   ```cmd
   diskpart
   list volume
   ```
   If not, `WinRE.ps1` should assign one — check for errors in the log.

### pre.ps1

#### AnyDesk installation or password configuration fails

**Cause:** AnyDesk installer is missing, or the installer does not exit cleanly.

**Fix:**

1. Check `C:\ProgramData\OEM\Logs\pre_<timestamp>.log`.
2. Verify the installer exists:
   ```powershell
   Test-Path "C:\Recovery\OEM\Apps\AnyDesk.exe"
   ```
3. Verify the installation path:
   ```powershell
   Test-Path "C:\Program Files (x86)\AnyDesk\anydesk.exe"
   ```
4. If password configuration fails, check for a service that has not started. Restart the AnyDesk service and retry:
   ```powershell
   Restart-Service -Name "AnyDesk"
   ```

#### Office installation fails

**Cause:** `setup.exe` or `configuration.xml` is missing, or the installer exits non-zero.

**Fix:**

1. Check the log for the Office install section.
2. Verify the installer folder exists:
   ```powershell
   Test-Path "C:\Recovery\OEM\Apps\Office365"
   ```
3. Verify both `setup.exe` and `configuration.xml` are present.
4. Test the installer manually:
   ```cmd
   cd C:\Recovery\OEM\Apps\Office365
   setup.exe /configure configuration.xml
   ```
5. If the exit code is non-zero, review the Office install log at `%temp%\<timestamp>.log`.

#### Office activation is deferred

**Cause:** By design — `pre.ps1` fails closed if any Office app is running in an interactive user session.

**Fix:**

1. This is intentional. The gate ensures Ohook does not run while Office is open.
2. If you need to force activation, run the Ohook script manually as SYSTEM after OOBE:
   ```cmd
   C:\Recovery\OEM\Activation\Ohook_Activation.cmd /Ohook
   ```

#### Windows activation fails

**Cause:** OEM firmware key is missing, or the key does not match the installed edition.

**Fix:**

1. Check the activation status:
   ```cmd
   slmgr /dlv
   ```
2. Verify the firmware key is readable:
   ```powershell
   (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
   ```
3. If the key is present but activation fails, check the key matches the OS edition:
   ```powershell
   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
   ```
4. Compare with `OA3xOriginalProductKeyDescription`. If they do not match, the machine is licensed for a different edition. Either deploy the matching edition, or rely on the HWID fallback that `Activate-Windows` already tries.

#### UWP app installation fails with "Element not found" or "0xc1570118"

**Cause:** The OS already has a newer version of the same package provisioned.

**Fix:**

1. This is expected behavior. The script catches these errors and treats the app as already installed.
2. To force a downgrade, remove the existing provisioned package first:
   ```powershell
   Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*PackageName*" | Remove-AppxProvisionedPackage -Online
   ```

#### "CPU counters unavailable; using fixed 5s settle delay"

**Cause:** Performance counters are broken or unstable. Expected on some systems with third-party drivers.

**Fix:**

1. This is not a fatal error. The script falls back gracefully.
2. If it happens frequently, you can disable the `Wait-SystemIdle` call in `pre.ps1`. It is a nicety, not a requirement.

---

## OOBE and SetupComplete Issues

### SetupComplete.cmd does not run

**Cause:** The file is not in the expected location.

**Fix:**

1. Verify the file exists:
   ```powershell
   Test-Path "C:\Windows\Setup\Scripts\SetupComplete.cmd"
   ```
2. If missing, the `$OEM$\$$\Setup\` folder was not copied to the target. Verify `CopyOEM.wsf` runs and the `$OEM$` folder structure is correct under `<arch>\$OEM$`.
3. Verify `SetupComplete.cmd` is present in your deployment share at `<arch>\$OEM$\$$\Setup\Scripts\`.

### SetupComplete.cmd runs but pre.ps1 does not

**Cause:** PowerShell is missing or blocked, or `pre.ps1` does not exist.

**Fix:**

1. Check the SetupComplete log:
   ```powershell
   Get-Content "C:\ProgramData\OEM\Logs\SetupComplete.log"
   ```
2. Verify `pre.ps1` exists:
   ```powershell
   Test-Path "C:\Recovery\OEM\pre.ps1"
   ```
3. Verify PowerShell is available:
   ```cmd
   powershell.exe -Command "Get-Host"
   ```
4. If ExecutionPolicy blocks the script, verify the `-ExecutionPolicy Bypass` flag is in `SetupComplete.cmd`.

### pre.ps1 runs but fails partway through

**Cause:** A script error, or a missing dependency.

**Fix:**

1. Check the transcript:
   ```powershell
   Get-Content "C:\ProgramData\OEM\Logs\pre_*.log" | Select-String -Pattern "ERROR|FATAL"
   ```
2. Because `pre.ps1` continues on error, a partial failure does not stop the deployment. Review the log for specific failures and address them individually.
3. If `pre.ps1` aborts entirely (the top-level catch fires), look for `[FATAL] pre.ps1 aborted:` in the log.
4. Common causes: missing 7-Zip, missing activation scripts, missing LGPO tool.

### Customizations.ps1 does not run

**Cause:** The file does not exist, or `SetupComplete.cmd` exited early.

**Fix:**

1. Verify the file exists:
   ```powershell
   Test-Path "C:\Recovery\OEM\Customizations.ps1"
   ```
2. If `pre.ps1` hangs, `SetupComplete.cmd` waits indefinitely. Check the log for signs of hanging.

---

## Framework Issues

### Framework phases do not converge

**Symptoms:** `USER_DONE` marker is never written. Health check fails. Apps appear in `FailedApps` in the summary.

**Fix:**

1. Check the shared log:
   ```powershell
   Get-Content "C:\ProgramData\OEM\Logs\PBR_Deployment.log" | Select-String -Pattern "ERROR|FAILED"
   ```
2. Check the phase transcript:
   ```powershell
   Get-ChildItem "C:\ProgramData\OEM\Logs\Master_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   ```
3. Look for the outcome line format:
   ```
   OUTCOME: <AppName> — Failed (reason)
   ```
4. Common causes:
   - An app declared `Required: true` failed
   - The health check found a missing app after USER phase
   - The `Set-DeploymentStage` write failed (registry issue)

### Winget installs fail in USER phase

**Cause:** Winget is missing, the bypass setting is not configured, or the package source is unavailable.

**Fix:**

1. Check that winget is available:
   ```powershell
   winget --version
   ```
2. Check the framework's winget log within the phase transcript.
3. If winget requires admin bypass and it is not enabled, check the framework's session log for `Initialize-WinGetSession` and whether it detected a known-disabled baseline.
4. For winget-source issues, run:
   ```powershell
   winget source update
   ```

### Resume task does not fire

**Cause:** The scheduled task was not registered, or the principal or trigger is wrong.

**Fix:**

1. Check for the task:
   ```powershell
   Get-ScheduledTask -TaskName "*PBR*"
   ```
2. Check its last run result:
   ```powershell
   Get-ScheduledTaskInfo -TaskName "<Profile.ResumeTaskName>"
   ```
3. Verify the trigger is `AtLogOn` and the principal is `Administrators` at `Highest`.
4. If the task was never registered, check the SYSTEM phase log for errors in `Register-ResumeTask`.

### AutoApply ownership is not honored

**Cause:** The `C:\Recovery\AutoApply` folder is missing or incomplete.

**Fix:**

1. Verify the folder exists:
   ```powershell
   Test-Path "C:\Recovery\AutoApply"
   ```
2. The framework checks for the expected file set per OS version:
   - Windows 10: `LayoutModification.xml`
   - Windows 11: `LayoutModification.json` and `TaskbarLayoutModification.xml`
3. If the folder exists but is incomplete, the framework takes ownership. Complete the file set or remove the folder entirely.

### Stage marker is missing or wrong

**Cause:** Registry write failed, or the phase did not complete.

**Fix:**

1. Read the marker directly:
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\OEM\<Brand>" -Name "DeploymentStage"
   ```
2. Expected values: `NONE` (or absent), `SYSTEM_DONE`, `USER_DONE`.
3. If missing, check the framework transcript for `Set-DeploymentStage` errors.
4. If the value is unexpected (e.g. `SYSTEM_DONE` on a machine that previously had `USER_DONE`), see the marker-downgrade note in [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md#known-limitations).

---

## Hardware-Specific Issues

### Intel VMD (all generations)

#### Target machine's internal disk is not visible in WinPE

**Cause:** VMD is enabled in BIOS, and no VMD driver is loaded.

**Fix:** See [LoadWinPEDrivers.ps1 troubleshooting](#loadwinpedriversps1) above.

**Alternative:** Disable VMD in BIOS/UEFI. Not recommended for production — VMD provides RAID and power benefits — but a valid workaround for testing.

### Intel 11th Gen and newer

#### `Get-IntelProcessorGeneration` returns `$null` for a supported CPU

**Cause:** The CPU name string does not match any pattern in the function.

**Fix:**

1. Get the CPU name:
   ```powershell
   (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString
   ```
2. Compare against the patterns in `Get-IntelProcessorGeneration`:
   - `i[3579][- ]\d{4,5}` for Core i-series
   - `Core\s+Ultra\s+[3579]\s+\d{3,4}` for Core Ultra
   - `Core\s+[3579]\s+\d{3,4}` for new Core (non-i)
   - `Xeon.*?\d{4,5}` for Xeon
3. If the CPU string does not match, add a new pattern or extend the existing ones.

### AMD Ryzen

#### Ryzen systems are treated as Intel or unknown

**Cause:** `Get-IntelProcessorGeneration` correctly returns `$null` for AMD — this is by design.

**Fix:**

1. `ExtractOEMDrivers.ps1` still detects the manufacturer and can match AMD-specific packs. Verify the pack is named correctly:
   ```
   HP EliteBook 845 G9 Ryzen 7.7z
   ```
2. For AMD RAID or NVMe, add specific handling to `LoadWinPEDrivers.ps1` if needed.

### Modern Intel platforms with storage requirements

#### The target requires a newer VMD version than what is bundled

**Cause:** The bundled VMD driver version is outdated for a new CPU generation.

**Fix:**

1. Download the latest VMD driver from Intel.
2. Place the extracted driver at `\\SERVER\Shared\Drivers\WinPE\Storage\Intel\x64\<new-version>\` and at `\\SERVER\Shared\DriverPacks\Storage\Intel\<new-version>\` inside the applicable model pack.
3. Update the generation → version mapping in `LoadWinPEDrivers.ps1` and `ApplyOEMDrivers.ps1`.

### HP business laptops

#### HP model strings do not match expected archive names

**Cause:** HP reports the model with variations (e.g. `HP EliteBook 840 14 inch G10 Notebook PC`).

**Fix:**

1. The script builds multiple candidate patterns including the simplified model (`HP EliteBook 840 G10`). Verify one of the patterns matches your archive.
2. Rename your archive to match the simplified form:
   ```
   HP EliteBook 840 G10 13th Gen Intel.7z
   ```
3. If the pattern still does not match, add a simplification rule to `Get-HPSimplifiedModel`.

### Lenovo ThinkPads

#### Lenovo model strings include the SKU suffix

**Cause:** Lenovo reports `ThinkPad T14 Gen 3 21AH00BGUS` (with SKU suffix).

**Fix:**

1. `Get-LenovoBaseModel` should strip the SKU suffix. Verify it works by checking the log.
2. Rename your archive to match the base model:
   ```
   Lenovo ThinkPad T14 Gen 3.7z
   ```

---

## Post-Deployment Issues

### Windows is not activated after deployment

**Cause:** OEM firmware key is missing or does not match the installed edition.

**Fix:**

1. Verify on the target:
   ```cmd
   slmgr /dlv
   ```
2. If the license status is `Notification` or `Unlicensed`, run:
   ```cmd
   slmgr /ato
   ```
3. If activation fails with error `0xC004F050` (invalid key), the key does not match the edition. Deploy the matching edition instead.
4. If the target has no firmware key (VM or custom build), activation requires a retail or volume license.

### Drivers are missing after deployment

**Cause:** OEM driver pack did not include the specific driver, or DISM rejected it.

**Fix:**

1. Check **Device Manager** for unknown devices.
2. Note the hardware ID of the missing device:
   ```
   Properties → Details → Hardware Ids
   ```
3. Search for the matching driver in the vendor's driver pack, or download it separately.
4. Add the driver to the driver pack and re-deploy, or install it manually.

### WinRE is not enabled after deployment

**Cause:** WinRE deployment failed, or the recovery partition is not accessible.

**Fix:**

1. Check WinRE status:
   ```cmd
   reagentc /info
   ```
2. If `Windows RE status: Disabled`, enable it:
   ```cmd
   reagentc /enable
   ```
3. If the enable fails, verify the recovery partition exists:
   ```cmd
   diskpart
   list volume
   ```
4. If the partition exists but is not accessible, assign a letter and retry:
   ```cmd
   diskpart
   select volume <N>
   assign letter=R
   reagentc /setreimage /path R:\Recovery\WindowsRE
   reagentc /enable
   ```

### LGPO policies are not applied

**Cause:** LGPO tool is missing, or the policy backup is empty.

**Fix:**

1. Verify LGPO is present:
   ```powershell
   Test-Path "C:\Recovery\OEM\LGPO\LGPO.exe"
   ```
2. Verify policies are present:
   ```powershell
   Get-ChildItem "C:\Recovery\OEM\LGPO\Backup"
   ```
3. Manually apply:
   ```cmd
   "C:\Recovery\OEM\LGPO\LGPO.exe" /g "C:\Recovery\OEM\LGPO\Backup"
   ```
4. Verify with:
   ```cmd
   gpresult /r /scope:computer
   ```

### OEM apps are not installed

**Cause:** OEM app archive not found, or extraction failed.

**Fix:**

1. Verify the archive was extracted:
   ```powershell
   Get-ChildItem "C:\Recovery\OEM\Apps"
   ```
2. If empty, the extraction step failed. Check the deployment log under `X:\MININT\SMSOSD\OSDLOGS\` or `C:\MININT\SMSOSD\OSDLOGS\`.
3. Install the apps manually:
   ```powershell
   Get-ChildItem "C:\Recovery\OEM\Apps" -Filter *.exe | ForEach-Object {
       Start-Process $_.FullName -ArgumentList "/S" -Wait
   }
   ```

### Post-deployment scripts fail

**Cause:** The scripts expect content on `\\SERVER\Shared` or a `DEPLOY`-labeled USB.

**Fix:**

1. Check which script failed and read the script itself:
   ```powershell
   Get-Content "C:\Scripts\<ScriptName>.cmd"
   ```
2. Verify the network share is reachable:
   ```powershell
   Test-Path "\\SERVER\Shared\ScanState"
   ```
3. Verify the USB is labeled `DEPLOY` if using offline media:
   ```powershell
   Get-Volume | Where-Object FileSystemLabel -eq 'DEPLOY'
   ```
4. For `4ScanState.cmd` failures, verify the USMT tool is present under `\\SERVER\Shared\ScanState\amd64\`.

---

## Useful Diagnostic Commands

### WinPE

```cmd
:: Open a command prompt
F8

:: View the disk layout
diskpart
list disk
list volume
exit

:: Check CPU name
reg query "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0" /v ProcessorNameString

:: Check model and manufacturer
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemProductName
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemManufacturer

:: Read a log
notepad X:\MININT\SMSOSD\OSDLOGS\BDD.log
```

### Full OS (post-deployment)

```powershell
# Check Windows activation
slmgr /dlv

# Check WinRE status
reagentc /info

# List installed drivers
dism /Online /Get-Drivers /Format:Table

# List provisioned AppX packages
Get-AppxProvisionedPackage -Online | Select-Object DisplayName, Version

# Check OEM logs
Get-ChildItem "C:\ProgramData\OEM\Logs"

# Check framework stage marker
Get-ItemProperty "HKLM:\SOFTWARE\OEM\<Brand>" -Name "DeploymentStage"

# Check applied LGPO policies
gpresult /r /scope:computer

# Check the OEM firmware key
(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey

# Check the OS edition
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
```

### Deployment share

```powershell
# Verify share is reachable
net use \\SERVER\DeploymentShare$

# Verify a specific path exists
Test-Path "\\SERVER\Shared\OEM\x64\Dell.7z"

# List task sequences on the share
Get-ChildItem "\\SERVER\DeploymentShare$\Control\Task Sequences"

# List drivers in the share
Get-ChildItem "\\SERVER\DeploymentShare$\Out-of-box Drivers" -Directory
```

### Reading logs on the fly

```powershell
# Follow a log file in real time (full OS)
Get-Content "C:\ProgramData\OEM\Logs\pre_*.log" -Wait -Tail 20

# Show all errors from pre.ps1 log
Select-String -Path "C:\ProgramData\OEM\Logs\pre_*.log" -Pattern "ERROR|FATAL"

# Show all errors from BDD.log
Select-String -Path "C:\MININT\SMSOSD\OSDLOGS\BDD.log" -Pattern 'type="[34]"'

# Show all FAILED outcomes in the framework log
Select-String -Path "C:\ProgramData\OEM\Logs\PBR_Deployment.log" -Pattern "FAILED|OUTCOME:.*Failed"
```

---

## Getting Help

If your issue is not covered here:

1. **Search existing issues** — [github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues)
2. **Search existing discussions** — [github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions)
3. **Open a new discussion** for general questions — [github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions/new](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/discussions/new)
4. **Open a bug report** for reproducible issues — use the [bug report template](https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment/issues/new?template=bug_report.yml)

### What to include when asking for help

- **What you expected to happen** — one sentence
- **What actually happened** — one sentence, with the exact error message
- **Where in the deployment it failed** — phase, step name, or script
- **Hardware details:**
  - Make, model, CPU generation
  - BIOS version and date
  - UEFI or Legacy BIOS mode
- **Software details:**
  - Which task sequence (`WIN11PROX64`, `WIN10PROX64`, or `WIN10PROX86`)
  - MDT version
  - ADK version
- **Relevant log excerpt** — 20–30 lines around the error, not the whole log
- **What you already tried** — so suggestions are not repeated

**Do not paste entire logs inline.** Attach them as files or upload to a [GitHub Gist](https://gist.github.com/) and link the URL.

### Response times

This is a hobby project maintained in spare time. Response times vary from hours to days. If your issue is blocking production, consider it a signal to invest in vendor-supported deployment tooling (Intune, Autopilot, or the OEM's own imaging platform) for production, and use this project for lab or small-batch deployments.

---

*See [docs/SCRIPTS.md](SCRIPTS.md) for script documentation, [docs/APPS-FRAMEWORK.md](APPS-FRAMEWORK.md) for the framework reference, [docs/SETUP.md](SETUP.md) for the initial setup walkthrough, and the [README](../README.md) for the project overview.*
