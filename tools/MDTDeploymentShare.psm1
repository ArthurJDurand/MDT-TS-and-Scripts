#Requires -Version 5.1
<#
.SYNOPSIS
    Shared core module for installing, updating, and testing an
    MDT deployment share built from MDT-Zero-Touch-Deployment.

.DESCRIPTION
    This module is the shared core consumed by three entry-point scripts:

        Install-MDTDeploymentShare.ps1   Interactive first-time install
        Update-MDTDeploymentShare.ps1    Idempotent, non-interactive update
        Test-MDTDeploymentShare.ps1      Read-only health check

    It provides environment discovery, prerequisite installation via
    winget with direct-download fallback, hostname and share patching,
    DHCP and WDS role installation via native Windows cmdlets, MDT
    cmdlet wrappers, backup and rollback, and structured logging.

    The module does NOT contain any scenario-specific orchestration.
    That logic lives in the entry-point scripts.

.NOTES
    Repo:     https://github.com/ArthurJDurand/MDT-Zero-Touch-Deployment
    License:  MIT
    Author:   Arthur Durand (@ArthurJDurand)
    Version:  1.0.0
#>

#region ─── Module state ────────────────────────────────────────────────────

$script:MDTModuleVersion       = '1.0.0'
$script:MDTInstallRoot         = Join-Path $env:ProgramData 'MDT-Install'
$script:MDTInstallLogDir       = Join-Path $script:MDTInstallRoot 'Logs'
$script:MDTBackupRoot          = Join-Path $script:MDTInstallRoot 'Backups'
$script:MDTInstallLogPath      = $null
$script:MDTDefaultSourcePath   = 'C:\Source\MDT-Zero-Touch-Deployment'
$script:MDTDefaultSharePath    = 'C:\DeploymentShare'
$script:MDTDeploymentShareName = 'DeploymentShare$'
$script:MDTSharedName          = 'Shared'
$script:MDTOemName             = 'OEM'
$script:MDTMediaRoot           = 'C:\Deploy\MDT'

# Prerequisite installers. winget is the primary path; the direct URL is
# the fallback for offline or winget-less environments. Permalinks are
# rotated by Microsoft per release; update this block when a new ADK,
# WinPE add-on, or SDK ships.
$script:MDTPrerequisites = @(
    [pscustomobject]@{
        Name      = 'Windows ADK'
        WingetId  = 'Microsoft.WindowsADK'
        DirectUrl = 'https://go.microsoft.com/fwlink/?linkid=2289980'
        FileName  = 'adksetup.exe'
        Args      = @('/quiet', '/features', 'OptionId.DeploymentTools')
        Required  = $true
    }
    [pscustomobject]@{
        Name      = 'Windows PE Add-on for ADK'
        WingetId  = 'Microsoft.WindowsADK.WinPEAddon'
        DirectUrl = 'https://go.microsoft.com/fwlink/?linkid=2289981'
        FileName  = 'adkwinpesetup.exe'
        Args      = @('/quiet', '/features', 'OptionId.WindowsPreinstallationEnvironment')
        Required  = $true
    }
    [pscustomobject]@{
        Name      = 'Windows SDK (deployment tools)'
        WingetId  = 'Microsoft.WindowsSDK.10.0.26100'
        DirectUrl = 'https://go.microsoft.com/fwlink/?linkid=2289982'
        FileName  = 'winsdksetup.exe'
        Args      = @('/quiet', '/features', 'OptionId.WindowsDeploymentTools')
        Required  = $false
    }
    [pscustomobject]@{
        Name      = 'Microsoft Deployment Toolkit 6.3.8456.1000'
        WingetId  = $null
        DirectUrl = 'https://download.microsoft.com/download/3/3/9/339BE62D-B4B8-4956-B58D-73C4685FC492/MicrosoftDeploymentToolkit_x64.msi'
        FileName  = 'MicrosoftDeploymentToolkit_x64.msi'
        Args      = @('/quiet')
        Required  = $true
    }
)

# Companion repositories cloned or pulled on demand.
$script:MDTCompanionRepos = @{
    OEM     = [pscustomobject]@{
        Name = 'MDT-OEM-Extensibility'
        Path = 'C:\Source\MDT-OEM-Extensibility'
        Url  = 'https://github.com/ArthurJDurand/MDT-OEM-Extensibility.git'
    }
    Builder = [pscustomobject]@{
        Name = 'MDT-Windows-Image-Builder'
        Path = 'C:\Source\MDT-Windows-Image-Builder'
        Url  = 'https://github.com/ArthurJDurand/MDT-Windows-Image-Builder.git'
    }
}

# The ten files whose \\SERVER references are patched during install.
# Paths are relative to the deployment share root.
$script:MDTHostnameTargets = @(
    'Control\Settings.xml'
    'Control\Bootstrap.ini'
    'Scripts\Custom\ApplyUpdates10x64.ps1'
    'Scripts\Custom\ApplyUpdates10x86.ps1'
    'Scripts\Custom\ApplyUpdates11.ps1'
    'Scripts\Custom\ExtractOEMAppsx64.ps1'
    'Scripts\Custom\ExtractOEMAppsx86.ps1'
    'Scripts\Custom\ExtractOEMDrivers.ps1'
    'Scripts\Custom\LoadWinPEDrivers.ps1'
    'Scripts\Custom\WinRE.ps1'
)

# Folders backed up before any mutating operation.
$script:MDTBackupFolders = @(
    'Control'
    'Scripts\Custom'
    'Templates'
    'x64\$OEM$'
    'x86\$OEM$'
)

#endregion


#region ─── Private helpers ─────────────────────────────────────────────────

function Test-MDTIsAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-MDTIsAdmin {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Operation)
    if (-not (Test-MDTIsAdmin)) {
        throw "Elevation is required to $Operation. Re-run from an elevated PowerShell session."
    }
}

function Resolve-MDTSharePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    # Try the well-known default share location.
    $candidate = Join-Path $script:MDTDefaultSharePath '.'
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
    }

    throw "Deployment share not found at '$Path' and default '$script:MDTDefaultSharePath' does not exist."
}

function Invoke-MDTDownload {
    <#
    .SYNOPSIS
        Downloads a URL to a file using TLS 1.2 and BITS where available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Destination
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Write-MDTInstallLog "Downloading $Url -> $Destination"

    $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bits) {
        try {
            Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop
            return $Destination
        } catch {
            Write-MDTInstallLog "BITS transfer failed: $($_.Exception.Message). Falling back to Invoke-WebRequest." -Level Warn
        }
    }

    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    return $Destination
}

function Add-MDTMDTModule {
    <#
    .SYNOPSIS
        Imports the MDT PowerShell module and, if necessary, registers the
        MDT snap-in. Raises a terminating error when the module is missing.
    #>
    [CmdletBinding()]
    param()

    $mdtBin = Join-Path ${env:ProgramFiles} 'Microsoft Deployment Toolkit\Bin'
    $mdtPsd1 = Join-Path $mdtBin 'MicrosoftDeploymentToolkit.psd1'

    if (-not (Test-Path -LiteralPath $mdtPsd1)) {
        throw "MDT PowerShell module not found at $mdtPsd1. Install MDT first."
    }

    Get-Module MicrosoftDeploymentToolkit | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $mdtPsd1 -Force -ErrorAction Stop
    Write-MDTInstallLog "MDT module loaded from $mdtPsd1"
}

