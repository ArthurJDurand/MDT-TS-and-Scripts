<#
.SYNOPSIS
    Vendor-neutral deployment context, mutex, registry markers, and
    hardware detection.
#>

# --- Hardware detection ---

$script:CachedManufacturer = $null
$script:CachedModel        = $null

function Get-SystemManufacturer {
    if ($script:CachedManufacturer) { return $script:CachedManufacturer }

    $invalid = @(
        'Default string','Not Applicable','Not Available',
        'System Manufacturer','To be filled by O.E.M.'
    )

    $values = @(
        (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Manufacturer
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Vendor
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notin $invalid }

    if (-not $values) {
        $script:CachedManufacturer = 'Unknown'
        return 'Unknown'
    }

    $script:CachedManufacturer = $values |
        Group-Object |
        Sort-Object @{ Expression = { $_.Count }; Descending = $true },
                    @{ Expression = { $_.Name };  Descending = $false } |
        Select-Object -First 1 -ExpandProperty Name

    return $script:CachedManufacturer
}

function Get-SystemModel {
    if ($script:CachedModel) { return $script:CachedModel }

    $invalid = @(
        'Default string','Not Applicable','Not Available',
        'System Product Name','System Version',
        'To be filled by O.E.M.','Type1ProductConfigId'
    )

    $values = @(
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Name
        (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).Version
    ) | ForEach-Object { if ($_ -ne $null) { $_.ToString().Trim() } else { $null } } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Where-Object { $_ -notin $invalid }

    if (-not $values -or $values.Count -eq 0) { return $null }

    $script:CachedModel = $values |
        Sort-Object @{ Expression = { $_.Length }; Descending = $true },
                    @{ Expression = { $_ };       Descending = $false } |
        Select-Object -First 1

    return $script:CachedModel
}

function Get-IntelGenerationFromName {
    # Parses an Intel CPU name string to a generation number, or $null
    # when no known pattern matches. Shared by every OEM module that
    # gates app eligibility on CPU generation; centralizing the parser
    # means a fix or a new pattern reaches every OEM in one edit.
    #
    # Recognized patterns, in order:
    #   1. "Nth Gen" — explicit generation string, e.g. "11th Gen".
    #   2. i3/i5/i7/i9 model numbers — first digit of the model number
    #      is the generation, except for 5-digit models starting with 1
    #      where the first two digits are the generation ("10750" -> 10).
    #   3. Core Ultra N — 13 + first digit of the SKU (Ultra 7 155H ->
    #      14).
    #   4. Non-Ultra Core N — Raptor Lake Refresh, generation 14. Intel
    #      has not shipped a newer non-Ultra Core three-digit part;
    #      newer mainstream parts use the Core Ultra branding handled
    #      above.
    #   5. N-series / U-series — generation 12. Does NOT match Intel's
    #      two-digit N95/N97 parts (Alder Lake-N); see PROJECT-NOTE.md
    #      §4.1 for the tracked gap.
    param([string]$CPUName)
    if (-not $CPUName) { return $null }
    $clean = $CPUName -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
    $clean = ($clean -replace '\s+', ' ').Trim()
    if ($clean -notmatch '(?i)\bIntel\b') { return $null }
    if ($clean -match '(?i)\b(?<gen>\d+)(?:st|nd|rd|th)?\s+Gen\b') { return [int]$Matches['gen'] }
    if ($clean -match '(?i)\bi[3579][- ](?<model>\d{4,5})[A-Z0-9]*\b') {
        $m = $Matches['model']
        if ($m.StartsWith('1')) { return [int]$m.Substring(0,2) }
        return [int]$m.Substring(0,1)
    }
    if ($clean -match '(?i)\bCore\s+Ultra\s+[3579]\s+(?<sku>\d{3})[A-Z]*\b') {
        return 13 + [int]$Matches['sku'].Substring(0,1)
    }
    if ($clean -match '(?i)\bCore\s+[3579]\s+(?<sku>\d{3})[A-Z]*\b') { return 14 }
    if ($clean -match '(?i)\b(?:N\d{3}|U\d{3}E?)\b') { return 12 }
    return $null
}

function Get-AmdGenerationFromName {
    # Parses an AMD CPU name string to a generation number, or $null when
    # no known pattern matches. Shared by every OEM module that gates
    # app eligibility on CPU generation.
    #
    # Recognized patterns, in order:
    #   1. Ryzen AI 3/5/7/9 — generation 30, a symbolic token
    #      distinguished from older Ryzen parts by the "AI" branding.
    #   2. Ryzen 3/5/7/9 with a 4-digit model number — first digit of
    #      the model (Ryzen 7 5800X -> 5).
    param([string]$CPUName)
    if (-not $CPUName) { return $null }
    $name = $CPUName -replace '\(R\)|\(TM\)|\(C\)|\bProcessor\b|\bCPU\b', ''
    $name = ($name -replace '\s+', ' ').Trim()
    if ($name -notmatch '(?i)\bAMD\b') { return $null }
    if ($name -match '(?i)\bRyzen\s+AI\s+[3579]\s+(?:HX\s+)?(?<sku>\d{3})[A-Z]*\b') { return 30 }
    if ($name -match '(?i)\bRyzen\s+[3579]\s+(?:PRO\s+)?(?<model>\d{4})[A-Z0-9]*\b') {
        return [int]$Matches['model'].Substring(0,1)
    }
    return $null
}

# --- Context ---

function New-DeploymentContext {
    param(
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [psobject]$Manifest
    )

    return [pscustomobject]@{
        OEMName          = $Profile.Name
        Profile          = $Profile
        Manifest         = $Manifest
        ScriptPath       = $null

        IsSystem         = $false
        IsUser           = $false

        MarkerPath       = $Profile.MarkerRegistryPath
        StageName        = if ($Profile.StageName)  { $Profile.StageName }  else { 'DeploymentStage' }

        # Set by the phase functions after GetSystemFamilyFromProfile runs.
        # Health check reads it without re-invoking the profile hook.
        SystemFamily     = $null

        # Per-phase cache of service readiness. $null means "not yet checked".
        ServiceReady     = $null

        # Populated by Initialize-WinGetSession during USER phase.
        # Carries BypassEnabled / BypassBaseline. $null in SYSTEM phase.
        WingetSession    = $null

        InstalledApps    = [System.Collections.Generic.List[string]]::new()
        UpdatedApps      = [System.Collections.Generic.List[string]]::new()
        AlreadyCurrent   = [System.Collections.Generic.List[string]]::new()
        SkippedApps      = [System.Collections.Generic.List[string]]::new()
        DeferredApps     = [System.Collections.Generic.List[string]]::new()
        FailedApps       = [System.Collections.Generic.List[string]]::new()

        # Per-app reason scratch pad. Installer paths populate this with
        # fields describing why the app reached its terminal classification.
        # The phase loops read it once per app iteration and emit a single
        # structured OUTCOME line to the per-app log via Write-AppOutcome.
        # Not persisted; per-run only. Keys are app names; values are
        # hashtables of reason fields.
        #
        # Backed by an ordinal case-sensitive Dictionary rather than a plain
        # hashtable, to match the case-sensitive semantics of the bucket
        # lists (List<string>.Contains). Two manifest entries differing
        # only by case must not collide here while remaining distinct in
        # the buckets.
        AppOutcomes      = [System.Collections.Generic.Dictionary[string,hashtable]]::new([System.StringComparer]::Ordinal)

        RebootRequired   = $false
    }
}

# --- Mutex ---

function New-DeploymentMutex {
    param([string]$Name = 'Global\OEMFramework')

    $mutex = [System.Threading.Mutex]::new($false, $Name)
    try {
        $owned = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        # The throw signals the previous owner died. .NET has already
        # transferred ownership of the underlying OS mutex to this thread;
        # the $mutex reference is still valid, so ReleaseMutex will succeed.
        $owned = $true
    }
    return [pscustomobject]@{ Name = $Name; Mutex = $mutex; Owned = $owned }
}

function Release-DeploymentMutex {
    param(
        [Parameter(Mandatory)] [System.Threading.Mutex]$Mutex,
        [bool]$Owned = $true
    )
    if ($Owned -and $Mutex) { try { $Mutex.ReleaseMutex() } catch {} }
    if ($Mutex)              { try { $Mutex.Dispose() }      catch {} }
}

# --- Stage markers ---

function Get-DeploymentStage {
    param(
        [Parameter(Mandatory)] [string]$MarkerPath,
        [string]$ValueName = 'DeploymentStage'
    )

    if (-not (Test-Path $MarkerPath)) { return 'NONE' }
    $prop = Get-ItemProperty -Path $MarkerPath -ErrorAction SilentlyContinue
    if (-not $prop) { return 'NONE' }
    $value = $prop.$ValueName
    if (-not $value) { return 'NONE' }
    return [string]$value
}

function Set-DeploymentStage {
    param(
        [Parameter(Mandatory)] [string]$MarkerPath,
        [Parameter(Mandatory)] [string]$Stage,
        [string]$ValueName = 'DeploymentStage'
    )

    # Route through Set-RegistryValueSilent so marker writes use reg.exe,
    # matching the framework-wide registry-write discipline. That helper
    # creates the key if missing and performs the read-back verification
    # itself, so no separate Test-Path/New-Item step is needed here.
    return [bool](Set-RegistryValueSilent -Path $MarkerPath -Name $ValueName -Value $Stage -Type 'String')
}

# --- Phase detection ---

function Get-CurrentExecutionPhase {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -eq 'S-1-5-18') { return 'SYSTEM' }
    return 'USER'
}

