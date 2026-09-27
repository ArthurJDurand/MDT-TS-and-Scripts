<#
.SYNOPSIS
    Vendor-neutral registry helpers.
#>

function Set-RegistryValueSilent {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [object]$Value,
        [string]$Type = 'String'
    )

    # Framework convention: registry writes use reg.exe exclusively.
    # PowerShell's registry provider has exhibited handle retention that
    # blocked hive unload; applying reg.exe uniformly keeps the discipline
    # simple and avoids reintroducing that class of failure on any path.
    # Read-back uses the PowerShell provider for reads only; read handles
    # do not exhibit retention behavior.

    # Translate 'HKLM:\Software\Foo' -> 'HKLM\Software\Foo'.
    # Both forms accepted; the PSDrive colon is optional.
    $regPath = $Path -replace '^(HKLM|HKCU|HKCR|HKU|HKCC):\\?', '$1\'

    # Translate the PowerShell property type name to the reg.exe REG_* token.
    # Supported types are those this helper can serialize correctly via
    # reg.exe /d. QWord, MultiString, and Binary require type-specific /d
    # formatting (hex for binary, \0-separated for multi-string) that this
    # helper does not implement. A caller that needs them should serialize
    # and write directly rather than receive a silently-wrong value.
    $regType = switch ($Type) {
        'String'       { 'REG_SZ' }
        'ExpandString' { 'REG_EXPAND_SZ' }
        'DWord'        { 'REG_DWORD' }
        default {
            throw "Set-RegistryValueSilent: unsupported registry type '$Type'. Supported types: String, ExpandString, DWord."
        }
    }

    # reg.exe does not accept $true/$false for REG_DWORD. Convert booleans.
    $regValue = $Value
    if ($regType -eq 'REG_DWORD' -and $regValue -is [bool]) {
        $regValue = if ($regValue) { 1 } else { 0 }
    }

    # Native command stderr under $ErrorActionPreference='Stop' is promoted
    # to a terminating error before $LASTEXITCODE can be inspected. A local
    # 'Continue' restores the intended contract: a reg.exe failure is
    # inspected via $LASTEXITCODE and reported as $false, not thrown. The
    # prior value is restored in finally so the caller's preference is not
    # permanently altered. Mirrors Set-OfflineHiveValueSet's protection.
    $previousEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $regOutput = & reg.exe ADD $regPath /v $Name /t $regType /d $regValue /f 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-DeploymentLog -Message "Registry write failed at $Path\$Name : $regOutput" -Level WARN
            return $false
        }
    }
    finally {
        $ErrorActionPreference = $previousEap
    }

    # Read-back verification: a write that returns exit 0 can still fail
    # silently under quota, ACL, or partial-write conditions.
    try {
        $read = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        $actual = $read.$Name
        switch ($Type) {
            'DWord'  { return ([int]$actual -eq [int]$Value) }
            default  { return ([string]$actual -eq [string]$Value) }
        }
    }
    catch {
        Write-DeploymentLog -Message "Registry read-back at $Path\$Name failed: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Set-OfflineHiveValueSet {
    # Writes a set of values into a mounted offline hive using reg.exe
    # exclusively, verifying the exit code of each write. Returns $true
    # only if the parent key creation and every value write succeeded.
    # Callers use this to distinguish "hardening applied" from "hardening
    # partially applied" without inspecting reg.exe output directly.
    #
    # This is a write-side helper. It exists alongside Set-RegistryValueSilent
    # (single-value) because a mounted offline hive takes the same write
    # discipline (reg.exe only; see PHILOSOPHY.md §6 invariant 7) but needs
    # the key created once and then N values written under it.
    param(
        [Parameter(Mandatory)] [string]$Mount,
        [Parameter(Mandatory)] [string]$SubKey,
        [Parameter(Mandatory)] [string[]]$Names,
        [Parameter(Mandatory)] [object]$Value,
        [string]$Type = 'DWord'
    )

    $target = "$Mount\$SubKey"

    # Translate the PowerShell-style type name to the reg.exe REG_* token,
    # matching Set-RegistryValueSilent's public contract. reg.exe rejects
    # 'DWord'; it requires 'REG_DWORD'. Without this translation, every
    # per-key write fails with "ERROR: Invalid syntax." and the helper's
    # documented $true/$false contract never gets a chance to run.
    $regType = switch ($Type) {
        'String'       { 'REG_SZ' }
        'ExpandString' { 'REG_EXPAND_SZ' }
        'DWord'        { 'REG_DWORD' }
        default {
            throw "Set-OfflineHiveValueSet: unsupported registry type '$Type'. Supported types: String, ExpandString, DWord."
        }
    }

    $regValue = $Value
    if ($regType -eq 'REG_DWORD' -and $regValue -is [bool]) {
        $regValue = if ($regValue) { 1 } else { 0 }
    }

    # Native command stderr under $ErrorActionPreference='Stop' is promoted
    # to a terminating error before $LASTEXITCODE can be inspected. A local
    # 'Continue' restores the intended contract: a reg.exe failure is
    # inspected via $LASTEXITCODE and reported as $false, not thrown. The
    # prior value is restored in finally so the caller's preference is not
    # permanently altered.
    $previousEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'

        $null = & reg.exe ADD $target /f 2>&1 | Out-Null
        $ok = ($LASTEXITCODE -eq 0)

        foreach ($n in $Names) {
            $null = & reg.exe ADD $target /v $n /t $regType /d $regValue /f 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $ok = $false }
        }

        return $ok
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
}