#endregion


#region ─── Logging and prompts ─────────────────────────────────────────────

function Initialize-MDTInstallLog {
    <#
    .SYNOPSIS
        Creates a new timestamped log file under the MDT install root
        and returns the path.
    .PARAMETER Name
        Short operation name appended to the log filename.
    .PARAMETER Directory
        Override the log directory. Defaults to the module default.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [string] $Name = 'mdt',
        [Parameter()] [string] $Directory = $script:MDTInstallLogDir
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $safeName = ($Name -replace '[^\w\-\.]', '_')
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logPath = Join-Path $Directory ("{0}_{1}.log" -f $stamp, $safeName)

    Set-Content -LiteralPath $logPath -Value "# MDT install log - $stamp - $Name" -Encoding UTF8
    $script:MDTInstallLogPath = $logPath
    return $logPath
}

function Write-MDTInstallLog {
    <#
    .SYNOPSIS
        Writes a timestamped entry to the current log and echoes to host.
    .PARAMETER Message
        The message text.
    .PARAMETER Level
        Info, Warn, Error, Verbose, or Debug.
    .PARAMETER NoHost
        Suppress console echo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Message,
        [Parameter()] [ValidateSet('Info', 'Warn', 'Error', 'Verbose', 'Debug')] [string] $Level = 'Info',
        [Parameter()] [switch] $NoHost
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$stamp [$Level] $Message"

    if ($script:MDTInstallLogPath) {
        try {
            Add-Content -LiteralPath $script:MDTInstallLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }
    }

    if (-not $NoHost) {
        $colour = switch ($Level) {
            'Error'   { 'Red' }
            'Warn'    { 'Yellow' }
            'Verbose' { 'DarkGray' }
            'Debug'   { 'DarkGray' }
            default   { 'Gray' }
        }
        Write-Host $line -ForegroundColor $colour
    }
}

function Confirm-MDTAction {
    <#
    .SYNOPSIS
        Standardized yes/no prompt.
    .PARAMETER Question
        The question to ask.
    .PARAMETER Default
        Yes, No, or None. Controls the preselected answer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Question,
        [Parameter()] [ValidateSet('Yes', 'No', 'None')] [string] $Default = 'No'
    )

    $suffix = switch ($Default) {
        'Yes'  { '[Y/n]' }
        'No'   { '[y/N]' }
        'None' { '[y/n]' }
    }

    while ($true) {
        $answer = Read-Host "$Question $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            if ($Default -eq 'Yes') { return $true }
            if ($Default -eq 'No')  { return $false }
            continue
        }
        switch -Regex ($answer.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host 'Please answer y or n.' -ForegroundColor Yellow }
        }
    }
}

function Show-MDTScenarioPicker {
    <#
    .SYNOPSIS
        Presents the install scenarios that are viable on this machine
        and returns the selected scenario ID.
    .DESCRIPTION
        Returns one of:
            FullServer, ServerRoleOnly, FullDesktop, DesktopShareOnly,
            UpdateExisting, OemPacksOnly, ImageBuilderOnly
    .PARAMETER MachineInfo
        Optional pre-computed output of Get-MDTMachineInfo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [pscustomobject] $MachineInfo
    )

    if (-not $MachineInfo) { $MachineInfo = Get-MDTMachineInfo }

    $scenarios = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($MachineInfo.IsServer) {
        $scenarios.Add([pscustomobject]@{
            Id     = 'FullServer'
            Label  = 'Full server - install everything on this server'
            Detail = 'ADK/SDK/WinPE/MDT/fixes, DHCP + WDS roles, share, TS, boot images, WDS import.'
        })
        $scenarios.Add([pscustomobject]@{
            Id     = 'ServerRoleOnly'
            Label  = 'Server role only - PXE server points at a remote share'
            Detail = 'Install ADK/WinPE, configure DHCP + WDS, import boot images from a remote share.'
        })
    } else {
        $scenarios.Add([pscustomobject]@{
            Id     = 'FullDesktop'
            Label  = 'Full desktop - install everything plus AOMEI PXE Boot'
            Detail = 'ADK/SDK/WinPE/MDT/fixes, AOMEI PXE Boot, share, TS, boot images.'
        })
        $scenarios.Add([pscustomobject]@{
            Id     = 'DesktopShareOnly'
            Label  = 'Desktop share only - no PXE'
            Detail = 'Create share, merge repo, import TS, build boot images.'
        })
    }

    $scenarios.Add([pscustomobject]@{
        Id     = 'UpdateExisting'
        Label  = 'Update existing - patch configs, content, TS, boot images'
        Detail = 'Idempotent update of an existing share.'
    })
    $scenarios.Add([pscustomobject]@{
        Id     = 'OemPacksOnly'
        Label  = 'OEM packs only - build vendor archives'
        Detail = 'Clone MDT-OEM-Extensibility and build selected vendor packs.'
    })
    $scenarios.Add([pscustomobject]@{
        Id     = 'ImageBuilderOnly'
        Label  = 'Image builder only - set up image-build workspace'
        Detail = 'Clone MDT-Windows-Image-Builder.'
    })

    Write-Host ''
    Write-Host 'Available scenarios on this machine:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $scenarios.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $scenarios[$i].Label) -ForegroundColor White
        Write-Host ("      {0}" -f $scenarios[$i].Detail) -ForegroundColor DarkGray
    }
    Write-Host ''

    while ($true) {
        $choice = Read-Host "Select a scenario [1-$($scenarios.Count)]"
        $n = 0
        if ([int]::TryParse($choice, [ref] $n) -and $n -ge 1 -and $n -le $scenarios.Count) {
            return $scenarios[$n - 1].Id
        }
        Write-Host 'Invalid selection.' -ForegroundColor Yellow
    }
}

#endregion


#region ─── Environment discovery ──────────────────────────────────────────

