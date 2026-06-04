<#
.SYNOPSIS
    Runs preparation, then launches Claude Cowork with the task's main prompt.

.DESCRIPTION
    This is the single command a scheduled task can call. It:
      1. Runs prepare_task.ps1 -TaskName <Task>.
      2. If preparation succeeds, resolves the Cowork executable and delivers the
         task's main prompt (prompts/<task>.md) to Cowork.
      3. If preparation fails, does NOT launch Cowork (the failure notification
         from prepare_task.ps1 already fired).

    HOW THE PROMPT REACHES COWORK is environment-specific. Claude Cowork Desktop
    does not (yet) expose a stable, documented "open with this prompt" CLI flag,
    so this script supports two delivery modes (settings.cowork.promptDelivery):

      "file"  (default, safest): writes the resolved prompt to an outbox file and
              launches Cowork. The Cowork task itself is configured (once) to read
              its main prompt from that outbox path. See docs/COWORK_INTEGRATION.md.

      "clipboard": copies the prompt to the clipboard and launches Cowork, so you
              (or a Cowork macro) can paste it.

    Treat the launch arguments as a seam to adjust once Cowork's automation surface
    is confirmed on your machine — this is the "language to be inserted into the
    Cowork skill" the project is preparing for.

.PARAMETER TaskName
    Task key (Paycheck, R1Transfer, TelegramCommission, StudentLoan).

.PARAMETER PrepareOnly
    Run preparation and prompt staging but do not launch the Cowork executable.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Paycheck','R1Transfer','TelegramCommission','StudentLoan')]
    [string]$TaskName,

    [switch]$PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

$settings = Get-Settings
$task     = Get-TaskDefinition -TaskName $TaskName
$root     = Get-AutomationRoot

# 1. Preparation gate ───────────────────────────────────────────────────────
Write-Log "Launcher: running preparation for '$($task.displayName)'." -Level Info
& "$PSScriptRoot\prepare_task.ps1" -TaskName $TaskName
$prepExit = $LASTEXITCODE
if ($prepExit -ne 0) {
    Write-Log "Preparation failed (exit $prepExit). Not launching Cowork." -Level Error
    exit $prepExit
}

# 2. Resolve & stage the main prompt ─────────────────────────────────────────
$promptPath = Join-Path $root $task.promptFile
if (-not (Test-Path $promptPath)) { throw "Prompt file not found: $promptPath" }

$statusPath = Join-Path (Expand-ConfigPath $settings.paths.status) ("task_status.{0}.json" -f $TaskName)

# Make the status path explicit at the top of the delivered prompt so Cowork
# always knows where to read preparation results from.
$header = @"
<!-- AUTO-GENERATED PROMPT HEADER — do not edit by hand -->
<!-- Task: $($task.displayName)  |  Generated: $(Get-Date -Format o) -->
<!-- Preparation status file: $statusPath -->

"@
$promptBody = Get-Content -Raw -LiteralPath $promptPath
# Literal String.Replace (not -replace): the status path is a Windows path with
# backslashes, which a regex replacement string would mangle.
$resolved = $header + $promptBody.Replace('{{STATUS_FILE}}', $statusPath)

$delivery = $settings.cowork.promptDelivery
switch ($delivery) {
    'file' {
        $outDir = Expand-ConfigPath $settings.cowork.promptDropDir
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $outFile = Join-Path $outDir ("{0}.prompt.md" -f $TaskName)
        Set-Content -LiteralPath $outFile -Value $resolved -Encoding UTF8
        Write-Log "Prompt staged to $outFile" -Level Info
    }
    'clipboard' {
        try { Set-Clipboard -Value $resolved; Write-Log "Prompt copied to clipboard." -Level Info }
        catch { Write-Log "Clipboard delivery failed: $($_.Exception.Message)" -Level Warn }
    }
    default { Write-Log "Unknown promptDelivery '$delivery'; prompt not staged." -Level Warn }
}

if ($PrepareOnly) {
    Write-Log "PrepareOnly set; skipping Cowork launch." -Level Info
    exit 0
}

# 3. Launch Cowork ───────────────────────────────────────────────────────────
$exe = $null
foreach ($cand in $settings.cowork.exePathCandidates) {
    $expanded = Expand-ConfigPath $cand
    if (Test-Path $expanded) { $exe = $expanded; break }
}
if (-not $exe) {
    Write-Log "Claude Cowork executable not found in configured candidates. Prompt is staged; launch manually or fix settings.cowork.exePathCandidates." -Level Warn
    exit 0
}

$launchArgs = @($settings.cowork.launchArgs) | Where-Object { $_ }
Write-Log "Launching Cowork: $exe $($launchArgs -join ' ')" -Level Info
Start-Process -FilePath $exe -ArgumentList $launchArgs
Write-Log "Cowork launched for '$($task.displayName)'." -Level Info
exit 0
