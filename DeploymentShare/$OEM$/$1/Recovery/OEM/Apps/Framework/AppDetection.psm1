<#
.SYNOPSIS
    Vendor-neutral application detection with cache management.

.DESCRIPTION
    Five caches (Uninstall, Package, AppX, Provisioned, UserAppx) are used
    to reduce repeated enumeration cost. Each has an init flag so an empty
    result is not re-queried on every call. The UserAppx cache backs the
    current-user AppX fallback in Test-ApplicationInstalled.

    The safe AppX/provisioned helpers return $null when all retries fail,
    distinct from @() on a genuine empty result. Cached getters only mark
    the cache initialized on non-null, so a transient failure does not
    disable AppX detection for the rest of the process lifetime.
#>

$script:UninstallCache            = $null
$script:ProvisionedCache          = $null
$script:PackageCache              = $null
$script:AppxCache                 = $null
$script:UserAppxCache             = $null
$script:UninstallCacheInitialized = $false
$script:ProvisionedCacheInitialized = $false
$script:PackageCacheInitialized   = $false
$script:AppxCacheInitialized      = $false
$script:UserAppxCacheInitialized  = $false

function Clear-ApplicationCaches {
    $script:UninstallCache            = $null
    $script:ProvisionedCache          = $null
    $script:PackageCache              = $null
    $script:AppxCache                 = $null
    $script:UserAppxCache             = $null
    $script:UninstallCacheInitialized = $false
    $script:ProvisionedCacheInitialized = $false
    $script:PackageCacheInitialized   = $false
    $script:AppxCacheInitialized      = $false
    $script:UserAppxCacheInitialized  = $false
}

function Get-AppxProvisionedPackageSafe {
    $maxAttempts = 3
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            return @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        }
        catch {
            if ($_.Exception.Message -match 'Another operation|0x80073D60|0x80070020') {
                Write-Host "  AppX service busy, retrying ($i/$maxAttempts)..."
                Start-Sleep -Seconds (5 * $i)
            }
            else {
                Write-DeploymentLog -Message "Unexpected AppX provisioned query failure: $($_.Exception.Message)" -Level WARN
                return $null
            }
        }
    }
    Write-Host '  WARNING: Could not retrieve provisioned packages after retries.' -ForegroundColor Yellow
    return $null
}

function Get-CachedProvisionedPackages {
    if (-not $script:ProvisionedCacheInitialized) {
        $result = Get-AppxProvisionedPackageSafe
        if ($null -ne $result) {
            $script:ProvisionedCache = $result
            $script:ProvisionedCacheInitialized = $true
            return $script:ProvisionedCache
        }
        return @()
    }
    return $script:ProvisionedCache
}

function Get-AppxPackageSafe {
    param([switch]$CurrentUser)
    $maxAttempts = 3
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            if ($CurrentUser) {
                return @(Get-AppxPackage -ErrorAction Stop)
            }
            return @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        }
        catch {
            if ($_.Exception.Message -match 'Another operation|0x80073D60|0x80070020') {
                Write-Host "  AppX service busy, retrying ($i/$maxAttempts)..."
                Start-Sleep -Seconds (5 * $i)
            }
            else {
                Write-DeploymentLog -Message "Unexpected AppX query failure: $($_.Exception.Message)" -Level WARN
                return $null
            }
        }
    }
    Write-Host '  WARNING: Could not retrieve AppX packages after retries.' -ForegroundColor Yellow
    return $null
}