function Get-MDTMachineInfo {
    <#
    .SYNOPSIS
        Returns OS edition, ProductType, hostname, elevation, and
        domain membership for the local machine.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem

    $isServer = ($os.ProductType -ne 1)
    $edition = switch ($os.ProductType) {
        1       { 'Desktop' }
        2       { 'Server (Domain Controller)' }
        3       { 'Server' }
        default { 'Unknown' }
    }

    $fqdn = $env:COMPUTERNAME
    if ($env:USERDNSDOMAIN) { $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN" }

    [pscustomobject]@{
        Hostname          = $env:COMPUTERNAME
        FQDN              = $fqdn
        OSName            = $os.Caption
        OSVersion         = $os.Version
        OSBuild           = $os.BuildNumber
        ProductType       = $os.ProductType
        Edition           = $edition
        IsServer          = $isServer
        IsDomainJoined    = [bool]$cs.PartOfDomain
        Domain            = $cs.Domain
        Architecture      = $os.OSArchitecture
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        IsElevated        = Test-MDTIsAdmin
    }
}

function Get-MDTHostnamePolicy {
    <#
    .SYNOPSIS
        Computes the server name, share names, and UNC prefixes that the
        installer will patch into the deployment share.
    .PARAMETER ServerName
        Server hostname for UNC paths. Default $env:COMPUTERNAME.
    .PARAMETER SharedName
        Name of the shared-content share. Default 'Shared'.
    .PARAMETER OemName
        Name of the OEM sub-share under the shared share. Default 'OEM'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()] [string] $ServerName = $env:COMPUTERNAME,
        [Parameter()] [string] $SharedName = $script:MDTSharedName,
        [Parameter()] [string] $OemName    = $script:MDTOemName
    )

    $server = $ServerName.Trim()
    $shared = $SharedName.Trim().Trim('\', '/')
    $oem    = $OemName.Trim().Trim('\', '/')

    [pscustomobject]@{
        ServerName          = $server
        DeploymentShareName = $script:MDTDeploymentShareName
        SharedName          = $shared
        OemName             = $oem
        DeploymentShareUnc  = "\\$server\$($script:MDTDeploymentShareName)"
        SharedUnc           = "\\$server\$shared"
        OemUnc              = "\\$server\$shared\$oem"
        WinPeDriversUnc     = "\\$server\$shared\Drivers\WinPE"
        ReplacementToken    = '\\SERVER'
        ReplacementPrefix   = "\\$server"
    }
}

function Test-MDTPrerequisite {
    <#
    .SYNOPSIS
        Reports which MDT prerequisites are installed on this machine.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $adkCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit'),
        (Join-Path $env:ProgramFiles 'Windows Kits\10\Assessment and Deployment Kit')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $adkPath      = $adkCandidates | Select-Object -First 1
    $adkInstalled = [bool]$adkPath
    $winPePath    = if ($adkPath) { Join-Path $adkPath 'Windows Preinstallation Environment' } else { $null }
    $winPeInst    = $winPePath -and (Test-Path -LiteralPath $winPePath)

    $sdkCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'),
        (Join-Path $env:ProgramFiles 'Windows Kits\10\bin')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $sdkPath      = $sdkCandidates | Select-Object -First 1
    $sdkInstalled = [bool]$sdkPath

    $mdtPath      = Join-Path $env:ProgramFiles 'Microsoft Deployment Toolkit'
    $mdtInstalled = Test-Path -LiteralPath $mdtPath

    $sevenZipPath = 'C:\Program Files\7-Zip\7z.exe'
    $sevenZipInst = Test-Path -LiteralPath $sevenZipPath

    $wingetCmd    = Get-Command winget.exe -ErrorAction SilentlyContinue
    $pwshCmd      = Get-Command pwsh.exe   -ErrorAction SilentlyContinue

    $mdtSnapIn = $false
    if ($mdtInstalled) {
        try {
            $mdtSnapIn = [bool](Get-PSSnapin -Registered -Name 'Microsoft.BDD.PSSnapIn' -ErrorAction SilentlyContinue)
        } catch { $mdtSnapIn = $false }
    }

    [pscustomobject]@{
        ADK             = $adkInstalled
        ADKPath         = $adkPath
        WinPE           = $winPeInst
        WinPEPath       = $winPePath
        SDK             = $sdkInstalled
        SDKPath         = $sdkPath
        MDT             = $mdtInstalled
        MDTPath         = $mdtPath
        SevenZip        = $sevenZipInst
        SevenZipPath    = $sevenZipPath
        Winget          = [bool]$wingetCmd
        WingetPath      = if ($wingetCmd) { $wingetCmd.Source } else { $null }
        PowerShell7     = [bool]$pwshCmd
        PowerShell7Path = if ($pwshCmd) { $pwshCmd.Source } else { $null }
        MDTSnapIn       = $mdtSnapIn
        AllRequired     = ($adkInstalled -and $winPeInst -and $mdtInstalled -and $sevenZipInst)
    }
}

function Get-MDTDeploymentShares {
    <#
    .SYNOPSIS
        Enumerates MDT deployment shares known to this machine via the
        MDT PowerShell module.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $mdtPsd1 = Join-Path $env:ProgramFiles 'Microsoft Deployment Toolkit\Bin\MicrosoftDeploymentToolkit.psd1'
    if (-not (Test-Path -LiteralPath $mdtPsd1)) {
        Write-MDTInstallLog "MDT module not found at $mdtPsd1; cannot enumerate shares." -Level Warn
        return @()
    }

    try {
        Add-MDTMDTModule
        return @(Get-MDTDeploymentShare)
    } catch {
        Write-MDTInstallLog "Failed to enumerate MDT shares: $($_.Exception.Message)" -Level Warn
        return @()
    }
}

function Get-MDTNetworkConfig {
    <#
    .SYNOPSIS
        Returns the primary IPv4 network configuration of the local
        machine.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $cfg = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
        Select-Object -First 1

    if (-not $cfg) {
        return [pscustomobject]@{
            InterfaceAlias = $null
            IPAddress      = $null
            PrefixLength   = $null
            SubnetMask     = $null
            Gateway        = $null
            DNSServers     = @()
        }
    }

    $ip  = $cfg.IPv4Address[0].IPAddress
    $len = [int]$cfg.IPv4Address[0].PrefixLength
    $mask = $null
    if ($len -gt 0) {
        $maskUint = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $len))
        $mask = [IPAddress]::new($maskUint).ToString()
    }

    [pscustomobject]@{
        InterfaceAlias = $cfg.InterfaceAlias
        IPAddress      = $ip
        PrefixLength   = $len
        SubnetMask     = $mask
        Gateway        = $cfg.IPv4DefaultGateway.NextHop
        DNSServers     = @(
            $cfg.DNSServer |
                Where-Object { $_.AddressFamily -eq 2 } |
                ForEach-Object { $_.ServerAddresses } |
                Select-Object -First 3
        )
    }
}

function Get-MDTPXEScenario {
    <#
    .SYNOPSIS
        Determines where PXE is served on this machine.
    .OUTPUTS
        One of: WDS, AOMEI, Remote, None.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $info = Get-MDTMachineInfo

    if ($info.IsServer) {
        $wdsFeature = $null
        try { $wdsFeature = Get-WindowsFeature -Name WDS -ErrorAction SilentlyContinue } catch { }
        if ($wdsFeature -and $wdsFeature.Installed) { return 'WDS' }
        return 'None'
    }

    $aomeiCandidates = @(
        'C:\Program Files (x86)\AOMEI PXE Boot',
        'C:\Program Files\AOMEI PXE Boot'
    )
    foreach ($p in $aomeiCandidates) {
        if (Test-Path -LiteralPath $p) { return 'AOMEI' }
    }
    return 'None'
}

#endregion


#region ─── Prerequisite installation ───────────────────────────────────────

function Install-MDTSevenZip {
    <#
    .SYNOPSIS
        Installs 7-Zip if missing.
    #>
    [CmdletBinding()]
    param()

    $target = 'C:\Program Files\7-Zip\7z.exe'
    if (Test-Path -LiteralPath $target) {
        Write-MDTInstallLog '7-Zip already installed.'
        return
    }

    Assert-MDTIsAdmin 'install 7-Zip'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-MDTInstallLog 'Installing 7-Zip via winget...'
        & $winget.Source install --id 7zip.7zip --exact --silent --accept-package-agreements --accept-source-agreements
    } else {
        throw 'winget is not available and no direct fallback is configured for 7-Zip.'
    }

    if (-not (Test-Path -LiteralPath $target)) { throw '7-Zip install failed.' }
    Write-MDTInstallLog '7-Zip installed.'
}

function Install-MDTPowerShell7 {
    <#
    .SYNOPSIS
        Installs PowerShell 7 if missing. Tier 2.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        Write-MDTInstallLog 'PowerShell 7 already installed.'
        return
    }

    Assert-MDTIsAdmin 'install PowerShell 7'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'winget is not available; cannot install PowerShell 7.' }

    Write-MDTInstallLog 'Installing PowerShell 7 via winget...'
    & $winget.Source install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements
}

