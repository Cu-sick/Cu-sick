<#
.SYNOPSIS
    Dry-run and diagnostics for the preparation pipeline.

.DESCRIPTION
    Verifies prerequisites, credential availability, TOTP generation, the token
    fast path, and (optionally) a full Playwright validation — without launching
    Cowork. Use this before registering scheduled tasks and whenever a task starts
    failing.

.EXAMPLE
    pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck
    pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck -Browser -Interactive
#>
[CmdletBinding()]
param(
    [ValidateSet('Paycheck','R1Transfer','TelegramCommission','StudentLoan')]
    [string]$TaskName = 'Paycheck',
    [switch]$Browser,        # also run the Playwright validation path
    [switch]$Interactive     # run Playwright headful
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$scripts = [IO.Path]::Combine((Split-Path -Parent $PSScriptRoot),'scripts')
Import-Module (Join-Path $scripts 'Common.psm1') -Force

$pass = 0; $fail = 0; $warn = 0
function Check($name, [scriptblock]$test) {
    try {
        $r = & $test
        if ($r -eq $true)      { Write-Host "  [PASS] $name" -ForegroundColor Green; $script:pass++ }
        elseif ($r -eq 'warn') { Write-Host "  [WARN] $name" -ForegroundColor Yellow; $script:warn++ }
        else                   { Write-Host "  [FAIL] $name -> $r" -ForegroundColor Red; $script:fail++ }
    } catch { Write-Host "  [FAIL] $name -> $($_.Exception.Message)" -ForegroundColor Red; $script:fail++ }
}

Initialize-Log -TaskName "test-$TaskName" | Out-Null
Write-Host "== Preparation diagnostics for '$TaskName' ==" -ForegroundColor Cyan

Write-Host "`n[1] Environment" -ForegroundColor Cyan
Check 'Node.js on PATH'        { if (Get-Command node -ErrorAction SilentlyContinue) { $true } else { 'node not found' } }
Check 'Playwright installed'   { if (Test-Path (Join-Path (Get-AutomationRoot) 'node_modules\playwright')) { $true } else { 'run install-prerequisites.ps1' } }
Check 'CredentialManager module' { if (Get-Module -ListAvailable -Name CredentialManager) { $true } else { 'warn' } }
Check 'BurntToast module'      { if (Get-Module -ListAvailable -Name BurntToast) { $true } else { 'warn' } }

Write-Host "`n[2] Config & task" -ForegroundColor Cyan
Check 'settings.config.json loads' { Get-Settings | Out-Null; $true }
Check "task '$TaskName' defined"   { Get-TaskDefinition -TaskName $TaskName | Out-Null; $true }
$task = Get-TaskDefinition -TaskName $TaskName
Check 'prompt file exists'         { if (Test-Path (Join-Path (Get-AutomationRoot) $task.promptFile)) { $true } else { "missing $($task.promptFile)" } }

Write-Host "`n[3] Credentials" -ForegroundColor Cyan
$creds = Resolve-MonarchCredentials
Check 'Monarch email resolved'    { if ($creds.Email) { $true } else { 'not set — run Set-MonarchCredentials.ps1' } }
Check 'Monarch password resolved' { if ($creds.Password) { $true } else { 'not set' } }
Check 'MFA secret resolved'       { if ($creds.MfaSecret) { $true } else { 'warn' } }
Check 'TOTP generates'            { if ($creds.MfaSecret) { Get-TotpCode -Secret $creds.MfaSecret | Out-Null; $true } else { 'warn' } }
Check 'Token present (fast path)' { if ($creds.Token) { $true } else { 'warn' } }

Write-Host "`n[4] Session" -ForegroundColor Cyan
if ($creds.Token) {
    . (Join-Path $scripts 'Refresh-MonarchSession.ps1')
    Check 'Token validates via GraphQL' { if (Test-MonarchToken -Token $creds.Token) { $true } else { 'token stale/invalid' } }
}
if ($Browser) {
    Write-Host "  Running Playwright validation (this opens a browser)..." -ForegroundColor DarkGray
    . (Join-Path $scripts 'Refresh-MonarchSession.ps1')
    $res = Invoke-MonarchSessionRefresh -Interactive:$Interactive -ForceBrowser
    Check 'Browser session usable' { if ($res.Ok) { $true } else { $res.Detail } }
}

Write-Host "`n== Result: $pass passed, $warn warnings, $fail failed ==" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if ($fail -gt 0) { exit 1 } else { exit 0 }
