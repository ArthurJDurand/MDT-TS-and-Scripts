<#
.SYNOPSIS
    Vendor-neutral local installer discovery and execution.

.DESCRIPTION
    Handles deterministic installer discovery, MSI mutex waits, EXE/MSI/MSP/CMD
    execution with timeout-kill-wait, MSI 1618 retry, and AppX/MSIX provisioning
    with sibling/package-local/global dependency resolution.
#>

function Set-AppOutcomeFields {
    # Merge-by-field helper for $Context.AppOutcomes. The prior code assigned
    # a fresh hashtable at every local-installer outcome site, which discarded
    # any reason fields a prior method (typically winget) had already written
    # for the same app in the same phase. Winget's history (WinGetSource,
    # WinGetExitCode) is the most valuable diagnostic on the "winget failed,
    # local installer rescued" path, and must survive the local installer's
    # own field writes.
    #
    # Sets only the named fields, preserving any pre-existing keys. Creates
    # the entry as an empty hashtable first if none exists.
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [string]$AppName,
        [Parameter(Mandatory)] [hashtable]$Fields
    )
    if (-not $Context.AppOutcomes) { return }
    if (-not $Context.AppOutcomes.ContainsKey($AppName)) {
        $Context.AppOutcomes[$AppName] = @{}
    }
    $target = $Context.AppOutcomes[$AppName]
    foreach ($k in $Fields.Keys) {
        $target[$k] = $Fields[$k]
    }
}