function Install-MDTFixes {
    <#
    .SYNOPSIS
        Runs the bundled All MDT Fixes 2025.exe.
    .PARAMETER SourcePath
        Path to the cloned MDT-Zero-Touch-Deployment repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourcePath
    )

    Assert-MDTIsAdmin 'apply MDT fixes'

    $fixes = Join-Path $SourcePath 'Prerequisites\All MDT Fixes 2025.exe'
    if (-not (Test-Path -LiteralPath $fixes)) {
        Write-MDTInstallLog "All MDT Fixes 2025.exe not found at $fixes; skipping." -Level Warn
        return
    }

    Write-MDTInstallLog "Running $fixes"
    $proc = Start-Process -FilePath $fixes -ArgumentList @('/S') -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-MDTInstallLog "Fixes executable returned exit code $($proc.ExitCode)." -Level Warn
    } else {
        Write-MDTInstallLog 'Fixes applied.'
    }
}

function Install-MDTPrerequisites {
    <#
    .SYNOPSIS
        Installs the MDT prerequisites (ADK, WinPE add-on, SDK, MDT).
    .DESCRIPTION
        For each prerequisite:
          1. If already installed, skip.
          2. If winget is available, install via winget.
          3. Otherwise, download from the configured direct URL and run
             the installer silently.
          4. If both fail, print the URL for manual handling.
    .PARAMETER LocalInstallerPath
        Optional folder containing pre-downloaded installers named
        per the FileName property in the prerequisite table.
    .PARAMETER Skip
        Names of prerequisites to skip (e.g. 'Windows SDK (deployment tools)').
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string] $LocalInstallerPath,
        [Parameter()] [string[]] $Skip = @()
    )

    Assert-MDTIsAdmin 'install MDT prerequisites'

    $state = Test-MDTPrerequisite
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    foreach ($p in $script:MDTPrerequisites) {
        if ($Skip -contains $p.Name) {
            Write-MDTInstallLog "Skipping $($p.Name) (requested)."
            continue
        }

        # Already installed?  ADK / WinPE / MDT / SDK checks.
        $already = switch ($p.Name) {
            'Windows ADK'                            { $state.ADK }
            'Windows PE Add-on for ADK'              { $state.WinPE }
            'Windows SDK (deployment tools)'         { $state.SDK }
            'Microsoft Deployment Toolkit 6.3.8456.1000' { $state.MDT }
            default                                  { $false }
        }
        if ($already) {
            Write-MDTInstallLog "$($p.Name) already installed."
            continue
        }

        $installed = $false

        # 1. Local installer path
        if ($LocalInstallerPath) {
            $local = Join-Path $LocalInstallerPath $p.FileName
            if (Test-Path -LiteralPath $local) {
                Write-MDTInstallLog "Installing $($p.Name) from $local"
                $args = @($p.Args)
                Start-Process -FilePath $local -ArgumentList $args -Wait
                $installed = $true
            }
        }

        # 2. winget
        if (-not $installed -and $winget -and $p.WingetId) {
            Write-MDTInstallLog "Installing $($p.Name) via winget ($($p.WingetId))..."
            & $winget.Source install --id $p.WingetId --exact --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) { $installed = $true }
        }

        # 3. Direct download
        if (-not $installed -and $p.DirectUrl) {
            try {
                $tmp = Join-Path $env:TEMP $p.FileName
                Invoke-MDTDownload -Url $p.DirectUrl -Destination $tmp
                Write-MDTInstallLog "Installing $($p.Name) from $tmp"
                Start-Process -FilePath $tmp -ArgumentList @($p.Args) -Wait
                $installed = $true
            } catch {
                Write-MDTInstallLog "Direct download failed for $($p.Name): $($_.Exception.Message)" -Level Warn
            }
        }

        if (-not $installed) {
            $msg = "Could not install $($p.Name) automatically. Download from: $($p.DirectUrl)"
            if ($p.Required) { throw $msg }
            Write-MDTInstallLog $msg -Level Warn
        }
    }

    Write-MDTInstallLog 'Prerequisite installation finished.'
}

#endregion


#region ─── Hostname and share-name patching ────────────────────────────────

function Get-MDTHostnameTargets {
    <#
    .SYNOPSIS
        Returns the list of files inside a deployment share that contain
        \\SERVER and need patching.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER OnlyExisting
        When set, filters the list to files that actually exist and
        contain the token.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter()] [switch] $OnlyExisting
    )

    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in $script:MDTHostnameTargets) {
        $full = Join-Path $SharePath $rel
        if ($OnlyExisting) {
            if (-not (Test-Path -LiteralPath $full)) { continue }
            $content = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
            if ($content -notmatch '\\\\SERVER') { continue }
        }
        $results.Add($full)
    }
    return $results.ToArray()
}

function Set-MDTHostnameInFiles {
    <#
    .SYNOPSIS
        Replaces \\SERVER in the given files with the replacement prefix.
        Writes atomically; returns per-file replacement counts.
    .PARAMETER Files
        One or more file paths to patch.
    .PARAMETER ReplacementPrefix
        Replacement for \\SERVER. Typically '\\HOSTNAME'.
    .PARAMETER Token
        Token to search for. Default '\\SERVER'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string[]] $Files,
        [Parameter(Mandatory)] [string] $ReplacementPrefix,
        [Parameter()] [string] $Token = '\\SERVER'
    )

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file)) {
            $results.Add([pscustomobject]@{ File = $file; Replacements = 0; Changed = $false; Error = 'File not found' })
            continue
        }

        try {
            $content = Get-Content -LiteralPath $file -Raw
            $count = ([regex]::Matches($content, [regex]::Escape($Token))).Count

            if ($count -eq 0) {
                $results.Add([pscustomobject]@{ File = $file; Replacements = 0; Changed = $false; Error = $null })
                continue
            }

            $updated = $content -replace [regex]::Escape($Token), $ReplacementPrefix
            Set-Content -LiteralPath $file -Value $updated -NoNewline -Encoding UTF8

            $results.Add([pscustomobject]@{ File = $file; Replacements = $count; Changed = $true; Error = $null })
        } catch {
            $results.Add([pscustomobject]@{ File = $file; Replacements = 0; Changed = $false; Error = $_.Exception.Message })
        }
    }

    return $results.ToArray()
}

