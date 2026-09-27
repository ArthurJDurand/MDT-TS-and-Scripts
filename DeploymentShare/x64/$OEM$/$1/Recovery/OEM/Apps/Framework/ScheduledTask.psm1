<#
.SYNOPSIS
    Vendor-neutral scheduled-task lifecycle for phase-2 resume.
#>

function Register-ResumeTask {
    param(
        [Parameter(Mandatory)] [string]$TaskName,
        [Parameter(Mandatory)] [string]$ScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        Write-DeploymentLog -Message 'Register-ResumeTask: script path is empty; refusing to register.' -Level ERROR
        return $false
    }

    # Protect a valid task from unnecessary replacement. If an equivalent
    # task already exists and passes verification, leave it alone. The
    # unregister-then-register path below is only taken when no valid task
    # is present, so a valid task is never destroyed in pursuit of a
    # replacement. The register-then-verify sequence for invalid or missing
    # tasks is not atomic; verification is what catches a failed
    # registration. The SYSTEM->USER handoff depends on this task, so its
    # absence is a hard failure.
    if (Test-ResumeTask -TaskName $TaskName -ScriptPath $ScriptPath) {
        return $true
    }

    # Existing task is either absent or invalid. Remove a stale entry
    # before registering the replacement.
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    try {
        # conhost.exe --headless launches the child process with no console
        # window at all, avoiding the brief flash that -WindowStyle Hidden
        # produces while Windows creates-then-hides the console. Available on
        # Windows 10 1809+.
        $action = New-ScheduledTaskAction -Execute 'conhost.exe' `
            -Argument "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-544' -RunLevel Highest
        # -AllowStartIfOnBatteries and -DontStopIfGoingOnBatteries are both
        # required. New-ScheduledTaskSettingsSet defaults to disallowing
        # start on battery and to stopping when AC is removed. A resume task
        # that silently fails to fire because the laptop is unplugged is a
        # hard deployment failure: the machine never advances past
        # SYSTEM_DONE. Explicitly permit both.
        $settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null

        return (Test-ResumeTask -TaskName $TaskName -ScriptPath $ScriptPath)
    }
    catch {
        Write-DeploymentLog -Message "Failed to register '$TaskName': $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-ResumeTask {
    param(
        [Parameter(Mandatory)] [string]$TaskName,
        [string]$ScriptPath = ''
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $false }

    $actionOK = $task.Actions.Count -gt 0 -and $task.Actions[0].Execute -eq 'conhost.exe'

    # Confirm the trigger is specifically AtLogOn, not merely "some trigger".
    $triggerOK = $false
    foreach ($trigger in $task.Triggers) {
        if ($trigger.CimClass -and $trigger.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger') {
            $triggerOK = $true
            break
        }
    }

    $principalOK = $task.Principal -and $task.Principal.RunLevel -eq 'Highest'

    # Task settings: a resume task that refuses to start on battery, or
    # stops when AC is removed, is functionally broken on laptops. The
    # framework registers it with these both disabled; verify the live
    # task matches so a stale registration with the older defaults is
    # replaced on the next SYSTEM phase.
    $batteryOK = -not $task.Settings.DisallowStartIfOnBatteries -and -not $task.Settings.StopIfGoingOnBatteries

    $scriptOK = $true
    if ($ScriptPath) {
        $taskArgs = $task.Actions[0].Arguments
        $scriptOK = $taskArgs -and ($taskArgs.IndexOf($ScriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    }

    return ($actionOK -and $triggerOK -and $principalOK -and $batteryOK -and $scriptOK)
}

function Unregister-ResumeTask {
    param([Parameter(Mandatory)] [string]$TaskName)

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-DeploymentLog -Message "Scheduled task '$TaskName' removed." -Level INFO
    }
}

Export-ModuleMember -Function Register-ResumeTask, Test-ResumeTask, Unregister-ResumeTask