function Get-InstallationPackage {
    param(
        [string]$Path,
        [string]$Filter
    )

    if (-not $Path -or -not (Test-Path $Path)) { return $null }

    if (Test-Path -Path $Path -PathType Container) {
        if ($Filter) {
            return Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        $priority = @('install.cmd','setup.cmd','*.msi','*.msp','*.msixbundle','*.appxbundle','*.appx','*.msix','sp*.exe','*.exe','*.cmd')
        foreach ($pat in $priority) {
            $match = Get-ChildItem -Path $Path -Filter $pat -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($match) { return $match }
        }
        return $null
    }

    if (Test-Path -Path $Path -PathType Leaf) {
        return Get-Item -Path $Path -ErrorAction SilentlyContinue
    }
    return $null
}

function Wait-ForMSI {
    param([int]$TimeoutSeconds = 900)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $mutex = $null
        if (-not [System.Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$mutex)) {
            return $true
        }
        if ($null -ne $mutex) { $mutex.Close() }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Invoke-LocalInstaller {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$InstallerPath,
        [string]$InstallerFilter = '',
        [string]$InstallerArgs = '/quiet /norestart',
        [string[]]$InstallerCandidates = @(),
        [string]$AppxPackageName = '',
        [string]$AppName = '',
        [Parameter(Mandatory)] [psobject]$Context,
        [switch]$Interactive,
        [switch]$AllowPresentReinstall,
        [psobject]$App = $null
    )

    $candidatePaths = if ($InstallerCandidates -and $InstallerCandidates.Count -gt 0) {
        $InstallerCandidates
    } else {
        @($InstallerPath)
    }

    $timeout = if ($Context.Profile.LocalTimeoutSeconds) { [int]$Context.Profile.LocalTimeoutSeconds } else { 600 }

    # Defensive: if only -App was supplied and -AppName was not, fall back
    # to the app's declared name. Engine passes both today, so this is inert
    # in the current corpus; it prevents empty app labels in log entries and
    # bucket additions if a future caller passes only -App.
    if ([string]::IsNullOrWhiteSpace($AppName) -and $App) {
        $AppName = [string]$App.AppName
    }

    # Prefer the OEM's presence definition when the manifest entry is
    # available. The phase loop already gated on Test-AppPresence; using
    # the same definition here keeps the two checks consistent so an app
    # the OEM says is absent will not be silently skipped by the generic
    # detector. Falls back to Test-ApplicationInstalled for direct callers
    # that do not pass -App.
    $preInstalled = if ($App) {
        Test-AppPresence -Context $Context -App $App
    } else {
        Test-ApplicationInstalled -AppName $AppName -AppxPackageName $AppxPackageName -Exact
    }
    $preVersion = if ($preInstalled) {
        $v = Get-ApplicationVersion -AppName $AppName -AppxPackageName $AppxPackageName
        if (-not $v -and $App -and $App.PSObject.Properties['AlternateAppNames']) {
            foreach ($alt in @($App.AlternateAppNames)) {
                if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                $v = Get-ApplicationVersion -AppName $alt
                if ($v) { break }
            }
        }
        $v
    } else { $null }

    # Track whether any candidate path yielded a package file.
    # The terminal failure reason distinguishes "no installer was found"
    # (genuinely missing) from "an installer was found and attempted but
    # the operation failed" (unsupported format, execution failure, or
    # postcondition failure). Both routes end in the same FailedApps
    # entry; only the diagnostic reason differs. The D5 AppX case lands
    # in the second category: the MSIX exists, the provisioning call ran,
    # verification failed.
    #
    # $lastAttemptedPackage and $lastAttemptedExitCode capture the final
    # attempt's diagnostics so the failure block can report them on the
    # OUTCOME line. Reset at the top of every loop iteration that finds a
    # package; the AppX branch leaves $lastAttemptedExitCode empty because
    # DISM provisioning does not produce a process exit code. See
    # PROJECT-NOTE.md §4.1.
    $anyPackageFound = $false
    $lastAttemptedPackage = ''
    $lastAttemptedExitCode = ''

    # Local installers are install-if-absent. The only caller-permitted
    # exception is the 0x8A15005E override (pinned-cert mismatch, state
    # check untrusted); those installers are idempotent re-installs.
    if ($preInstalled -and -not $AllowPresentReinstall) {
        Write-DeploymentLog -Message "Skipping local installer for '$AppName': already present." -Level INFO -AppName $AppName
        Add-UniqueValue -List $Context.AlreadyCurrent -Value $AppName
        Set-AppOutcomeFields -Context $Context -AppName $AppName -Fields @{
            TerminalReason      = 'AlreadyPresent'
            InitialMethod       = 'AlreadyInstalled'
            PreVersion          = [string]$preVersion
            PostVersion         = [string]$preVersion
            LocalInstaller      = ''
            LocalExitCode       = ''
        }
        return [pscustomobject]@{ Success = $true; ExitCode = 0; Package = $null }
    }

    foreach ($candidatePath in $candidatePaths) {
        $package = Get-InstallationPackage -Path $candidatePath -Filter $InstallerFilter
        if (-not $package) { continue }

        $anyPackageFound = $true
        $lastAttemptedPackage = $package.Name
        $lastAttemptedExitCode = ''

        $argsDisplay = if ([string]::IsNullOrWhiteSpace($InstallerArgs)) { '(none)' } else { $InstallerArgs }
        Write-DeploymentLog -Message "Installing locally from: $($package.FullName) (args: $argsDisplay)" -Level INFO -AppName $AppName

        try {
            $ext = $package.Extension.ToLower()

            if ($ext -in @('.msi','.msp')) {
                if (-not (Wait-ForMSI -TimeoutSeconds $timeout)) {
                    throw 'MSI engine mutex did not release in time.'
                }
            }

            if ($ext -in @('.appx','.appxbundle','.msix','.msixbundle')) {
                $ok = Invoke-AppxProvision -Package $package -AppName $AppName -Context $Context
                if ($ok) {
                    Clear-ApplicationCaches
                    $postInstalled = if ($App) {
                        Test-AppPresence -Context $Context -App $App
                    } else {
                        Test-ApplicationInstalled -AppName $AppName -AppxPackageName $AppxPackageName -Exact
                    }
                    if ($postInstalled) {
                        $postVersion = Get-ApplicationVersion -AppName $AppName -AppxPackageName $AppxPackageName
                        if (-not $postVersion -and $App -and $App.PSObject.Properties['AlternateAppNames']) {
                            foreach ($alt in @($App.AlternateAppNames)) {
                                if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                                $postVersion = Get-ApplicationVersion -AppName $alt
                                if ($postVersion) { break }
                            }
                        }
                        Write-LocalInstallOutcome -Context $Context -AppName $AppName `
                            -PreInstalled $preInstalled -PreVersion $preVersion `
                            -PostVersion $postVersion
                        Set-AppOutcomeFields -Context $Context -AppName $AppName -Fields @{
                            TerminalReason      = 'LocalAppxProvisioned'
                            InitialMethod       = 'Local'
                            PreVersion          = [string]$preVersion
                            PostVersion         = [string]$postVersion
                            LocalInstaller      = $package.Name
                            LocalExitCode       = '0'
                        }
                        return [pscustomobject]@{ Success = $true; ExitCode = 0; Package = $package.FullName }
                    }
                    else {
                        # Provisioning reported success but the immediately-
                        # following presence check did not see the target.
                        # This is the D5 fail-closed boundary: the provisioning
                        # verification inside Invoke-AppxProvision passed, but
                        # the app is not visible to the presence detector.
                        # Log at WARN so a future reader can see the exact
                        # point at which provisioning and presence diverged.
                        Write-DeploymentLog -Message "AppX provisioning reported success for $($package.Name), but the immediately-following presence check returned false. Proceeding to next candidate." -Level WARN -AppName $AppName
                    }
                }
                continue
            }

            $windowStyle = if ($Interactive) { 'Normal' } else { 'Hidden' }
            $startParams = @{ WindowStyle = $windowStyle }
            switch ($ext) {
                '.msi' {
                    $startParams.FilePath = 'msiexec.exe'
                    $startParams.ArgumentList = "/i `"$($package.FullName)`" $InstallerArgs".Trim()
                }
                '.msp' {
                    $startParams.FilePath = 'msiexec.exe'
                    $startParams.ArgumentList = "/p `"$($package.FullName)`" $InstallerArgs".Trim()
                }
                '.cmd' {
                    $startParams.FilePath = 'cmd.exe'
                    $startParams.ArgumentList = "/c `"$($package.FullName)`" $InstallerArgs".Trim()
                    $startParams.WorkingDirectory = $package.DirectoryName
                }
                '.exe' {
                    $startParams.FilePath = $package.FullName
                    $startParams.WorkingDirectory = $package.DirectoryName
                    if (-not [string]::IsNullOrWhiteSpace($InstallerArgs)) { $startParams.ArgumentList = $InstallerArgs }
                }
                default { throw "Unsupported file format: $ext" }
            }

            $exitCode = Invoke-ProcessWithTimeout -StartParams $startParams -TimeoutSeconds $timeout

            if ($exitCode -eq 1618) {
                Write-DeploymentLog -Message 'MSI service busy (1618); waiting and retrying.' -Level WARN -AppName $AppName
                if (Wait-ForMSI -TimeoutSeconds $timeout) {
                    $exitCode = Invoke-ProcessWithTimeout -StartParams $startParams -TimeoutSeconds $timeout
                }
            }
            $lastAttemptedExitCode = [string]$exitCode

            Clear-ApplicationCaches
            $postInstalled = if ($App) {
                Test-AppPresence -Context $Context -App $App
            } else {
                Test-ApplicationInstalled -AppName $AppName -AppxPackageName $AppxPackageName -Exact
            }
            $postVersion = if ($postInstalled) {
                $v = Get-ApplicationVersion -AppName $AppName -AppxPackageName $AppxPackageName
                if (-not $v -and $App -and $App.PSObject.Properties['AlternateAppNames']) {
                    foreach ($alt in @($App.AlternateAppNames)) {
                        if ([string]::IsNullOrWhiteSpace($alt)) { continue }
                        $v = Get-ApplicationVersion -AppName $alt
                        if ($v) { break }
                    }
                }
                $v
            } else { $null }

            if ($exitCode -in @(1641,3010)) { $Context.RebootRequired = $true }

            if ($postInstalled) {
                Write-LocalInstallOutcome -Context $Context -AppName $AppName `
                    -PreInstalled $preInstalled -PreVersion $preVersion -PostVersion $postVersion
                Set-AppOutcomeFields -Context $Context -AppName $AppName -Fields @{
                    TerminalReason      = 'LocalInstallerCompleted'
                    InitialMethod       = 'Local'
                    PreVersion          = [string]$preVersion
                    PostVersion         = [string]$postVersion
                    LocalInstaller      = $package.Name
                    LocalExitCode       = [string]$exitCode
                }
                return [pscustomobject]@{ Success = $true; ExitCode = $exitCode; Package = $package.FullName }
            }
            else {
                Write-DeploymentLog -Message "Installer did not produce application presence: $($package.FullName)" -Level WARN -AppName $AppName
            }
        }
        catch {
            Write-DeploymentLog -Message "Local install error for '$candidatePath': $($_.Exception.Message)" -Level ERROR -AppName $AppName
        }
    }

    $terminalReason = if ($anyPackageFound) { 'LocalInstallFailed' } else { 'InstallerMissing' }
    Write-DeploymentLog -Message "Local install failed for '$AppName' after trying all candidate paths (tried: $($candidatePaths -join '; '); anyPackageFound=$anyPackageFound)." -Level ERROR -AppName $AppName
    Add-UniqueValue -List $Context.FailedApps -Value $AppName
    Set-AppOutcomeFields -Context $Context -AppName $AppName -Fields @{
        TerminalReason      = $terminalReason
        InitialMethod       = 'Local'
        PreVersion          = [string]$preVersion
        PostVersion         = ''
        LocalInstaller      = $lastAttemptedPackage
        LocalExitCode       = $lastAttemptedExitCode
    }
    return [pscustomobject]@{ Success = $false; ExitCode = $null; Package = $null }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory)] [hashtable]$StartParams,
        [int]$TimeoutSeconds = 600
    )

    $proc = Start-Process @StartParams -PassThru
    if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
        return $proc.ExitCode
    }

    Write-DeploymentLog -Message "Installer did not finish after ${TimeoutSeconds}s; killing process." -Level WARN
    try { $proc.Kill() } catch {}
    # See Invoke-WingetProcess in WinGet.psm1: WaitForExit(int) returns
    # [bool] and must be assigned to $null to keep it off the pipeline.
    try { $null = $proc.WaitForExit(5000) } catch {}
    if ($proc.HasExited) { return $proc.ExitCode }
    return 1
}