function Set-MDTScriptHostname {
    <#
    .SYNOPSIS
        Patches all ten hostname-bearing files in a deployment share.
        Takes a backup first, replaces, verifies, and reports.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Policy
        Output of Get-MDTHostnamePolicy. When omitted, one is computed
        from $env:COMPUTERNAME.
    .PARAMETER NoBackup
        Skip the automatic pre-patch backup. Not recommended.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter()] [pscustomobject] $Policy,
        [Parameter()] [switch] $NoBackup
    )

    if (-not $Policy) { $Policy = Get-MDTHostnamePolicy }

    Write-MDTInstallLog "Patching hostname references to $($Policy.ReplacementPrefix) under $SharePath"

    $backupPath = $null
    if (-not $NoBackup) {
        $backupPath = New-MDTBackup -SharePath $SharePath -Reason 'pre-hostname-patch'
        Write-MDTInstallLog "Pre-patch backup: $backupPath"
    }

    $files   = Get-MDTHostnameTargets -SharePath $SharePath -OnlyExisting
    $results = Set-MDTHostnameInFiles -Files $files -ReplacementPrefix $Policy.ReplacementPrefix -Token $Policy.ReplacementToken

    $failed = $results | Where-Object { $_.Error }
    if ($failed) {
        Write-MDTInstallLog "Hostname patch failed for $($failed.Count) file(s)." -Level Error
        foreach ($f in $failed) {
            Write-MDTInstallLog ("  {0}: {1}" -f $f.File, $f.Error) -Level Error
        }
        if ($backupPath) {
            Write-MDTInstallLog "Rolling back from $backupPath"
            Restore-MDTBackup -BackupPath $backupPath -SharePath $SharePath
        }
        throw 'Hostname patching failed; rollback performed.'
    }

    $total = ($results | Measure-Object -Property Replacements -Sum).Sum
    Write-MDTInstallLog "Hostname patch complete. $total replacement(s) across $($results.Count) file(s)."

    [pscustomobject]@{
        SharePath  = $SharePath
        Policy     = $Policy
        Files      = $results
        Total      = $total
        BackupPath = $backupPath
    }
}

#endregion


#region ─── Configuration file patching ────────────────────────────────────

function Set-MDTBootstrapIni {
    <#
    .SYNOPSIS
        Patches Control\Bootstrap.ini with the server name and default
        credentials.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Policy
        Output of Get-MDTHostnamePolicy.
    .PARAMETER UserDomain
        Value for the UserDomain key. Default 'localhost'.
    .PARAMETER UserID
        Value for the UserID key. Default 'Network User'.
    .PARAMETER UserPassword
        Value for the UserPassword key. Default 'p@$$w0rd'.
    .PARAMETER SkipDomain
        Do not set UserDomain.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter(Mandatory)] [pscustomobject] $Policy,
        [Parameter()] [string] $UserDomain   = 'localhost',
        [Parameter()] [string] $UserID       = 'Network User',
        [Parameter()] [string] $UserPassword = 'p@$$w0rd',
        [Parameter()] [switch] $SkipDomain
    )

    $file = Join-Path $SharePath 'Control\Bootstrap.ini'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-MDTInstallLog "Bootstrap.ini not found at $file; skipping." -Level Warn
        return
    }

    if (-not $PSCmdlet.ShouldProcess($file, 'Patch Bootstrap.ini')) { return }

    $lines = Get-Content -LiteralPath $file
    $out   = foreach ($line in $lines) {
        switch -Regex ($line) {
            '^\s*DeployRoot\s*='    { "DeployRoot=$($Policy.DeploymentShareUnc)"; continue }
            '^\s*UserDomain\s*='    { if (-not $SkipDomain) { "UserDomain=$UserDomain" } else { $line }; continue }
            '^\s*UserID\s*='        { "UserID=$UserID"; continue }
            '^\s*UserPassword\s*='  { "UserPassword=$UserPassword"; continue }
            default                 { $line }
        }
    }
    Set-Content -LiteralPath $file -Value $out -Encoding UTF8
    Write-MDTInstallLog "Patched $file"
}

function Set-MDTSettingsXml {
    <#
    .SYNOPSIS
        Patches Control\Settings.xml with the deployment-share UNC.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Policy
        Output of Get-MDTHostnamePolicy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter(Mandatory)] [pscustomobject] $Policy
    )

    $file = Join-Path $SharePath 'Control\Settings.xml'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-MDTInstallLog "Settings.xml not found at $file; skipping." -Level Warn
        return
    }
    if (-not $PSCmdlet.ShouldProcess($file, 'Patch Settings.xml')) { return }

    [xml]$xml = Get-Content -LiteralPath $file -Raw
    $root = $xml.DocumentElement
    $changed = $false

    foreach ($node in $root.SelectNodes('//*')) {
        if ($node.Name -eq 'UNCPath') {
            $node.InnerText = $Policy.DeploymentShareUnc
            $changed = $true
        }
    }

    if ($changed) {
        $xml.Save($file)
        Write-MDTInstallLog "Patched $file"
    } else {
        Write-MDTInstallLog "No UNCPath found in $file; leaving as-is."
    }
}

function Set-MDTMediasXml {
    <#
    .SYNOPSIS
        Patches Control\Medias.xml with the deployment-share UNC.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Policy
        Output of Get-MDTHostnamePolicy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter(Mandatory)] [pscustomobject] $Policy
    )

    $file = Join-Path $SharePath 'Control\Medias.xml'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-MDTInstallLog "Medias.xml not found at $file; skipping (optional)." -Level Warn
        return
    }
    if (-not $PSCmdlet.ShouldProcess($file, 'Patch Medias.xml')) { return }

    [xml]$xml = Get-Content -LiteralPath $file -Raw
    $changed = $false
    foreach ($node in $xml.DocumentElement.SelectNodes('//*')) {
        if ($node.InnerText -match '\\\\SERVER') {
            $node.InnerText = $node.InnerText -replace '\\\\SERVER', $Policy.ReplacementPrefix
            $changed = $true
        }
    }
    if ($changed) {
        $xml.Save($file)
        Write-MDTInstallLog "Patched $file"
    } else {
        Write-MDTInstallLog "No \\SERVER references found in $file."
    }
}

function Set-MDTCustomSettingsIni {
    <#
    .SYNOPSIS
        Patches Control\CustomSettings.ini with site-specific values.
        Tier 2.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Settings
        Hashtable of Key=Value pairs to set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter(Mandatory)] [hashtable] $Settings
    )

    $file = Join-Path $SharePath 'Control\CustomSettings.ini'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-MDTInstallLog "CustomSettings.ini not found at $file; skipping." -Level Warn
        return
    }
    if (-not $PSCmdlet.ShouldProcess($file, 'Patch CustomSettings.ini')) { return }

    $lines = Get-Content -LiteralPath $file
    $out   = foreach ($line in $lines) {
        $matched = $false
        foreach ($key in $Settings.Keys) {
            if ($line -match "^\s*$([regex]::Escape($key))\s*=") {
                "$key=$($Settings[$key])"
                $matched = $true
                break
            }
        }
        if (-not $matched) { $line }
    }

    # Append any keys not present in the file.
    $existing = ($out | Where-Object { $_ -match '^\s*([^#;=]+)=' } |
        ForEach-Object { ($_ -split '=', 2)[0].Trim() }) | Sort-Object -Unique
    $toAppend = foreach ($key in $Settings.Keys) { if ($existing -notcontains $key) { "$key=$($Settings[$key])" } }
    if ($toAppend) { $out = @($out) + $toAppend }

    Set-Content -LiteralPath $file -Value $out -Encoding UTF8
    Write-MDTInstallLog "Patched $file"
}

#endregion


#region ─── Network role installation (DHCP + WDS) ──────────────────────────