function Get-DefaultUserSpotlightKeys {
    # Authoritative default list of ContentDeliveryManager values zeroed
    # in both the Default User offline hive (via reg.exe LOAD/UNLOAD)
    # and the live user's hive. All eleven OEM modules currently use
    # the identical list; centralizing it means a single edit updates
    # the fleet. A module that genuinely needs a different list can
    # pass -SpotlightKeys explicitly to the helpers below.
    return @(
        'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
        'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','RotatingLockScreenEnabled',
        'RotatingLockScreenOverlayEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
        'SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled',
        'SubscribedContent-353694Enabled','SubscribedContent-353698Enabled','SubscribedContent-88000326Enabled',
        'SystemPaneSuggestionsEnabled'
    )
}

function Invoke-DefaultUserHiveHardening {
    # Byte-for-byte behaviour preserved from the per-module
    # Invoke-*DefaultUserHiveSetup implementations this replaces.
    # Do NOT rewrite the reg.exe LOAD/UNLOAD dance, the GC.Collect
    # step, or the 30-attempt unload retry loop while consolidating —
    # those were the product of real debugging (handle retention
    # blocking hive unload) and are correctness-critical.
    param(
        [string]$MountPoint    = 'HKLM\MDT_DEFUSER',
        [string]$HiveFile      = 'C:\Users\Default\ntuser.dat',
        [string[]]$SpotlightKeys = (Get-DefaultUserSpotlightKeys)
    )

    # Ensure Windows Firewall is running. Some UWP/Store provisioning
    # paths require MpsSvc to be active.
    $fw = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
    if ($fw -and $fw.Status -ne 'Running') {
        Start-Service MpsSvc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    if (Test-Path $HiveFile) {
        # MountPoint is the reg.exe form (HKLM\MDT_DEFUSER). Derive the
        # PowerShell provider form for the Test-Path guard.
        $mountDrive = 'HKLM:\' + ($MountPoint -replace '^HKLM\\', '')
        $hiveLoaded = $false

        # If a prior run left the mount point registered, unload it
        # before re-mounting. Otherwise reg.exe LOAD fails with "already
        # loaded" and hive setup is silently skipped. The Test-Path
        # guard is required: reg.exe UNLOAD on an unmounted path writes
        # "ERROR: The parameter is incorrect." to stderr, and under
        # $ErrorActionPreference = 'Stop' PowerShell promotes that to a
        # terminating error that aborts the phase. Reads via the
        # registry provider are permitted by PHILOSOPHY.md §6 invariant
        # 7; only writes are restricted to reg.exe.
        if (Test-Path $mountDrive) {
            # Wrap the pre-mount UNLOAD in a local EAP=Continue scope.
            # A stale mount that Test-Path sees but reg.exe cannot remove
            # would otherwise promote reg.exe's stderr to a terminating
            # error under a caller's $ErrorActionPreference = 'Stop'.
            # Mirrors Set-RegistryValueSilent and Set-OfflineHiveValueSet.
            $preUnloadEap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $null = & reg.exe UNLOAD $MountPoint 2>&1
            } finally {
                $ErrorActionPreference = $preUnloadEap
            }
            Start-Sleep -Milliseconds 500
        }

        try {
            $null = & reg.exe LOAD $MountPoint $HiveFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                $hiveLoaded = $true
                $hardeningOk = Set-OfflineHiveValueSet -Mount $MountPoint `
                    -SubKey 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
                    -Names $SpotlightKeys -Value 0 -Type 'DWord'
                if (-not $hardeningOk) {
                    Write-DeploymentLog -Message 'Default User hive ContentDeliveryManager writes failed or were incomplete.' -Level WARN
                }
            }
            if (-not $hiveLoaded) {
                Write-DeploymentLog -Message "Default User hive was not loaded; default-profile hardening skipped." -Level WARN
            }
        } catch {
            Write-DeploymentLog -Message "Default User hive hardening failed: $($_.Exception.Message)" -Level WARN
        }
        finally {
            if ($hiveLoaded) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 500
                $unloaded = $false
                for ($i = 0; $i -lt 30; $i++) {
                    $null = & reg.exe UNLOAD $MountPoint 2>&1
                    if ($LASTEXITCODE -eq 0) { $unloaded = $true; break }
                    Start-Sleep -Seconds 1
                }
                if (-not $unloaded) {
                    Write-DeploymentLog -Message "WARNING: Failed to unload Default User hive from $MountPoint after 30 attempts. The hive may remain loaded until reboot." -Level WARN
                }
            }
        }
    }

    $null = Set-RegistryValueSilent -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type 'DWord'
    $null = Set-RegistryValueSilent -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Name 'DisableConsumerFeatures' -Value 1 -Type 'DWord'
}

function Invoke-LiveUserSpotlightSuppression {
    # Byte-for-byte behaviour preserved from the per-module
    # Invoke-*LiveUserSpotlightSuppression implementations.
    param(
        [string[]]$SpotlightKeys = (Get-DefaultUserSpotlightKeys)
    )
    $hive = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    try {
        foreach ($key in $SpotlightKeys) {
            $null = Set-RegistryValueSilent -Path $hive -Name $key -Value 0 -Type 'DWord'
        }
    } catch {
        Write-DeploymentLog -Message "Live-user Spotlight suppression failed: $($_.Exception.Message)" -Level WARN
    }
}

Export-ModuleMember -Function `
    Set-RegistryValueSilent, `
    Set-OfflineHiveValueSet, `
    Get-DefaultUserSpotlightKeys, `
    Invoke-DefaultUserHiveHardening, `
    Invoke-LiveUserSpotlightSuppression
