<#
.SYNOPSIS
    Creates/updates the 4 Windows Scheduled Tasks from config/tasks.config.json.

.DESCRIPTION
    For each enabled task, registers a Scheduled Task named "ClaudeCowork-<Name>"
    that runs Launch-ClaudeCowork.ps1 -TaskName <Name>. That launcher runs the
    preparation script first and only opens Cowork if the Monarch session is live.

    Triggers are built from each task's "schedule" block (Daily or Weekly + time).

    Run from an elevated PowerShell. Review tasks.config.json BEFORE running.
    Use -WhatIf to preview without registering, or -Remove to delete the tasks.

.PARAMETER Remove
    Unregister the ClaudeCowork-* tasks instead of creating them.

.PARAMETER RunWithHighestPrivileges
    Register tasks to run elevated (off by default).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,
    [switch]$RunWithHighestPrivileges
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$([IO.Path]::Combine((Split-Path -Parent $PSScriptRoot),'scripts','Common.psm1'))" -Force

$root      = Get-AutomationRoot
$cfg       = Get-TasksConfig
$launcher  = Join-Path $root 'scripts\Launch-ClaudeCowork.ps1'
$pwsh      = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }  # fall back to Windows PowerShell

foreach ($task in $cfg.tasks) {
    $taskName = "ClaudeCowork-$($task.name)"

    if ($Remove) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($taskName, 'Unregister')) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "Removed $taskName" -ForegroundColor Yellow
            }
        }
        continue
    }

    if (-not $task.enabled) { Write-Host "Skipping disabled task: $($task.name)"; continue }

    # Action: pwsh -NoProfile -ExecutionPolicy Bypass -File <launcher> -TaskName <Name>
    $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -TaskName $($task.name)"
    $action  = New-ScheduledTaskAction -Execute $pwsh -Argument $argLine -WorkingDirectory $root

    # Trigger from schedule block.
    $s = $task.schedule
    $at = [datetime]::ParseExact($s.atTime, 'HH:mm', $null)
    switch ($s.frequency) {
        'Daily'  { $trigger = New-ScheduledTaskTrigger -Daily -At $at }
        'Weekly' {
            $days = $s.daysOfWeek
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $at
        }
        default  { throw "Unsupported frequency '$($s.frequency)' for task $($task.name)." }
    }

    $settingsSet = New-ScheduledTaskSettingsSet -StartWhenAvailable `
        -DontStopOnIdleEnd -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5) `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    $principalArgs = @{ UserId = "$env:USERDOMAIN\$env:USERNAME"; LogonType = 'Interactive' }
    if ($RunWithHighestPrivileges) { $principalArgs.RunLevel = 'Highest' }
    $principal = New-ScheduledTaskPrincipal @principalArgs

    $desc = "Claude Cowork: $($task.displayName). Refreshes Monarch session, then launches Cowork. $($task.notes)"

    if ($PSCmdlet.ShouldProcess($taskName, "Register ($($s.frequency) @ $($s.atTime))")) {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settingsSet -Principal $principal -Description $desc -Force | Out-Null
        Write-Host "Registered $taskName — $($s.frequency) @ $($s.atTime)" -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Inspect with:  Get-ScheduledTask -TaskName ClaudeCowork-* | Format-Table TaskName,State'
Write-Host 'Test now with: Start-ScheduledTask -TaskName ClaudeCowork-Paycheck'