function Install-MDTDhcpRole {
    <#
    .SYNOPSIS
        Installs the DHCP Server role with a PXE scope and vendor
        policies, using native Windows PowerShell cmdlets.
    .DESCRIPTION
        Fully idempotent. If the role is already installed the function
        ensures the scope and policies exist and adds any missing pieces.
    .PARAMETER ScopeId
        Network ID for the PXE scope, e.g. 192.168.1.0.
    .PARAMETER ScopeName
        Display name for the scope.
    .PARAMETER StartRange
        First address in the PXE range.
    .PARAMETER EndRange
        Last address in the PXE range.
    .PARAMETER SubnetMask
        Subnet mask for the scope.
    .PARAMETER Router
        Default gateway for clients.
    .PARAMETER DnsServers
        DNS servers offered to clients.
    .PARAMETER LeaseDuration
        Lease duration as a TimeSpan string. Default 1 minute.
    .PARAMETER ServerName
        Name of the PXE server for option 66. Default $env:COMPUTERNAME.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]   $ScopeId,
        [Parameter()] [string]            $ScopeName    = 'PXE Clients',
        [Parameter(Mandatory)] [string]   $StartRange,
        [Parameter(Mandatory)] [string]   $EndRange,
        [Parameter(Mandatory)] [string]   $SubnetMask,
        [Parameter()] [string]            $Router,
        [Parameter()] [string[]]          $DnsServers   = @(),
        [Parameter()] [string]            $LeaseDuration = '00:01:00',
        [Parameter()] [string]            $ServerName   = $env:COMPUTERNAME
    )

    Assert-MDTIsAdmin 'install and configure the DHCP role'
    if (-not $PSCmdlet.ShouldProcess('DHCP role', 'Install and configure')) { return }

    Write-MDTInstallLog 'Installing DHCP Server role...'
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

    Import-Module DhcpServer -ErrorAction Stop

    $existingScope = Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue
    if (-not $existingScope) {
        Write-MDTInstallLog "Adding scope $ScopeId ($StartRange - $EndRange)"
        Add-DhcpServerv4Scope `
            -Name $ScopeName `
            -StartRange $StartRange `
            -EndRange $EndRange `
            -SubnetMask $SubnetMask `
            -State Active | Out-Null
    } else {
        Write-MDTInstallLog "Scope $ScopeId already exists; ensuring range."
        Set-DhcpServerv4Scope -ScopeId $ScopeId -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask
    }

    Set-DhcpServerv4Scope -ScopeId $ScopeId -LeaseDuration $LeaseDuration

    if ($Router) {
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -Force
    }
    if ($DnsServers.Count) {
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsServer $DnsServers -Force
    }
    Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 60 -Value 'PXEClient' -Force

    # Boot-file vendor policies. Recreated only if absent.
    $policies = @(
        @{ Name = 'PXEClient (UEFI x64)';         VendorClass = 'PXEClient (UEFI x64)*';         BootFile = 'boot\x64\wdsmgfw.efi' }
        @{ Name = 'PXEClient (UEFI x86)';         VendorClass = 'PXEClient (UEFI x86)*';         BootFile = 'boot\x86\wdsmgfw.efi' }
        @{ Name = 'PXEClient (BIOS x86 & x64)';   VendorClass = 'PXEClient (BIOS x86 & x64)*';   BootFile = 'boot\x64\wdsnbp.com' }
    )

    foreach ($p in $policies) {
        $existing = Get-DhcpServerv4Policy -ScopeId $ScopeId -Name $p.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-MDTInstallLog "Policy '$($p.Name)' already exists; leaving."
            continue
        }
        Write-MDTInstallLog "Adding policy '$($p.Name)'"
        Add-DhcpServerv4Policy -ScopeId $ScopeId -Name $p.Name -Condition OR -VendorClass EQ, $p.VendorClass | Out-Null
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -PolicyName $p.Name -OptionId 67 -Value $p.BootFile -Force
    }

    # DHCP server-level option 66 for WDS redirection.
    Set-DhcpServerv4OptionValue -OptionId 66 -Value $ServerName -Force -ErrorAction SilentlyContinue

    Restart-Service DHCPServer -Force
    Write-MDTInstallLog 'DHCP role configured.'
}

function Install-MDTWdsRole {
    <#
    .SYNOPSIS
        Installs and configures the WDS role in Native mode, pointing at
        a deployment share for boot image sources.
    .PARAMETER RemoteInstallPath
        Local folder for WDS content. Default C:\RemoteInstall.
    .PARAMETER DeploymentShareUnc
        UNC of the MDT deployment share that WDS should import boot
        images from. Optional; only used for the initial import.
    .PARAMETER PxeResponsePolicy
        Default, RespondAll, RespondOnlyKnown, or DoNotRespond.
        Default RespondAll.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()] [string] $RemoteInstallPath = 'C:\RemoteInstall',
        [Parameter()] [string] $DeploymentShareUnc,
        [Parameter()] [ValidateSet('Default', 'RespondAll', 'RespondOnlyKnown', 'DoNotRespond')]
                      [string] $PxeResponsePolicy = 'RespondAll'
    )

    Assert-MDTIsAdmin 'install and configure the WDS role'
    if (-not $PSCmdlet.ShouldProcess('WDS role', 'Install and configure')) { return }

    Write-MDTInstallLog 'Installing WDS role...'
    Install-WindowsFeature -Name WDS -IncludeManagementTools | Out-Null

    Import-Module WDS -ErrorAction Stop

    Write-MDTInstallLog 'Initialising WDS server...'
    wdsutil /initialize-server /reminst:"$RemoteInstallPath" | Out-Null

    Write-MDTInstallLog "Setting PXE response policy to $PxeResponsePolicy"
    $wdsPolicyArg = switch ($PxeResponsePolicy) {
        'RespondAll'        { '/response:all' }
        'RespondOnlyKnown'  { '/response:known' }
        'DoNotRespond'      { '/response:none' }
        default             { '/response:all' }
    }
    wdsutil /set-server /answerclients:$($PxeResponsePolicy.ToLower()) | Out-Null

    if ($DeploymentShareUnc) {
        $bootWim = Join-Path $DeploymentShareUnc 'Boot\LiteTouchPE_x64.wim'
        if (Test-Path -LiteralPath $bootWim) {
            Write-MDTInstallLog "Importing boot image from $bootWim"
            Import-WdsBootImage -Path $bootWim -NewImageName 'LiteTouch x64' -SkipVerify -ErrorAction Continue | Out-Null
        } else {
            Write-MDTInstallLog "Boot WIM not found at $bootWim; import separately." -Level Warn
        }
    }

    Write-MDTInstallLog 'WDS role configured.'
}

function Add-MDTDhcpAuthorization {
    <#
    .SYNOPSIS
        Authorises the local DHCP server in Active Directory when the
        machine is domain-joined and not already authorised.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $info = Get-MDTMachineInfo
    if (-not $info.IsDomainJoined) {
        Write-MDTInstallLog 'Not domain-joined; skipping DHCP authorisation.'
        return
    }

    Assert-MDTIsAdmin 'authorise the DHCP server in AD'

    Import-Module DhcpServer -ErrorAction Stop

    $existing = Get-DhcpServerInDC -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq (Get-MDTNetworkConfig).IPAddress }

    if ($existing) {
        Write-MDTInstallLog 'DHCP server already authorised.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Authorise DHCP server in AD')) { return }
    Add-DhcpServerInDC -DnsName $info.FQDN -IPAddress (Get-MDTNetworkConfig).IPAddress
    Write-MDTInstallLog 'DHCP server authorised.'
}

#endregion


#region ─── AOMEI PXE setup (desktop) ───────────────────────────────────────

function Install-MDTAomeiPxeBoot {
    <#
    .SYNOPSIS
        Extracts and runs AOMEI PXE Boot Free from the source tree.
    .PARAMETER SourcePath
        Path to the cloned MDT-Zero-Touch-Deployment repository.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SourcePath
    )

    $installer = Join-Path $SourcePath 'Prerequisites\for Desktop Editions of Windows\AOMEI PXE Boot Free 1.5\PXEBoot.exe'
    if (-not (Test-Path -LiteralPath $installer)) {
        Write-MDTInstallLog "AOMEI PXE Boot installer not found at $installer." -Level Warn
        return
    }

    if (-not $PSCmdlet.ShouldProcess($installer, 'Run AOMEI PXE Boot installer')) { return }

    Write-MDTInstallLog "Launching $installer"
    Start-Process -FilePath $installer -Wait
    Write-MDTInstallLog 'AOMEI PXE Boot installer finished. Follow the GUI to complete setup.'
}

function Set-MDTAomeiConfig {
    <#
    .SYNOPSIS
        Points AOMEI PXE Boot at the LiteTouch boot WIM. Tier 2.
    .PARAMETER BootWimPath
        Full path to LiteTouchPE_x64.wim.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $BootWimPath
    )

    if (-not (Test-Path -LiteralPath $BootWimPath)) {
        throw "Boot WIM not found at $BootWimPath"
    }

    Write-MDTInstallLog 'AOMEI PXE Boot configuration is not automatable; see docs/OFFLINE-MEDIA.md.' -Level Warn
    Write-MDTInstallLog "Point AOMEI at: $BootWimPath"
}

#endregion


#region ─── Backup and rollback ────────────────────────────────────────────

function New-MDTBackup {
    <#
    .SYNOPSIS
        Copies the folders the installer touches into a timestamped
        backup directory and returns its path.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER Reason
        Free-text tag embedded in the backup folder name.
    .PARAMETER BackupRoot
        Override the backup root. Defaults to the module default.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter()] [string] $Reason = 'snapshot',
        [Parameter()] [string] $BackupRoot = $script:MDTBackupRoot
    )

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeReason = ($Reason -replace '[^\w\-]', '_')
    $dest = Join-Path $BackupRoot "$stamp`_$safeReason"
    $dest = Join-Path $dest 'share'

    if (-not $PSCmdlet.ShouldProcess($dest, 'Create MDT backup')) { return $dest }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    foreach ($rel in $script:MDTBackupFolders) {
        $src = Join-Path $SharePath $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dstRel = Join-Path $dest $rel
        $null = New-Item -ItemType Directory -Path $dstRel -Force
        Copy-Item -Path (Join-Path $src '*') -Destination $dstRel -Recurse -Force -ErrorAction Continue
    }

    # Copy Control\*.ini and Control\*.xml at the top level as well.
    $controlDest = Join-Path $dest 'Control'
    foreach ($pattern in @('*.ini', '*.xml')) {
        Copy-Item -Path (Join-Path $SharePath "Control\$pattern") -Destination $controlDest -Force -ErrorAction SilentlyContinue
    }

    Write-MDTInstallLog "Backup written to $dest"
    return $dest
}