# --- List helper ---

function Add-UniqueValue {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]]$List,
        [Parameter(Mandatory)] [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $null = $List.Add($Value)
    }
}

# --- Profile hook invocation ---

function Invoke-ProfileHook {
    param(
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [string]$HookName,
        [hashtable]$Parameters = @{}
    )
    $hook = $Profile.$HookName
    if (-not $hook) { return $null }
    return & $hook @Parameters
}

function ConvertTo-ScalarBool {
    # Coerces a hook's pipeline output to a scalar Boolean.
    #
    # A hook that emits pipeline output before returning $false produces an
    # array like @('diagnostic', $false). The caller's intent — the value of
    # `return` — is the *last* item on the pipeline, not the first. Taking
    # [-1] is correct; taking [0] would coerce 'diagnostic' to $true and
    # silently invert the hook's answer.
    param([object]$Result)

    if ($null -eq $Result) { return $false }

    $items = @($Result)
    if ($items.Count -eq 0) { return $false }

    $value = $items[-1]
    if ($value -is [bool]) { return $value }
    return [bool]$value
}

function Invoke-ProfileBoolHook {
    param(
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [string]$HookName,
        [hashtable]$Parameters = @{}
    )
    $hook = $Profile.$HookName
    if (-not $hook) { return $true }   # missing = pass

    return ConvertTo-ScalarBool (& $hook @Parameters)
}

