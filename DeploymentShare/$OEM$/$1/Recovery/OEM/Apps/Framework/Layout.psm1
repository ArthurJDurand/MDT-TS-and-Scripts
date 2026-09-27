<#
.SYNOPSIS
    Vendor-neutral layout file generation and pin resolution.

.DESCRIPTION
    Files are the source of truth. Idempotency is content-based via
    Write-ContentIfDifferent. AutoApply is a read-only ownership signal.

    Pins are delivered by layout files at next logon. The Shell.Application
    taskbarpin/startpin COM verbs were removed by Microsoft in Windows 10
    version 1903; on 1903 and later (and on all Windows 11 builds) those
    verbs are silent no-ops. Layout files are therefore the only working
    pin-delivery mechanism on supported Windows builds.
#>

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Content
    )

    $directory = Split-Path $Path -Parent
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tempPath = "$Path.tmp"

    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        Move-Item -Path $tempPath -Destination $Path -Force -ErrorAction Stop | Out-Null
    }
    catch {
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Write-ContentIfDifferent {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$DesiredContent
    )

    if (Test-Path $Path) {
        $current = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
        if ($current -eq $DesiredContent) { return $false }
    }
    $null = Write-Utf8NoBomFile -Path $Path -Content $DesiredContent
    return $true
}

function New-Win11StartLayoutJson {
    param([System.Collections.ArrayList]$Pins)

    $items = @()
    foreach ($pin in $Pins) {
        if ($pin.Type -in @('Packaged','UWA','AUMID')) {
            $items += [ordered]@{ 'packagedAppId' = $pin.Id }
        }
        elseif ($pin.Type -eq 'Desktop') {
            $items += [ordered]@{ 'desktopAppLink' = $pin.Id }
        }
    }
    return ConvertTo-Json -InputObject ([ordered]@{ 'primaryOEMPins' = $items }) -Depth 4 -Compress
}

function New-Win11TaskbarLayoutXml {
    param([System.Collections.ArrayList]$Pins)

    $xmlPins = New-Object System.Collections.ArrayList
    foreach ($pin in $Pins) {
        # Escape the pin identifier before XML interpolation. AUMIDs are
        # constrained in practice, but Desktop pin paths can legally contain
        # characters that are not valid raw inside an XML attribute (notably
        # '&'). A malformed taskbar file causes Windows to silently ignore
        # the entire layout file — pins simply do not appear, with no error
        # anywhere. SecurityElement.Escape handles &, <, >, ", '.
        $safeId = [System.Security.SecurityElement]::Escape([string]$pin.Id)
        if ($pin.Type -in @('Packaged','UWA','AUMID')) {
            $null = $xmlPins.Add("        <taskbar:UWA AppUserModelID=`"$safeId`" />")
        }
        elseif ($pin.Type -eq 'Desktop') {
            $null = $xmlPins.Add("        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$safeId`" />")
        }
    }
    $pinList = $xmlPins -join "`r`n"
    return @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate Version="1" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout">
  <CustomTaskbarLayoutCollection PinListPlacement="Append">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$pinList
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
}