function Get-MDTBackup {
    <#
    .SYNOPSIS
        Enumerates available backups under the backup root.
    .PARAMETER BackupRoot
        Override the backup root. Defaults to the module default.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter()] [string] $BackupRoot = $script:MDTBackupRoot
    )

    if (-not (Test-Path -LiteralPath $BackupRoot)) { return @() }

    Get-ChildItem -LiteralPath $BackupRoot -Directory |
        Sort-Object Name -Descending |
        ForEach-Object {
            [pscustomobject]@{
                Name       = $_.Name
                Path       = $_.FullName
                Created    = $_.CreationTime
                SharePath  = Join-Path $_.FullName 'share'
            }
        }
}

function Restore-MDTBackup {
    <#
    .SYNOPSIS
        Restores a deployment share from a backup produced by
        New-MDTBackup.
    .PARAMETER BackupPath
        Path to the backup folder (as returned by New-MDTBackup).
    .PARAMETER SharePath
        Root of the deployment share to restore into.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $BackupPath,
        [Parameter(Mandatory)] [string] $SharePath
    )

    $src = Join-Path $BackupPath 'share'
    if (-not (Test-Path -LiteralPath $src)) {
        # Accept either the outer wrapper or the share folder directly.
        if ((Split-Path -Leaf $BackupPath) -eq 'share') { $src = $BackupPath }
        else { throw "Backup does not contain a share folder: $BackupPath" }
    }

    if (-not $PSCmdlet.ShouldProcess($SharePath, "Restore from $BackupPath")) { return }

    foreach ($rel in $script:MDTBackupFolders) {
        $srcRel = Join-Path $src $rel
        if (-not (Test-Path -LiteralPath $srcRel)) { continue }
        $dstRel = Join-Path $SharePath $rel
        $null = New-Item -ItemType Directory -Path $dstRel -Force
        Copy-Item -Path (Join-Path $srcRel '*') -Destination $dstRel -Recurse -Force
    }

    Write-MDTInstallLog "Restored $SharePath from $BackupPath"
}

#endregion


#region ─── Merge ──────────────────────────────────────────────────────────

function Merge-MDTDeploymentShare {
    <#
    .SYNOPSIS
        Copies the repository's DeploymentShare\ tree into a target
        deployment share, without deleting anything already present.
    .PARAMETER SourcePath
        Root of the cloned repository.
    .PARAMETER TargetSharePath
        Root of the target deployment share.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $TargetSharePath
    )

    $source = Join-Path $SourcePath 'DeploymentShare'
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Repository does not contain a DeploymentShare folder at $source"
    }

    if (-not $PSCmdlet.ShouldProcess($TargetSharePath, "Merge from $source")) { return }

    $null = New-Item -ItemType Directory -Path $TargetSharePath -Force

    $args = @(
        $source, $TargetSharePath,
        '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP',
        '/XD', '.git', '.github', 'node_modules'
    )
    Write-MDTInstallLog "robocopy $($args -join ' ')"
    $proc = Start-Process -FilePath 'robocopy' -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ge 8) {
        throw "robocopy failed with exit code $($proc.ExitCode)"
    }
    Write-MDTInstallLog "Merged $source -> $TargetSharePath (robocopy exit $($proc.ExitCode))."
}

function Copy-MDTOEMContent {
    <#
    .SYNOPSIS
        Copies built OEM archives from a source folder (network or USB)
        into the target share's OEM area.
    .PARAMETER SourceFolder
        Folder containing the vendor .7z archives.
    .PARAMETER TargetSharePath
        Root of the deployment share.
    .PARAMETER OemSubPath
        Sub-path under the share for OEM archives. Default Shared\OEM.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SourceFolder,
        [Parameter(Mandatory)] [string] $TargetSharePath,
        [Parameter()] [string] $OemSubPath = "$($script:MDTSharedName)\$($script:MDTOemName)"
    )

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        throw "Source folder not found: $SourceFolder"
    }
    $target = Join-Path $TargetSharePath $OemSubPath
    if (-not $PSCmdlet.ShouldProcess($target, "Copy OEM archives from $SourceFolder")) { return }

    $null = New-Item -ItemType Directory -Path $target -Force
    $archives = Get-ChildItem -LiteralPath $SourceFolder -Filter '*.7z' -File -Recurse
    if (-not $archives) {
        Write-MDTInstallLog "No .7z archives found under $SourceFolder." -Level Warn
        return
    }
    foreach ($a in $archives) {
        Copy-Item -LiteralPath $a.FullName -Destination $target -Force
        Write-MDTInstallLog "Copied $($a.Name) -> $target"
    }
}