function Test-NewerProvisionedWarrantsSkip {
    # Returns $true if the provisioned store already has a package whose
    # identity is exactly $PackageIdentity and whose version is >= the
    # version encoded in the offline filename. Used to skip the DISM call
    # entirely instead of relying on DISM's own "newer already present"
    # error path, which writes noise into DISM logs.
    #
    # The match is anchored on the identity boundary (identity followed by
    # an underscore), matching the same two forms the provisioned store
    # reports and that Test-AppxProvisionedPackagePresent already accepts:
    # `<Identity>_<PublisherHash>` (family name) and
    # `<Identity>_<Version>_<Arch>_...` (full name). The prior
    # implementation used an unanchored substring match against both
    # PackageName and DisplayName; that could false-match a sibling
    # package whose name merely contains this identity as a prefix of a
    # longer name.
    param(
        [Parameter(Mandatory)] [string]$PackagePath,
        [Parameter(Mandatory)] [string]$PackageIdentity
    )

    if ([string]::IsNullOrWhiteSpace($PackageIdentity)) { return $false }

    $fileName = Split-Path $PackagePath -Leaf
    if ($fileName -notmatch '_(\d+\.\d+\.\d+\.\d+)_') { return $false }
    $newVersion = $null
    try { $newVersion = [version]$Matches[1] } catch { return $false }

    $existing = Get-CachedProvisionedPackages |
        Where-Object { $_.PackageName -like "${PackageIdentity}_*" } |
        Select-Object -First 1

    if (-not $existing -or -not $existing.Version) { return $false }
    try { return ([version]$existing.Version -ge $newVersion) } catch { return $false }
}