function Merge-Win10Layout {
    param(
        [string]$BrandName,
        [object[]]$StartPins,
        [object[]]$TaskbarPins,
        [string]$BasePath
    )

    if (-not $BasePath -or -not (Test-Path $BasePath)) { return $null }

    try {
        [xml]$xml = Get-Content -Path $BasePath -Raw -ErrorAction Stop
    } catch { return $null }

    $ns = @{
        lm            = 'http://schemas.microsoft.com/Start/2014/LayoutModification'
        defaultlayout = 'http://schemas.microsoft.com/Start/2014/FullDefaultLayout'
        start         = 'http://schemas.microsoft.com/Start/2014/StartLayout'
        taskbar       = 'http://schemas.microsoft.com/Start/2014/TaskbarLayout'
    }
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    foreach ($k in $ns.Keys) { $nsmgr.AddNamespace($k, $ns[$k]) }

    $root = $xml.DocumentElement
    $defaultLayoutOverride = $root.SelectSingleNode('//lm:DefaultLayoutOverride', $nsmgr)
    if (-not $defaultLayoutOverride) {
        Write-DeploymentLog -Message "Windows 10 base template at $BasePath is missing DefaultLayoutOverride; cannot merge." -Level WARN
        return $null
    }

    $defaultStart = $root.SelectSingleNode('//lm:DefaultLayoutOverride/lm:StartLayoutCollection/defaultlayout:StartLayout[@GroupCellWidth="6"]', $nsmgr)
    if (-not $defaultStart) {
        $defaultStart = $xml.CreateElement('defaultlayout','StartLayout',$ns['defaultlayout'])
        $defaultStart.SetAttribute('GroupCellWidth','6')
        $startColl = $defaultLayoutOverride.SelectSingleNode('lm:StartLayoutCollection', $nsmgr)
        if (-not $startColl) {
            $startColl = $xml.CreateElement('StartLayoutCollection',$ns['lm'])
            $defaultLayoutOverride.AppendChild($startColl) | Out-Null
        }
        $startColl.AppendChild($defaultStart) | Out-Null
    }

    # Match the brand group by attribute rather than by XPath string literal,
    # to avoid quoting/injection issues if the brand name contains an apostrophe.
    $brandGroupName = "$BrandName Apps"
    $existingGroups = @()
    foreach ($g in $defaultStart.SelectNodes('start:Group', $nsmgr)) {
        if ($g.GetAttribute('Name') -eq $brandGroupName) { $existingGroups += $g }
    }
    if ($existingGroups.Count -gt 0) {
        foreach ($g in $existingGroups) { [void]$defaultStart.RemoveChild($g) }
    }

    $newGroup = $xml.CreateElement('start','Group',$ns['start'])
    $newGroup.SetAttribute('Name', "$BrandName Apps")

    $col = 0; $row = 0
    foreach ($pin in $StartPins) {
        if ($pin.Type -in @('Packaged','UWA','AUMID')) {
            $tile = $xml.CreateElement('start','Tile',$ns['start'])
            $tile.SetAttribute('AppUserModelID', $pin.Id)
        }
        elseif ($pin.Type -eq 'Desktop') {
            $tile = $xml.CreateElement('start','DesktopApplicationTile',$ns['start'])
            $tile.SetAttribute('DesktopApplicationLinkPath', $pin.Id)
        } else { continue }
        $tile.SetAttribute('Size','2x2')
        $tile.SetAttribute('Column',[string]$col)
        $tile.SetAttribute('Row',[string]$row)
        $newGroup.AppendChild($tile) | Out-Null
        $col += 2
        if ($col -ge 6) { $col = 0; $row += 2 }
    }
    $defaultStart.AppendChild($newGroup) | Out-Null

    $taskbarColl = $root.SelectSingleNode('//lm:CustomTaskbarLayoutCollection',$nsmgr)
    if (-not $taskbarColl) {
        $taskbarColl = $xml.CreateElement('CustomTaskbarLayoutCollection',$ns['lm'])
        $root.AppendChild($taskbarColl) | Out-Null
    }
    $taskbarColl.SetAttribute('PinListPlacement','Append')

    $taskbarLayout = $taskbarColl.SelectSingleNode('defaultlayout:TaskbarLayout',$nsmgr)
    if (-not $taskbarLayout) {
        $taskbarLayout = $xml.CreateElement('defaultlayout','TaskbarLayout',$ns['defaultlayout'])
        $taskbarColl.AppendChild($taskbarLayout) | Out-Null
    }

    $taskbarPinList = $taskbarLayout.SelectSingleNode('taskbar:TaskbarPinList',$nsmgr)
    if (-not $taskbarPinList) {
        $taskbarPinList = $xml.CreateElement('taskbar','TaskbarPinList',$ns['taskbar'])
        $taskbarLayout.AppendChild($taskbarPinList) | Out-Null
    }

    # Deduplicate against anything already in the base XML's taskbar pin list,
    # so a base template that already pins an app does not produce a duplicate.
    $existingTaskbarIds = @{}
    foreach ($existing in $taskbarPinList.ChildNodes) {
        if ($existing.Attributes -and $existing.Attributes['AppUserModelID']) {
            $existingTaskbarIds[$existing.Attributes['AppUserModelID'].Value] = $true
        }
        elseif ($existing.Attributes -and $existing.Attributes['DesktopApplicationLinkPath']) {
            $existingTaskbarIds[$existing.Attributes['DesktopApplicationLinkPath'].Value] = $true
        }
    }

    foreach ($pin in $TaskbarPins) {
        if ($existingTaskbarIds.ContainsKey($pin.Id)) { continue }

        if ($pin.Type -in @('Packaged','UWA','AUMID')) {
            $node = $xml.CreateElement('taskbar','UWA',$ns['taskbar'])
            $node.SetAttribute('AppUserModelID', $pin.Id)
        }
        elseif ($pin.Type -eq 'Desktop') {
            $node = $xml.CreateElement('taskbar','DesktopApp',$ns['taskbar'])
            $node.SetAttribute('DesktopApplicationLinkPath', $pin.Id)
        } else { continue }
        $taskbarPinList.AppendChild($node) | Out-Null
        $existingTaskbarIds[$pin.Id] = $true
    }

    return $xml.OuterXml
}