function Get-DeploymentClassification {
    # Pure classification helper shared by WinGet.psm1 and LocalInstall.psm1.
    # Given pre/post presence and version state, returns one of:
    #   Installed, Updated, AlreadyCurrent, Failed
    # Centralized so the two install paths cannot drift in their terminal
    # classification rules.
    param(
        [bool]   $PreInstalled,
        [string] $PreVersion,
        [bool]   $PostInstalled,
        [string] $PostVersion
    )

    if (-not $PostInstalled) { return 'Failed' }
    if (-not $PreInstalled)  { return 'Installed' }

    $preV  = $null
    $postV = $null
    if ($PreVersion)  { try { $preV  = [version]$PreVersion }  catch {} }
    if ($PostVersion) { try { $postV = [version]$PostVersion } catch {} }

    if ($preV -and $postV -and $postV -gt $preV) { return 'Updated' }
    return 'AlreadyCurrent'
}

Export-ModuleMember -Function `
    Get-SystemManufacturer, `
    Get-SystemModel, `
    Get-IntelGenerationFromName, `
    Get-AmdGenerationFromName, `
    New-DeploymentContext, `
    New-DeploymentMutex, `
    Release-DeploymentMutex, `
    Get-DeploymentStage, `
    Set-DeploymentStage, `
    Get-CurrentExecutionPhase, `
    Add-UniqueValue, `
    Invoke-ProfileHook, `
    Invoke-ProfileBoolHook, `
    ConvertTo-ScalarBool, `
    Get-DeploymentClassification