function Get-AppxPackageIdentity {
    # Reads the <Identity> element from an AppX/MSIX package's
    # AppxManifest.xml without executing or registering the package.
    #
    # Returns a PSCustomObject with Name and Version, or $null if the
    # manifest cannot be read. The caller uses this to verify that a
    # provisioning or registration operation actually produced the
    # expected package, rather than trusting the filename or the
    # operation's own success/failure signal alone.
    #
    # Bundle formats (.msixbundle / .appxbundle) are supported: their
    # top-level manifest is AppxMetadata/AppxBundleManifest.xml and
    # carries a <Bundle><Identity> element with the bundle Name and
    # Version. DISM provisions the contained sub-packages under
    # identities conventionally named after the bundle identity, so the
    # returned Name matches what Get-AppxProvisionedPackage -Online
    # reports for the provisioned sub-packages.
    param(
        [Parameter(Mandatory)] [string]$PackagePath
    )

    if (-not (Test-Path -LiteralPath $PackagePath)) { return $null }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
        try {
            # Plain packages (.msix/.appx) carry AppxManifest.xml at the
            # ZIP root. Bundles (.msixbundle/.appxbundle) carry their
            # top-level manifest at AppxMetadata/AppxBundleManifest.xml.
            # Read either form; the identity element's Name is what the
            # caller verifies against in the provisioned store.
            $entry = $zip.Entries |
                Where-Object { $_.FullName -eq 'AppxManifest.xml' } |
                Select-Object -First 1
            $isBundle = $false
            if (-not $entry) {
                $entry = $zip.Entries |
                    Where-Object { $_.FullName -eq 'AppxMetadata/AppxBundleManifest.xml' } |
                    Select-Object -First 1
                $isBundle = $true
            }
            if (-not $entry) { return $null }

            $reader = New-Object System.IO.StreamReader($entry.Open())
            try {
                [xml]$manifest = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }

            # Bundle manifest root is <Bundle>; package manifest root is
            # <Package>. Both carry an <Identity> child with Name and
            # Version attributes.
            $rootElement = if ($isBundle) { $manifest.Bundle } else { $manifest.Package }
            if (-not $rootElement -or -not $rootElement.Identity) { return $null }
            $identity = $rootElement.Identity
            $name    = [string]$identity.Name
            $version = [string]$identity.Version
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) { return $null }

            return [pscustomobject]@{
                Name    = $name
                Version = $version
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Test-AppxProvisionedPackagePresent {
    # Verifies that a package matching the target identity and at least
    # the target version appears in Get-AppxProvisionedPackage -Online.
    # Polls for up to $WaitSeconds because DISM's provisioning state may
    # not be visible to the cmdlet immediately after a successful call.
    #
    # Returns $true only when the provisioned store confirms the target.
    # Never returns $true on a filename match alone.
    param(
        [Parameter(Mandatory)] [string]$PackageName,
        [Parameter(Mandatory)] [string]$PackageVersion,
        [int]$WaitSeconds = 15
    )

    $targetVersion = $null
    try { $targetVersion = [version]$PackageVersion } catch { return $false }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        # Anchor the identity match to the start of the reported name
        # followed by the version/arch separator. The provisioned store
        # reports PackageName as either the family name
        # (`<Identity>_<PublisherHash>`) or the full name
        # (`<Identity>_<Version>_<Arch>_...`); both start with the
        # identity followed by an underscore. Substring matching would
        # also accept unrelated packages whose family name happens to
        # contain the identity as a prefix of a longer name.
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "${PackageName}_*" })

        foreach ($p in $prov) {
            if (-not $p.Version) { continue }
            try {
                if ([version]$p.Version -ge $targetVersion) { return $true }
            } catch { }
        }

        if ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Test-AppxPackageRegistered {
    # Verifies that a package matching the target identity and at least
    # the target version is registered for the current user. Used to
    # confirm the USER-phase Add-AppxPackage path actually landed.
    param(
        [Parameter(Mandatory)] [string]$PackageName,
        [Parameter(Mandatory)] [string]$PackageVersion
    )

    $targetVersion = $null
    try { $targetVersion = [version]$PackageVersion } catch { return $false }

    $reg = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
    foreach ($p in $reg) {
        if (-not $p.Version) { continue }
        try {
            if ([version]$p.Version -ge $targetVersion) { return $true }
        } catch { }
    }

    return $false
}

function Invoke-AppxProvision {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$Package,
        [string]$AppName = '',
        [Parameter(Mandatory)] [psobject]$Context
    )

    if (-not $Context.IsSystem) {
        # USER phase: register the package for the current user. Read the
        # target identity first so we can verify the registration actually
        # landed; Add-AppxPackage returning without error is not itself
        # proof that the package is now visible to the framework's
        # detectors.
        $identity = Get-AppxPackageIdentity -PackagePath $Package.FullName
        if (-not $identity) {
            Write-DeploymentLog -Message "Could not read AppxManifest.xml from $($Package.Name); cannot verify registration." -Level ERROR -AppName $AppName
            return $false
        }

        try {
            Add-AppxPackage -Path $Package.FullName -ErrorAction Stop
        }
        catch {
            Write-DeploymentLog -Message "Add-AppxPackage failed: $($_.Exception.Message)" -Level ERROR -AppName $AppName
            return $false
        }
        finally {
            # Clear the AppDetection caches after the mutation attempt,
            # on both success and failure paths. Add-AppxPackage can
            # partially write before throwing; a stale current-user
            # snapshot would mislead the next Test-ApplicationInstalled.
            # The postcondition check below queries Get-AppxPackage
            # directly, not through the cache, so it is unaffected.
            Clear-ApplicationCaches
        }

        if (-not (Test-AppxPackageRegistered -PackageName $identity.Name -PackageVersion $identity.Version)) {
            Write-DeploymentLog -Message "Add-AppxPackage returned without error but '$($identity.Name)' is not registered at >= $($identity.Version)." -Level ERROR -AppName $AppName
            return $false
        }
        return $true
    }

    # Read the target identity from the package manifest first. It is
    # needed by both the pre-install skip check below and the
    # post-provisioning verification loop further down, and reading it
    # here lets us fail fast with a clear error before doing the
    # (potentially expensive) dependency enumeration.
    $identity = Get-AppxPackageIdentity -PackagePath $Package.FullName
    if (-not $identity) {
        Write-DeploymentLog -Message "Could not read AppxManifest.xml from $($Package.Name); cannot verify provisioning." -Level ERROR -AppName $AppName
        return $false
    }

    # Skip DISM entirely when the provisioned store already has a package
    # with this exact identity at >= the version encoded in the filename.
    # Anchored on the real package identity, not the filename basename, so
    # it cannot false-match a sibling whose name merely contains this one.
    if (Test-NewerProvisionedWarrantsSkip -PackagePath $Package.FullName -PackageIdentity $identity.Name) {
        Write-DeploymentLog -Message "Skipped: OS already has a newer version of $($Package.Name)." -Level INFO -AppName $AppName
        return $true
    }

    $depArgs = @{
        Online        = $true
        PackagePath   = $Package.FullName
        SkipLicense   = $true
        Regions       = 'All'
        ErrorAction   = 'Stop'
    }

    # Dependency search order:
    #   1. Sibling AppX-family files in the same folder as the package.
    #   2. Package-local 'Dependencies' subfolder next to the package.
    #   3. Global dependency folder from the profile (DependenciesPath),
    #      falling back to the framework default at
    #      C:\Recovery\OEM\Apps\Dependencies when the profile does not
    #      specify one. Dell and HP stage shared runtimes (VCLibs,
    #      NET.Native, UI.Xaml, etc.) in this global folder so their
    #      AppX packages that require them can be provisioned.
    $dependencyDir = Join-Path (Split-Path $Package.FullName -Parent) 'Dependencies'
    $siblingDeps = Get-ChildItem -Path $Package.DirectoryName -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $Package.FullName -and $_.Extension -match '\.(appx|appxbundle|msix|msixbundle)$' } |
        Select-Object -ExpandProperty FullName
    $packageLocalDeps = if (Test-Path $dependencyDir) {
        Get-ChildItem -Path $dependencyDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(VCLibs|NET\.Native|UI\.Xaml|DesktopAppInstaller|Advertising\.Xaml|Store\.Engagement)' -and $_.Extension -match '\.(appx|appxbundle|msix|msixbundle)$' } |
            Select-Object -ExpandProperty FullName
    } else { @() }
    $globalDependencyPath = if ($Context.Profile.DependenciesPath) {
        [string]$Context.Profile.DependenciesPath
    } else {
        'C:\Recovery\OEM\Apps\Dependencies'
    }
    $globalDeps = if (Test-Path $globalDependencyPath) {
        Get-ChildItem -Path $globalDependencyPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(VCLibs|NET\.Native|UI\.Xaml|DesktopAppInstaller|Advertising\.Xaml|Store\.Engagement)' -and $_.Extension -match '\.(appx|appxbundle|msix|msixbundle)$' } |
            Select-Object -ExpandProperty FullName
    } else { @() }

    $allDeps = @()
    if ($siblingDeps)       { $allDeps += $siblingDeps }
    if ($packageLocalDeps)  { $allDeps += $packageLocalDeps }
    if ($globalDeps)        { $allDeps += $globalDeps }
    if ($allDeps.Count -gt 0) {
        $depArgs.DependencyPackagePath = ($allDeps | Select-Object -Unique)
    }

    # $identity was read above, before the skip check; the retry loop
    # below verifies against it.
    for ($i = 1; $i -le 3; $i++) {
        $callSucceeded = $false
        $catchMessage  = $null

        try {
            Add-AppxProvisionedPackage @depArgs | Out-Null
            $callSucceeded = $true
        }
        catch {
            $catchMessage = $_.Exception.Message
        }

        # Verification postcondition. This is authoritative regardless of
        # whether the call threw. A successful call with an unprovisioned
        # target is treated the same as a failure: the operation did not
        # achieve what it claimed.
        if (Test-AppxProvisionedPackagePresent -PackageName $identity.Name -PackageVersion $identity.Version) {
            if ($catchMessage) {
                Write-DeploymentLog -Message "Provisioning returned error ('$catchMessage') but '$($identity.Name)' is now provisioned at >= $($identity.Version); treating as benign success." -Level INFO -AppName $AppName
            }
            Clear-ApplicationCaches
            return $true
        }

        if ($callSucceeded) {
            Write-DeploymentLog -Message "Add-AppxProvisionedPackage returned without error but '$($identity.Name)' is not visible in the provisioned store; retrying ($i/3)." -Level WARN -AppName $AppName
        }
        elseif ($catchMessage -match '0xc1570118') {
            # DISM's documented "package already present" code. Only benign
            # when the provisioned-state check above actually found the
            # target. It did not, so this is a genuine failure.
            Write-DeploymentLog -Message "Provisioning returned 0xc1570118 but '$($identity.Name)' is not provisioned; retrying ($i/3)." -Level WARN -AppName $AppName
        }
        else {
            # Includes 'Element not found' and any other error. Neither the
            # code nor the text alone is evidence of a benign case; only
            # the provisioned-state check is. It did not pass.
            Write-DeploymentLog -Message "DISM provisioning failed for '$($identity.Name)': $catchMessage - retrying ($i/3)." -Level WARN -AppName $AppName
        }

        if ($i -lt 3) { Start-Sleep -Seconds (3 * $i) }
    }

    # Retries exhausted. One final state check: a late-landing provision
    # is still success.
    if (Test-AppxProvisionedPackagePresent -PackageName $identity.Name -PackageVersion $identity.Version -WaitSeconds 5) {
        Clear-ApplicationCaches
        return $true
    }

    Clear-ApplicationCaches
    Write-DeploymentLog -Message "Provisioning failed after 3 attempts for '$($identity.Name)' at version $($identity.Version)." -Level ERROR -AppName $AppName
    return $false
}

