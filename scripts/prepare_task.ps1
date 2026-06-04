<#
.SYNOPSIS
    Preparation script run at the very start of each scheduled Claude Cowork task.
    Guarantees a live Monarch Money session, writes a status file, and logs.

.DESCRIPTION
    This is the script Windows Task Scheduler invokes first (before Cowork). It:
      1. Loads the task definition from config/tasks.config.json.
      2. Refreshes / validates the Monarch session (token fast-path → Playwright).
      3. Writes status/task_status.<TaskName>.json (and task_status.json).
      4. Logs to logs/ and sends a failure notification if configured.

    It does NOT launch Cowork — Launch-ClaudeCowork.ps1 (or the scheduled task's
    second action) does that, only after this script exits 0.

.PARAMETER TaskName
    One of the task keys in tasks.config.json (Paycheck, R1Transfer,
    TelegramCommission, StudentLoan).

.PARAMETER Interactive
    Run the browser headful — use for first-time priming or debugging.

.PARAMETER ForceBrowser
    Skip the token fast path and always validate via the browser.

.EXAMPLE
    pwsh -File .\scripts\prepare_task.ps1 -TaskName Paycheck

.EXAMPLE
    pwsh -File .\scripts\prepare_task.ps1 -TaskName StudentLoan -Interactive

.OUTPUTS
    Exit code 0 = session ready; non-zero = preparation failed (Cowork must not run).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Paycheck','R1Transfer','TelegramCommission','StudentLoan')]
    [string]$TaskName,

    [switch]$Interactive,
    [switch]$ForceBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot\Common.psm1" -Force
. "$PSScriptRoot\Refresh-MonarchSession.ps1"   # dot-source for Invoke-MonarchSessionRefresh

$logFile = Initialize-Log -TaskName $TaskName
$task    = Get-TaskDefinition -TaskName $TaskName
$status  = New-StatusObject -TaskName $TaskName -DisplayName $task.displayName

Write-Log "=== Preparing task '$($task.displayName)' [$TaskName] (runId $($status.runId)) ===" -Level Info

try {
    if (-not $task.requiresMonarchSession) {
        Write-Log "Task does not require a Monarch session; marking ready." -Level Info
        $status.success = $true
        $status.session.state = 'fresh'
        $status.session.method = 'n/a'
        $status.session.wasStale = $false
    }
    else {
        $refresh = Invoke-MonarchSessionRefresh -Interactive:$Interactive -ForceBrowser:$ForceBrowser
        $status.session.state            = $refresh.State
        $status.session.method           = $refresh.Method
        $status.session.wasStale         = $refresh.WasStale
        $status.session.lastValidatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        $status.success                  = [bool]$refresh.Ok

        if ($refresh.Ok) {
            Write-Log "Session ready ($($refresh.State) via $($refresh.Method)). $($refresh.Detail)" -Level Info
        } else {
            $status.errors += $refresh.Detail
            Write-Log "Session preparation FAILED: $($refresh.Detail)" -Level Error
        }
    }
}
catch {
    $status.success = $false
    $status.session.state = 'stale-failed'
    $status.errors += $_.Exception.Message
    Write-Log "Unhandled error during preparation: $($_.Exception.Message)" -Level Error
    Write-Log $_.ScriptStackTrace -Level Debug
}
finally {
    $status.completedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $statusPath = Write-TaskStatus -Status $status
    Write-Log "Status written to $statusPath" -Level Info
}

if ($status.success) {
    Send-Notification -Severity Success -Title "✅ $($task.displayName): session ready" `
        -Message "Monarch session $($status.session.state) via $($status.session.method)."
    Write-Log "=== Preparation complete: SUCCESS ===" -Level Info
    exit 0
} else {
    $detail = ($status.errors -join '; ')
    Send-Notification -Severity Failure -Title "❌ $($task.displayName): preparation failed" `
        -Message "Cowork was NOT launched. Reason: $detail. Log: $logFile"
    Write-Log "=== Preparation complete: FAILURE ===" -Level Error
    exit 1
}
