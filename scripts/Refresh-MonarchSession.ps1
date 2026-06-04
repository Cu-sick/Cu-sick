<#
.SYNOPSIS
    Ensures a live Monarch Money session, cheapest method first.

.DESCRIPTION
    Layer 1 (fast path):  validate a saved bearer token via a GraphQL `me` query.
    Layer 2 (browser):    Playwright loads the saved storageState and checks the UI;
                          if stale, performs a full email + password + TOTP re-auth
                          and saves a fresh storageState for Cowork's browser to reuse.

    Returns a hashtable: @{ Ok; State; Method; WasStale; Detail }
      State : fresh | refreshed | reauthenticated | stale-failed
      Method: token-validate | playwright-validate | playwright-reauth

.NOTES
    Imported and called by prepare_task.ps1. Can also be run standalone for testing:
        pwsh -File .\scripts\Refresh-MonarchSession.ps1 -Interactive
#>
[CmdletBinding()]
param(
    [switch]$Interactive,        # run the browser headful (for first-time / debugging)
    [switch]$ForceBrowser        # skip the token fast path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

function Test-MonarchToken {
    <# Fast path: returns $true if the bearer token still authenticates. #>
    param([Parameter(Mandatory)][string]$Token)
    $settings = Get-Settings
    $headers = @{
        'Authorization' = "Token $Token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }
    # Minimal authenticated query. `me` exists on Monarch's schema; any 200 with
    # non-error JSON means the token is live.
    $body = @{ query = 'query { me { id email } }' } | ConvertTo-Json
    foreach ($url in @($settings.monarch.graphqlUrl, $settings.monarch.graphqlFallbackUrl)) {
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 20
            if ($resp -and -not $resp.errors) {
                Write-Log "Token fast-path validated against $url." -Level Info
                return $true
            }
            Write-Log "Token rejected by $url (errors present)." -Level Debug
        } catch {
            Write-Log "Token check against $url failed: $($_.Exception.Message)" -Level Debug
        }
    }
    return $false
}

function Invoke-PlaywrightSession {
    param(
        [Parameter(Mandatory)][ValidateSet('validate','refresh')][string]$Command,
        [Parameter(Mandatory)][hashtable]$Creds,
        [switch]$Headful
    )
    $settings   = Get-Settings
    $root       = Get-AutomationRoot
    $script     = Join-Path $PSScriptRoot 'monarch-session.mjs'
    $statePath  = Expand-ConfigPath $settings.paths.storageState
    $settingsPath = Join-Path $root 'config\settings.config.json'

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "Node.js not found on PATH. Run tools\install-prerequisites.ps1."
    }

    # Secrets are passed via the child process environment, never on the arg line.
    $env:MONARCH_EMAIL      = $Creds.Email
    $env:MONARCH_PASSWORD   = $Creds.Password
    $env:MONARCH_MFA_SECRET = $Creds.MfaSecret
    $env:MM_STATE_PATH      = $statePath
    $env:MM_SETTINGS_PATH   = $settingsPath
    $env:MM_HEADLESS        = if ($Headful) { 'false' } else { 'true' }

    try {
        Write-Log "Invoking Playwright '$Command' (headless=$($env:MM_HEADLESS))." -Level Info
        $raw = & node $script $Command 2>&1
        $exit = $LASTEXITCODE
        # The last non-empty line is the JSON result; earlier lines are diagnostics.
        $jsonLine = ($raw | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
        $parsed = if ($jsonLine) { $jsonLine | ConvertFrom-Json } else { $null }
        return [pscustomobject]@{ ExitCode = $exit; Result = $parsed; Raw = ($raw -join "`n") }
    }
    finally {
        # Scrub secrets from this process's environment promptly.
        Remove-Item Env:MONARCH_EMAIL, Env:MONARCH_PASSWORD, Env:MONARCH_MFA_SECRET -ErrorAction SilentlyContinue
    }
}

function Invoke-MonarchSessionRefresh {
    [CmdletBinding()]
    param([switch]$Interactive, [switch]$ForceBrowser)

    $settings = Get-Settings
    $creds = Resolve-MonarchCredentials

    if (-not $creds.Email -or -not $creds.Password) {
        return @{ Ok = $false; State = 'stale-failed'; Method = 'none'; WasStale = $true
                  Detail = 'Monarch email/password not available. Run tools\Set-MonarchCredentials.ps1.' }
    }

    # ── Layer 1: token fast path ──────────────────────────────────────────
    if (-not $ForceBrowser -and -not $settings.session.forceBrowserValidate -and $creds.Token) {
        if (Test-MonarchToken -Token $creds.Token) {
            return @{ Ok = $true; State = 'fresh'; Method = 'token-validate'; WasStale = $false
                      Detail = 'Saved token authenticated via GraphQL.' }
        }
        Write-Log "Token fast-path failed; falling back to browser validation." -Level Warn
    }

    # ── Layer 2: browser validate, then re-auth if needed ────────────────
    $pw = Invoke-PlaywrightSession -Command 'refresh' -Creds $creds -Headful:$Interactive

    if (-not $pw.Result) {
        Write-Log "Playwright produced no parseable result. Raw:`n$($pw.Raw)" -Level Error
        return @{ Ok = $false; State = 'stale-failed'; Method = 'playwright-reauth'; WasStale = $true
                  Detail = 'Playwright helper returned no result. See log.' }
    }

    $r = $pw.Result
    if ($r.loggedIn) {
        if ($r.action -eq 'reauthenticated') {
            return @{ Ok = $true; State = 'reauthenticated'; Method = 'playwright-reauth'; WasStale = $true
                      Detail = 'Stale session detected; re-authenticated and saved fresh storageState.' }
        }
        return @{ Ok = $true; State = 'refreshed'; Method = 'playwright-validate'; WasStale = [bool]$r.wasStale
                  Detail = 'Existing storageState validated and refreshed.' }
    }

    $reason = if ($r.error) { $r.error } else { 'unknown' }
    return @{ Ok = $false; State = 'stale-failed'; Method = 'playwright-reauth'; WasStale = $true
              Detail = ("Session refresh failed: {0}" -f $reason) }
}

# If run directly (not dot-sourced), execute and print a result.
if ($MyInvocation.InvocationName -ne '.') {
    Initialize-Log -TaskName 'session'
    $res = Invoke-MonarchSessionRefresh -Interactive:$Interactive -ForceBrowser:$ForceBrowser
    $res | ConvertTo-Json
    if (-not $res.Ok) { exit 1 }
}