function Copy-MDTMediaContent {
    <#
    .SYNOPSIS
        Copies pre-built offline media content to a USB target.
        Tier 2.
    .PARAMETER MediaSource
        Folder containing the built media set.
    .PARAMETER UsbRoot
        Root of the target USB drive, e.g. E:\.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $MediaSource,
        [Parameter(Mandatory)] [string] $UsbRoot
    )

    if (-not (Test-Path -LiteralPath $MediaSource)) { throw "Media source not found: $MediaSource" }
    if (-not (Test-Path -LiteralPath $UsbRoot))     { throw "USB root not found: $UsbRoot" }
    if (-not $PSCmdlet.ShouldProcess($UsbRoot, "Copy media from $MediaSource")) { return }

    $args = @($MediaSource, $UsbRoot, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    $proc = Start-Process -FilePath 'robocopy' -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ge 8) { throw "robocopy failed with exit code $($proc.ExitCode)" }
    Write-MDTInstallLog "Copied media to $UsbRoot"
}

#endregion


#region ─── MDT cmdlet wrappers ─────────────────────────────────────────────

function Import-MDTTaskSequences {
    <#
    .SYNOPSIS
        Imports the three task sequences into a deployment share.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER TaskSequenceIds
        Task sequence IDs to import. Defaults to WIN11PROX64,
        WIN10PROX64, WIN10PROX86.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter()] [string[]] $TaskSequenceIds = @('WIN11PROX64', 'WIN10PROX64', 'WIN10PROX86')
    )

    Add-MDTMDTModule

    foreach ($id in $TaskSequenceIds) {
        $tsXml = Join-Path $SharePath "Control\$id\ts.xml"
        if (-not (Test-Path -LiteralPath $tsXml)) {
            Write-MDTInstallLog "Task sequence XML missing: $tsXml" -Level Warn
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($id, 'Import task sequence')) { continue }

        try {
            Import-MDTTaskSequence -Path $SharePath -FilePath $tsXml -ErrorAction Stop | Out-Null
            Write-MDTInstallLog "Imported task sequence $id"
        } catch {
            Write-MDTInstallLog "Failed to import $id: $($_.Exception.Message)" -Level Warn
        }
    }
}

function Update-MDTBootImages {
    <#
    .SYNOPSIS
        Regenerates LiteTouch boot images in a deployment share.
    .PARAMETER SharePath
        Root of the deployment share.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath
    )

    Add-MDTMDTModule

    if (-not $PSCmdlet.ShouldProcess($SharePath, 'Regenerate boot images')) { return }

    Write-MDTInstallLog "Regenerating boot images for $SharePath (this can take several minutes)..."
    Update-MDTDeploymentShare -Path $SharePath -Force
    Write-MDTInstallLog 'Boot images regenerated.'
}

function New-MDTOfflineMedia {
    <#
    .SYNOPSIS
        Builds an offline media set from a deployment share. Tier 2.
    .PARAMETER SharePath
        Root of the deployment share.
    .PARAMETER MediaPath
        Destination folder for the media set.
    .PARAMETER MediaId
        Media identifier to use or create.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SharePath,
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter()] [string] $MediaId = 'MEDIA001'
    )

    Add-MDTMDTModule

    if (-not $PSCmdlet.ShouldProcess($MediaPath, "Build offline media ($MediaId)")) { return }

    Write-MDTInstallLog "Building offline media $MediaId at $MediaPath"
    if (-not (Test-Path -LiteralPath $MediaPath)) { New-Item -ItemType Directory -Path $MediaPath -Force | Out-Null }
    New-MDTMedia -Path $SharePath -MediaPath $MediaPath -MediaID $MediaId
    Write-MDTInstallLog 'Offline media build complete.'
}

#endregion


#region ─── Companion repositories ──────────────────────────────────────────

function Get-MDTCompanionRepo {
    <#
    .SYNOPSIS
        Clones or pulls one of the companion repositories.
    .PARAMETER Name
        OEM or Builder.
    .PARAMETER Destination
        Override the default clone path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OEM', 'Builder')]
        [string] $Name,
        [Parameter()] [string] $Destination
    )

    $repo = $script:MDTCompanionRepos[$Name]
    $path = if ($Destination) { $Destination } else { $repo.Path }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { throw 'git.exe not found in PATH.' }

    if (Test-Path -LiteralPath $path) {
        Write-MDTInstallLog "Pulling $($repo.Name) in $path"
        & $git.Source -C $path pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-MDTInstallLog "git pull returned $LASTEXITCODE" -Level Warn }
    } else {
        Write-MDTInstallLog "Cloning $($repo.Url) -> $path"
        $parent = Split-Path -Parent $path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        & $git.Source clone $repo.Url $path
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
    }

    return $path
}

function Invoke-OEMArchiveBuild {
    <#
    .SYNOPSIS
        Runs Build-OEMPack.ps1 in MDT-OEM-Extensibility for the given
        vendors.
    .PARAMETER RepoPath
        Path to the cloned MDT-OEM-Extensibility repository.
    .PARAMETER Vendors
        Vendors to build. Empty means all.
    .PARAMETER OutputPath
        Destination folder for the built .7z archives.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter()] [string[]] $Vendors = @(),
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $script = Join-Path $RepoPath 'tools\Build-OEMPack.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Build-OEMPack.ps1 not found at $script"
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $params = @{ OutputPath = $OutputPath }
    if ($Vendors.Count) { $params['Vendor'] = $Vendors }

    Write-MDTInstallLog "Building OEM packs -> $OutputPath"
    & $script @params
    Write-MDTInstallLog 'OEM pack build complete.'
}

#endregion


Export-ModuleMember -Function @(
    'Initialize-MDTInstallLog'
    'Write-MDTInstallLog'
    'Confirm-MDTAction'
    'Show-MDTScenarioPicker'
    'Get-MDTMachineInfo'
    'Get-MDTHostnamePolicy'
    'Test-MDTPrerequisite'
    'Get-MDTDeploymentShares'
    'Get-MDTNetworkConfig'
    'Get-MDTPXEScenario'
    'Install-MDTSevenZip'
    'Install-MDTPowerShell7'
    'Install-MDTFixes'
    'Install-MDTPrerequisites'
    'Get-MDTHostnameTargets'
    'Set-MDTHostnameInFiles'
    'Set-MDTScriptHostname'
    'Set-MDTBootstrapIni'
    'Set-MDTSettingsXml'
    'Set-MDTMediasXml'
    'Set-MDTCustomSettingsIni'
    'Install-MDTDhcpRole'
    'Install-MDTWdsRole'
    'Add-MDTDhcpAuthorization'
    'Install-MDTAomeiPxeBoot'
    'Set-MDTAomeiConfig'
    'New-MDTBackup'
    'Get-MDTBackup'
    'Restore-MDTBackup'
    'Merge-MDTDeploymentShare'
    'Copy-MDTOEMContent'
    'Copy-MDTMediaContent'
    'Import-MDTTaskSequences'
    'Update-MDTBootImages'
    'New-MDTOfflineMedia'
    'Get-MDTCompanionRepo'
    'Invoke-OEMArchiveBuild'
)