function Test-AutoApplyLayoutPresent {
    param([Parameter(Mandatory)] [string]$OSInfo)

    $dir = 'C:\Recovery\AutoApply'
    if ($OSInfo -eq 'Windows 10') {
        return (Test-Path (Join-Path $dir 'LayoutModification.xml') -PathType Leaf)
    }
    if ($OSInfo -eq 'Windows 11') {
        return ((Test-Path (Join-Path $dir 'LayoutModification.json') -PathType Leaf) -and
                (Test-Path (Join-Path $dir 'TaskbarLayoutModification.xml') -PathType Leaf))
    }
    return $false
}

function Get-SingleApplicationId {
    # Returns the sole application Id from an AppxManifest object, or $null
    # when the package exposes zero or multiple applications. Declining to
    # guess prevents the framework from pinning an arbitrary application
    # when a package has several and the correct one was not declared. A
    # package author who needs a specific app from a multi-app package
    # should declare Pinning.Id as a full AUMID.
    param($Manifest)

    if (-not $Manifest -or -not $Manifest.Package -or -not $Manifest.Package.Applications) {
        return $null
    }
    $apps = @($Manifest.Package.Applications.Application)
    if ($apps.Count -ne 1) { return $null }
    return [string]$apps[0].Id
}

function Resolve-AumidForPin {
    param(
        [string]$AppxPackageName,
        [string]$FallbackAUMID
    )

    if (-not [string]::IsNullOrWhiteSpace($AppxPackageName)) {
        try {
            # Anchor the identity match: exact identity or identity
            # followed by the "_" family-name separator. Substring
            # matching would also accept variant packages whose identity
            # contains the declared name (e.g. a "Preview" variant), and
            # a wrong match here would silently pin the wrong AUMID.
            $pkg = Get-AppxCache | Where-Object {
                $_.PackageFamilyName -eq $AppxPackageName -or
                $_.Name -eq $AppxPackageName -or
                $_.PackageFamilyName -like "${AppxPackageName}_*" -or
                $_.Name -like "${AppxPackageName}_*"
            } | Select-Object -First 1

            if ($pkg) {
                $manifest = Get-AppxPackageManifest $pkg -ErrorAction SilentlyContinue
                if ($manifest) {
                    $appId = Get-SingleApplicationId -Manifest $manifest
                    if ($appId) { return "$($pkg.PackageFamilyName)!$appId" }
                }
            }

            $provPkg = Get-CachedProvisionedPackages | Where-Object {
                $_.PackageName -eq $AppxPackageName -or
                $_.PackageName -like "${AppxPackageName}_*"
            } | Select-Object -First 1

            if ($provPkg -and -not [string]::IsNullOrWhiteSpace($provPkg.InstallLocation)) {
                $manifestPath = Join-Path $provPkg.InstallLocation 'AppxManifest.xml'
                if (Test-Path $manifestPath) {
                    try {
                        [xml]$provManifest = Get-Content $manifestPath -Raw
                        $appId = Get-SingleApplicationId -Manifest $provManifest
                        if ($appId) { return "$($provPkg.PackageFamilyName)!$appId" }
                    } catch {}
                }
            }
        } catch {}
    }

    # Dynamic resolution failed. Use the manifest's declared Pinning.Id only
    # when it is already a full AUMID (contains !). A bare package family
    # name cannot be used as an AUMID; returning it would produce a silently
    # broken pin. Decline instead of guessing.
    if (-not [string]::IsNullOrWhiteSpace($FallbackAUMID) -and $FallbackAUMID.Contains('!')) {
        return $FallbackAUMID
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackAUMID)) {
        Write-DeploymentLog -Message "AUMID resolution declined for '$AppxPackageName': dynamic resolution did not produce a usable AUMID and Pinning.Id '$FallbackAUMID' is not a full AUMID. Pin skipped." -Level WARN
    }
    return $null
}