function Write-LocalInstallOutcome {
    # Success-bucket recorder for the local-install path. Called only from
    # the two success sites in Invoke-LocalInstaller (AppX-provisioned and
    # EXE/MSI-completed), both of which are already inside if($postInstalled)
    # blocks. Get-DeploymentClassification therefore always receives
    # -PostInstalled $true and can return only Installed, Updated, or
    # AlreadyCurrent — the Failed case is unreachable here, and failure is
    # recorded by the terminal failure block in Invoke-LocalInstaller
    # (which also owns the diagnostic fields via Set-AppOutcomeFields).
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [string]$AppName,
        [bool]$PreInstalled,
        [string]$PreVersion,
        [string]$PostVersion
    )

    $classification = Get-DeploymentClassification `
        -PreInstalled  $PreInstalled `
        -PreVersion    $PreVersion `
        -PostInstalled $true `
        -PostVersion   $PostVersion

    switch ($classification) {
        'Installed'      { Add-UniqueValue -List $Context.InstalledApps  -Value $AppName }
        'Updated'        { Add-UniqueValue -List $Context.UpdatedApps    -Value $AppName }
        'AlreadyCurrent' { Add-UniqueValue -List $Context.AlreadyCurrent -Value $AppName }
    }
}

Export-ModuleMember -Function `
    Get-InstallationPackage, `
    Wait-ForMSI, `
    Invoke-LocalInstaller, `
    Invoke-ProcessWithTimeout, `
    Invoke-AppxProvision, `
    Test-NewerProvisionedWarrantsSkip, `
    Write-LocalInstallOutcome