function Get-UninstallCache {
    if (-not $script:UninstallCacheInitialized) {
        $script:UninstallCache = @(Get-ItemProperty `
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
            -ErrorAction SilentlyContinue)
        $script:UninstallCacheInitialized = $true
    }
    return $script:UninstallCache
}

function Get-PackageCache {
    if (-not $script:PackageCacheInitialized) {
        $script:PackageCache = @(Get-Package -ErrorAction SilentlyContinue)
        $script:PackageCacheInitialized = $true
    }
    return $script:PackageCache
}

function Get-AppxCache {
    if (-not $script:AppxCacheInitialized) {
        $result = Get-AppxPackageSafe
        if ($null -ne $result) {
            $script:AppxCache = $result
            $script:AppxCacheInitialized = $true
            return $script:AppxCache
        }
        return @()
    }
    return $script:AppxCache
}

function Get-UserAppxCache {
    # Current-user AppX enumeration cache. Mirrors Get-AppxCache's
    # null-vs-empty contract: returns @() on query failure without
    # setting the initialized flag, so the next caller retries. Only
    # Clear-ApplicationCaches resets it. Snapshot semantics — the
    # framework cannot see installs performed by Dell AutoUpdate, the
    # msstore, firstrun.ps1, or pre.ps1, so this is a snapshot, not a
    # live view, exactly like the other four caches.
    if (-not $script:UserAppxCacheInitialized) {
        $result = Get-AppxPackageSafe -CurrentUser
        if ($null -ne $result) {
            $script:UserAppxCache = $result
            $script:UserAppxCacheInitialized = $true
            return $script:UserAppxCache
        }
        return @()
    }
    return $script:UserAppxCache
}

function Test-ApplicationInstalled {
    param(
        [string]$AppName = '',
        [string]$AppxPackageName = '',
        [switch]$Exact
    )

    if ([string]::IsNullOrWhiteSpace($AppName) -and [string]::IsNullOrWhiteSpace($AppxPackageName)) {
        return $false
    }

    if ($AppName) {
        $cache = Get-UninstallCache
        if ($cache | Where-Object { $_.DisplayName -eq $AppName }) { return $true }

        $pkgs = Get-PackageCache
        if ($pkgs | Where-Object { $_.Name -eq $AppName }) { return $true }

        $appx = Get-AppxCache | Where-Object {
            $_.Name -eq $AppName -or $_.PackageFamilyName -eq $AppName -or $_.PackageFullName -eq $AppName
        }
        if ($appx) { return $true }

        if ($Exact) {
            # Exact mode still permits normal version/architecture suffixes
            # used by desktop application DisplayName registrations.
            # Example:
            #   Microsoft Windows Desktop Runtime - 8
            #   Microsoft Windows Desktop Runtime - 8.0.25 (x64)
            #
            # Do not fall back to unrestricted substring matching here.
            $escapedName = [regex]::Escape($AppName)
            $versionedNamePattern = "^$escapedName(?:\s+v?\d+(?:\.\d+)*(?:\s.*)?|\.\d+(?:\.\d+)*(?:\s.*)?)$"

            if ($cache | Where-Object {
                $_.DisplayName -and $_.DisplayName -match $versionedNamePattern
            }) {
                return $true
            }

            if ($pkgs | Where-Object {
                $_.Name -and $_.Name -match $versionedNamePattern
            }) {
                return $true
            }
        }
    }

    if ($AppxPackageName) {
        # Anchor both identity matches to the underscore boundary. An
        # unanchored "$AppxPackageName*" also matches a sibling identity
        # whose name begins with the requested one (e.g. "Foo.Bar" vs
        # "Foo.BarExtensions"). PackageFamilyName and PackageFullName are
        # both "<Identity>_<suffix>", so the anchored form accepts the
        # legitimate version/arch/hash suffixes and rejects unrelated
        # siblings. Mirrors the identity rule already used by
        # Test-AppxProvisionedPackagePresent and Resolve-AumidForPin.
        $appx = Get-AppxCache | Where-Object {
            $_.Name -eq $AppxPackageName -or
            $_.PackageFamilyName -eq $AppxPackageName -or
            $_.PackageFullName -like "${AppxPackageName}_*"
        }
        if ($appx) { return $true }

        # Provisioned-store match: same identity-boundary rule, gated on
        # the caller's -Exact intent. The non-exact branch retains the
        # original substring match for compatibility callers.
        $provPattern = if ($Exact) { "${AppxPackageName}_*" } else { "*$AppxPackageName*" }
        if (Get-CachedProvisionedPackages | Where-Object { $_.PackageName -like $provPattern }) {
            return $true
        }
    }

    if ($AppName -or $AppxPackageName) {
        # Same identity-boundary rule as the AppxCache and provisioned-store
        # branches above. The current-user branch is reached when the
        # elevated -AllUsers view missed the package; an unanchored
        # "$AppxPackageName*" here would false-positive on a sibling
        # identity exactly as it would in the branches above.
        $userAppx = Get-UserAppxCache | Where-Object {
            ($AppName -and ($_.Name -eq $AppName -or $_.PackageFamilyName -eq $AppName -or $_.PackageFullName -eq $AppName)) -or
            ($AppxPackageName -and ($_.Name -eq $AppxPackageName -or $_.PackageFamilyName -eq $AppxPackageName -or $_.PackageFullName -like "${AppxPackageName}_*"))
        }
        if ($userAppx) { return $true }
    }

    if (-not $Exact -and $AppName) {
        $search = $AppName.ToLower()
        if ($cache | Where-Object { $_.DisplayName -and $_.DisplayName.ToLower().Contains($search) }) { return $true }
        if ($pkgs  | Where-Object { $_.Name -and $_.Name.ToLower().Contains($search) }) { return $true }
        $appx = Get-AppxCache | Where-Object {
            ($_.Name -and $_.Name.ToLower().Contains($search)) -or
            ($_.PackageFamilyName -and $_.PackageFamilyName.ToLower().Contains($search))
        }
        if ($appx) { return $true }
    }

    return $false
}

function Get-ApplicationVersion {
    param(
        [string]$AppName = '',
        [string]$AppxPackageName = ''
    )

    if ($AppxPackageName) {
        # Use the same AppX cache as Test-ApplicationInstalled, which queries
        # Get-AppxPackage -AllUsers. Querying the current user directly
        # produces a null version when the package is present but not
        # registered for the caller — the classifier would then fall through
        # to AlreadyCurrent without evidence.
        # Same identity-boundary rule as the provisioned-store lookup below
        # and as Test-ApplicationInstalled. An unanchored "$AppxPackageName*"
        # would resolve a sibling identity's version and feed it into the
        # Installed/Updated/AlreadyCurrent classification.
        $pkg = Get-AppxCache |
            Where-Object {
                $_.Name -eq $AppxPackageName -or
                $_.PackageFamilyName -eq $AppxPackageName -or
                $_.PackageFullName -like "${AppxPackageName}_*"
            } |
            Sort-Object @{
                Expression = { if ($_.Version) { try { [version]$_.Version } catch { [version]'0.0' } } else { [version]'0.0' } }
                Descending = $true
            } | Select-Object -First 1
        if ($pkg -and $pkg.Version) { return $pkg.Version.ToString() }

        # Same identity-boundary rule as Test-ApplicationInstalled's
        # provisioned branch. The value returned here feeds version
        # comparison (PreVersion / PostVersion) for terminal
        # classification, so picking a sibling package's version would
        # produce a misclassified Installed/Updated/AlreadyCurrent.
        $prov = Get-CachedProvisionedPackages |
            Where-Object { $_.PackageName -like "${AppxPackageName}_*" } |
            Sort-Object @{
                Expression = { if ($_.Version) { try { [version]$_.Version } catch { [version]'0.0' } } else { [version]'0.0' } }
                Descending = $true
            } | Select-Object -First 1
        if ($prov -and $prov.Version) { return $prov.Version.ToString() }
    }

    if ($AppName) {
        $uninstall = Get-UninstallCache |
            Where-Object { $_.DisplayName -eq $AppName } |
            Select-Object -First 1

        if (-not $uninstall) {
            $escapedName = [regex]::Escape($AppName)
            $versionedNamePattern = "^$escapedName(?:\s+v?\d+(?:\.\d+)*(?:\s.*)?|\.\d+(?:\.\d+)*(?:\s.*)?)$"

            $uninstall = Get-UninstallCache |
                Where-Object {
                    $_.DisplayName -and $_.DisplayName -match $versionedNamePattern
                } |
                Select-Object -First 1
        }

        if ($uninstall -and $uninstall.DisplayVersion) {
            return $uninstall.DisplayVersion
        }

        $pkg = Get-PackageCache |
            Where-Object { $_.Name -eq $AppName } |
            Select-Object -First 1

        if (-not $pkg) {
            $escapedName = [regex]::Escape($AppName)
            $versionedNamePattern = "^$escapedName(?:\s+v?\d+(?:\.\d+)*(?:\s.*)?|\.\d+(?:\.\d+)*(?:\s.*)?)$"

            $pkg = Get-PackageCache |
                Where-Object {
                    $_.Name -and $_.Name -match $versionedNamePattern
                } |
                Select-Object -First 1
        }

        if ($pkg -and $pkg.Version) {
            return $pkg.Version.ToString()
        }
    }

    return $null
}

Export-ModuleMember -Function `
    Clear-ApplicationCaches, `
    Get-AppxProvisionedPackageSafe, `
    Get-CachedProvisionedPackages, `
    Get-AppxPackageSafe, `
    Get-UninstallCache, `
    Get-PackageCache, `
    Get-AppxCache, `
    Get-UserAppxCache, `
    Test-ApplicationInstalled, `
    Get-ApplicationVersion