function Get-FrameworkOutlookPin {
    # Universal taskbar pin owned by the framework. Outlook is deployed
    # on every image the framework supports (baked in or installed by
    # pre.ps1), so the framework supplies the Outlook pin directly
    # instead of every OEM module declaring an identical helper. Modules
    # that want additional non-Outlook pins may still supply
    # GetAdditionalTaskbarPins; the framework merges their output after
    # the Outlook pin. Returns $null when Outlook is not detected — the
    # framework never emits a broken pin with an unresolvable AUMID.
    if (-not (Test-ApplicationInstalled -AppName 'Microsoft.OutlookForWindows' -AppxPackageName 'Microsoft.OutlookForWindows')) {
        return $null
    }
    $aumid = Resolve-AumidForPin `
        -AppxPackageName 'Microsoft.OutlookForWindows' `
        -FallbackAUMID   'Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'
    if (-not $aumid) { return $null }
    return [pscustomobject]@{ Type = 'Packaged'; Id = $aumid }
}

function Get-EligiblePins {
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [string]$SystemFamily,
        [Parameter(Mandatory)] [string]$OSInfo
    )

    # Framework-supplied universal pins plus any profile-hook pins sort
    # first on the taskbar and never appear on Start. Collect them
    # separately so pin-priority sorting of manifest pins cannot
    # displace them.
    #
    # Outlook is framework-owned: it is part of every deployed image, so
    # the framework supplies it directly (Get-FrameworkOutlookPin) rather
    # than every OEM module declaring an identical hook. Modules that
    # want to add OEM-specific pins beyond Outlook may still supply
    # GetAdditionalTaskbarPins; the framework merges their output after
    # the Outlook pin.
    $profileTaskbarPins = New-Object System.Collections.ArrayList

    $outlookPin = Get-FrameworkOutlookPin
    if ($outlookPin) {
        $null = $profileTaskbarPins.Add(@{ Type = $outlookPin.Type; Id = $outlookPin.Id })
    }

    $extra = Invoke-ProfileHook -Profile $Context.Profile -HookName 'GetAdditionalTaskbarPins' -Parameters @{ Context = $Context }
    if ($extra) {
        foreach ($p in @($extra)) {
            if ($p -and $p.Id) {
                $null = $profileTaskbarPins.Add(@{ Type = $p.Type; Id = $p.Id })
            }
        }
    }

    # Collect eligible manifest pin candidates with the metadata needed
    # for sorting: PinPriority (rank) and ManifestIndex (stable tiebreak).
    # Eligibility is evaluated here, before sorting, so an ineligible app
    # with a low PinPriority does not leave a gap — the next eligible pin
    # takes its place.
    $candidates = [System.Collections.Generic.List[object]]::new()
    $manifestIndex = 0
    foreach ($app in $Context.Manifest.apps) {
        $idx = $manifestIndex
        $manifestIndex++

        if (-not $app.Pinning -or -not $app.Pinning.Type) { continue }

        if (-not (Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestStaticEligibility' -Parameters @{ App = $app; SystemFamily = $SystemFamily })) { continue }
        if (-not (Invoke-ProfileBoolHook -Profile $Context.Profile -HookName 'TestDynamicEligibility' -Parameters @{ App = $app; Context = $Context })) { continue }

        if (-not (Test-AppPresence -Context $Context -App $app)) { continue }

        $taskbarWanted = [bool]$app.Pinning.Taskbar
        # A PinPriority declared as JSON null should sort last, same as
        # unset. PSObject.Properties['PinPriority'] is true whenever the
        # key exists, so [int]$null would otherwise evaluate to 0 and
        # sort the pin first.
        $pinPriority = if ($app.Pinning.PSObject.Properties['PinPriority'] -and $null -ne $app.Pinning.PinPriority) {
            [int]$app.Pinning.PinPriority
        } else {
            [int]::MaxValue
        }

        if ($app.Pinning.Type -eq 'AUMID') {
            # If the profile supplies ResolvePinAumid, call it. It is expected
            # to do its own full resolution (dynamic, breadcrumb file, static)
            # and return the AUMID to pin. Otherwise use the framework default.
            $aumid = $null
            $pinHook = $Context.Profile.ResolvePinAumid
            if ($pinHook) {
                $aumid = & $pinHook $app $Context $app.Pinning.Id
            }
            if (-not $aumid) {
                $aumid = Resolve-AumidForPin -AppxPackageName $app.AppxPackageName -FallbackAUMID $app.Pinning.Id
            }
            if ($aumid) {
                $null = $candidates.Add([pscustomobject]@{
                    Type          = 'Packaged'
                    Id            = $aumid
                    PinPriority   = $pinPriority
                    ManifestIndex = $idx
                    Taskbar       = $taskbarWanted
                })
            }
        }
        elseif ($app.Pinning.Type -eq 'Desktop') {
            $lnk = [Environment]::ExpandEnvironmentVariables($app.Pinning.Id)
            if (Test-Path $lnk) {
                $null = $candidates.Add([pscustomobject]@{
                    Type          = 'Desktop'
                    Id            = $lnk
                    PinPriority   = $pinPriority
                    ManifestIndex = $idx
                    Taskbar       = $taskbarWanted
                })
            }
        }
    }

    # Sort by PinPriority ascending, then ManifestIndex ascending. Unset
    # PinPriority carries [int]::MaxValue, so unprioritized pins sort after
    # any explicitly prioritized pins, preserving manifest order among
    # themselves. This is a rank, not a slot: an ineligible app is simply
    # absent from the candidates list, and the next eligible pin takes its
    # effective position.
    $sortedCandidates = @($candidates | Sort-Object -Property PinPriority, ManifestIndex)

    # Distribute. Start receives every sorted candidate. Taskbar receives
    # the profile-hook pins first (Outlook and any other profile-supplied
    # pins), then sorted manifest candidates that declare Taskbar:true, up
    # to the 3-pin cap. Cap enforcement happens during distribution so it
    # always sees the sorted order.
    $start   = New-Object System.Collections.ArrayList
    $taskbar = New-Object System.Collections.ArrayList

    foreach ($p in $profileTaskbarPins) {
        if ($taskbar.Count -lt 3) {
            $null = $taskbar.Add($p)
        }
    }
    foreach ($c in $sortedCandidates) {
        $null = $start.Add(@{ Type = $c.Type; Id = $c.Id })
        if ($c.Taskbar -and $taskbar.Count -lt 3) {
            $null = $taskbar.Add(@{ Type = $c.Type; Id = $c.Id })
        }
    }

    # Start cap is defense-in-depth against future manifests exceeding
    # Windows' practical tile-group limits. Taskbar cap is already enforced
    # during distribution above.
    if ($start.Count -gt 12) { $start = New-Object System.Collections.ArrayList (,$start[0..11]) }

    return @{ StartPins = $start; TaskbarPins = $taskbar }
}

function Invoke-LayoutGeneration {
    param(
        [Parameter(Mandatory)] [psobject]$Context,
        [Parameter(Mandatory)] [string]$SystemFamily,
        [Parameter(Mandatory)] [string]$OSInfo,
        [Parameter(Mandatory)] [string]$Phase   # 'SYSTEM' or 'USER'
    )

    if ($OSInfo -notin @('Windows 10','Windows 11')) {
        Write-DeploymentLog -Message "Unrecognized OS '$OSInfo'; layout responsibility deemed satisfied." -Level WARN
        return $true
    }

    $autoApplyPresent = Test-AutoApplyLayoutPresent -OSInfo $OSInfo
    if ($autoApplyPresent) {
        Write-DeploymentLog -Message "$Phase layout: AutoApply owns layout; PBR walks away." -Level INFO
        return $true
    }

    Write-DeploymentLog -Message "$Phase layout: framework owns layout; writing layout files." -Level INFO

    # Settle window: AppX registration latency after the last install.
    Clear-ApplicationCaches
    Start-Sleep -Seconds 10

    $pins = Get-EligiblePins -Context $Context -SystemFamily $SystemFamily -OSInfo $OSInfo

    $shellDirDefault = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell'
    if (-not (Test-Path $shellDirDefault)) {
        New-Item -Path $shellDirDefault -ItemType Directory -Force | Out-Null
    }

    $updateCurrentUser = ($Phase -eq 'USER') -and (-not $Context.IsSystem)
    $shellDirCurrent = $null
    if ($updateCurrentUser) {
        $shellDirCurrent = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
        if (-not (Test-Path $shellDirCurrent)) {
            New-Item -Path $shellDirCurrent -ItemType Directory -Force | Out-Null
        }
    }

    $brandName = $Context.Profile.Name

    if ($OSInfo -eq 'Windows 10') {
        $basePath = 'C:\Recovery\OEM\LayoutModification.xml'
        if (-not (Test-Path $basePath)) {
            Write-DeploymentLog -Message "Windows 10 base template missing at $basePath; layout fails closed." -Level ERROR
            return $false
        }
        $tempFile = Join-Path $env:TEMP "PBR_Layout_$PID.xml"
        try {
            Copy-Item -Path $basePath -Destination $tempFile -Force
            $mergedXml = Merge-Win10Layout -BrandName $brandName -StartPins $pins.StartPins -TaskbarPins $pins.TaskbarPins -BasePath $tempFile
        } finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        if (-not $mergedXml) {
            Write-DeploymentLog -Message 'Windows 10 layout merge failed.' -Level ERROR
            return $false
        }
        try {
            $null = Write-ContentIfDifferent -Path (Join-Path $shellDirDefault 'LayoutModification.xml') -DesiredContent $mergedXml
            if ($shellDirCurrent) {
                $null = Write-ContentIfDifferent -Path (Join-Path $shellDirCurrent 'LayoutModification.xml') -DesiredContent $mergedXml
            }
            return $true
        } catch {
            Write-DeploymentLog -Message "Windows 10 layout write failed: $($_.Exception.Message)" -Level ERROR
            return $false
        }
    }

    # Windows 11 (top guard guarantees this is the only remaining case).
    $jsonContent = New-Win11StartLayoutJson -Pins $pins.StartPins
    $xmlContent  = New-Win11TaskbarLayoutXml -Pins $pins.TaskbarPins

    $oemTaskbarPath = 'C:\Windows\OEM\TaskbarLayoutModification.xml'
    if (-not (Test-Path 'C:\Windows\OEM')) {
        New-Item -Path 'C:\Windows\OEM' -ItemType Directory -Force | Out-Null
    }

    try {
        $null = Write-ContentIfDifferent -Path (Join-Path $shellDirDefault 'LayoutModification.json') -DesiredContent $jsonContent
        $null = Write-ContentIfDifferent -Path $oemTaskbarPath -DesiredContent $xmlContent

        $layoutXmlPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'LayoutXMLPath' -ErrorAction SilentlyContinue).LayoutXMLPath
        if ($layoutXmlPath -ne $oemTaskbarPath) {
            $null = Set-RegistryValueSilent -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'LayoutXMLPath' -Value $oemTaskbarPath -Type 'String'
        }
        $verify = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'LayoutXMLPath' -ErrorAction SilentlyContinue).LayoutXMLPath
        if ($verify -ne $oemTaskbarPath) {
            Write-DeploymentLog -Message "LayoutXMLPath verification failed (expected '$oemTaskbarPath', got '$verify')." -Level ERROR
            return $false
        }

        $null = Write-ContentIfDifferent -Path (Join-Path $shellDirDefault 'TaskbarLayoutModification.xml') -DesiredContent $xmlContent
        if ($shellDirCurrent) {
            $null = Write-ContentIfDifferent -Path (Join-Path $shellDirCurrent 'LayoutModification.json') -DesiredContent $jsonContent
            $null = Write-ContentIfDifferent -Path (Join-Path $shellDirCurrent 'TaskbarLayoutModification.xml') -DesiredContent $xmlContent
        }
        return $true
    } catch {
        Write-DeploymentLog -Message "Windows 11 layout write failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

Export-ModuleMember -Function `
    Write-Utf8NoBomFile, `
    Write-ContentIfDifferent, `
    New-Win11StartLayoutJson, `
    New-Win11TaskbarLayoutXml, `
    Merge-Win10Layout, `
    Test-AutoApplyLayoutPresent, `
    Resolve-AumidForPin, `
    Get-EligiblePins, `
    Invoke-LayoutGeneration
