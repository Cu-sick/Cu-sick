<#
.SYNOPSIS
    Shared helpers for the Claude Cowork Monarch session-assurance toolkit.

.DESCRIPTION
    Centralizes configuration loading, logging, status-file writing, secure
    credential retrieval, RFC-6238 TOTP generation, and notifications
    (Windows Toast / Slack / Teams / email).

    Import with:  Import-Module "$PSScriptRoot\Common.psm1" -Force
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-level cache state. Initialized here so StrictMode-safe reads never hit
# an "uninitialized variable" error before the first assignment.
$script:__settings = $null

# ──────────────────────────────────────────────────────────────────────────
# Root / configuration resolution
# ──────────────────────────────────────────────────────────────────────────

function Get-AutomationRoot {
    <# Resolves the toolkit root: CLAUDE_AUTOMATION_ROOT env var wins, else the
       parent of this scripts/ folder, else C:\ClaudeAutomation. #>
    if ($env:CLAUDE_AUTOMATION_ROOT) { return $env:CLAUDE_AUTOMATION_ROOT }
    $parent = Split-Path -Parent $PSScriptRoot
    if ($parent -and (Test-Path $parent)) { return $parent }
    return 'C:\ClaudeAutomation'
}

function Expand-ConfigPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-Settings {
    <# Loads config/settings.config.json once per session (cached). #>
    if ($script:__settings) { return $script:__settings }
    $root = Get-AutomationRoot
    $candidates = @(
        (Join-Path $root 'config\settings.config.json'),
        (Join-Path $root 'settings.config.json')
    )
    $path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $path) { throw "settings.config.json not found under '$root\config'." }
    $script:__settings = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    return $script:__settings
}

function Get-TasksConfig {
    $root = Get-AutomationRoot
    $path = Join-Path $root 'config\tasks.config.json'
    if (-not (Test-Path $path)) { throw "tasks.config.json not found at '$path'." }
    return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json)
}

function Get-TaskDefinition {
    param([Parameter(Mandatory)][string]$TaskName)
    $cfg = Get-TasksConfig
    $task = $cfg.tasks | Where-Object { $_.name -eq $TaskName }
    if (-not $task) {
        $known = ($cfg.tasks.name) -join ', '
        throw "Unknown task '$TaskName'. Known tasks: $known"
    }
    return $task
}

# ──────────────────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────────────────

$script:__logFile = $null

function Initialize-Log {
    param([string]$TaskName = 'general')
    $settings = Get-Settings
    $logDir = Expand-ConfigPath $settings.paths.logs
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    $stamp = Get-Date -Format 'yyyyMMdd'
    $name  = if ($settings.logging.perTaskFile) { "prepare_${TaskName}_$stamp.log" } else { "prepare_task_$stamp.log" }
    $script:__logFile = Join-Path $logDir $name

    # Best-effort retention prune.
    try {
        $cutoff = (Get-Date).AddDays(-1 * [int]$settings.logging.retentionDays)
        Get-ChildItem -LiteralPath $logDir -Filter 'prepare_*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }

    return $script:__logFile
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug','Info','Warn','Error')][string]$Level = 'Info'
    )
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level.ToUpper(), $Message
    if ($script:__logFile) {
        Add-Content -LiteralPath $script:__logFile -Value $line -Encoding UTF8
    }
    switch ($Level) {
        'Error' { Write-Host $line -ForegroundColor Red }
        'Warn'  { Write-Host $line -ForegroundColor Yellow }
        'Debug' { Write-Verbose $line }
        default { Write-Host $line }
    }
}

# ──────────────────────────────────────────────────────────────────────────
# Status file
# ──────────────────────────────────────────────────────────────────────────

function Write-TaskStatus {
    <# Writes status/task_status.<TaskName>.json and updates status/task_status.json
       (the most-recent run) so Cowork prompts can read a stable path. #>
    param(
        [Parameter(Mandatory)][hashtable]$Status
    )
    $settings = Get-Settings
    $statusDir = Expand-ConfigPath $settings.paths.status
    if (-not (Test-Path $statusDir)) { New-Item -ItemType Directory -Path $statusDir -Force | Out-Null }

    $json = $Status | ConvertTo-Json -Depth 8
    $perTask = Join-Path $statusDir ("task_status.{0}.json" -f $Status.task)
    $latest  = Join-Path $statusDir 'task_status.json'
    Set-Content -LiteralPath $perTask -Value $json -Encoding UTF8
    Set-Content -LiteralPath $latest  -Value $json -Encoding UTF8
    return $perTask
}

function New-StatusObject {
    param([Parameter(Mandatory)][string]$TaskName, [string]$DisplayName)
    return @{
        schemaVersion = '1.0'
        task          = $TaskName
        taskDisplayName = $DisplayName
        startedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        completedUtc  = $null
        success       = $false
        session       = @{
            provider         = 'monarch'
            state            = 'unknown'   # fresh | refreshed | reauthenticated | stale-failed
            wasStale         = $null
            method           = $null       # token-validate | playwright-validate | playwright-reauth
            storageStatePath = (Expand-ConfigPath (Get-Settings).paths.storageState)
            lastValidatedUtc = $null
        }
        errors   = @()
        warnings = @()
        runId    = [guid]::NewGuid().ToString()
        machine  = $env:COMPUTERNAME
        log      = $script:__logFile
    }
}

# ──────────────────────────────────────────────────────────────────────────
# Credentials  (Windows Credential Manager → Environment fallback)
# ──────────────────────────────────────────────────────────────────────────

function Get-StoredCredentialSafe {
    <# Returns a PSCredential from Windows Credential Manager for $Target, or $null.
       Uses the CredentialManager PSGallery module if present. #>
    param([Parameter(Mandatory)][string]$Target)
    if (Get-Command -Name Get-StoredCredential -ErrorAction SilentlyContinue) {
        try { return Get-StoredCredential -Target $Target -ErrorAction Stop } catch { return $null }
    }
    return $null
}

function Resolve-MonarchCredentials {
    <# Returns a hashtable: @{ Email; Password; MfaSecret; Token } resolving from
       providers in settings.credentials.providerOrder. Missing values are $null. #>
    $settings = Get-Settings
    $result = @{ Email = $null; Password = $null; MfaSecret = $null; Token = $null }

    foreach ($provider in $settings.credentials.providerOrder) {
        switch ($provider) {
            'CredentialManager' {
                $cred = Get-StoredCredentialSafe -Target $settings.credentials.credentialManagerTarget
                if ($cred) {
                    if (-not $result.Email)    { $result.Email = $cred.UserName }
                    if (-not $result.Password) {
                        $result.Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password))
                    }
                }
                # MFA secret is stored under the same target's "comment"/attribute path is
                # awkward via Credential Manager, so we store it as its own credential.
                $mfa = Get-StoredCredentialSafe -Target ($settings.credentials.credentialManagerTarget + '/MFA')
                if ($mfa -and -not $result.MfaSecret) {
                    $result.MfaSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($mfa.Password))
                }
                $tok = Get-StoredCredentialSafe -Target $settings.credentials.tokenCredentialManagerTarget
                if ($tok -and -not $result.Token) {
                    $result.Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tok.Password))
                }
            }
            'Environment' {
                if (-not $result.Email     -and $env:MONARCH_EMAIL)      { $result.Email     = $env:MONARCH_EMAIL }
                if (-not $result.Password  -and $env:MONARCH_PASSWORD)   { $result.Password  = $env:MONARCH_PASSWORD }
                if (-not $result.MfaSecret -and $env:MONARCH_MFA_SECRET) { $result.MfaSecret = $env:MONARCH_MFA_SECRET }
                if (-not $result.Token     -and $env:MONARCH_TOKEN)      { $result.Token     = $env:MONARCH_TOKEN }
            }
        }
    }
    return $result
}

# ──────────────────────────────────────────────────────────────────────────
# TOTP (RFC 6238)  — generate a 2FA code from a base32 secret, in pure PowerShell
# ──────────────────────────────────────────────────────────────────────────

function ConvertFrom-Base32 {
    param([Parameter(Mandatory)][string]$Base32)
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $clean = ($Base32 -replace '[^A-Za-z2-7]', '').ToUpperInvariant()
    $bits = ''
    foreach ($c in $clean.ToCharArray()) {
        $idx = $alphabet.IndexOf($c)
        if ($idx -lt 0) { continue }
        $bits += [Convert]::ToString($idx, 2).PadLeft(5, '0')
    }
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; ($i + 8) -le $bits.Length; $i += 8) {
        $bytes.Add([Convert]::ToByte($bits.Substring($i, 8), 2))
    }
    return $bytes.ToArray()
}

function Get-TotpCode {
    <# Returns the current 6-digit TOTP for a base32 secret (30s step, SHA1). #>
    param(
        [Parameter(Mandatory)][string]$Secret,
        [int]$Digits = 6,
        [int]$PeriodSeconds = 30
    )
    $key = ConvertFrom-Base32 -Base32 $Secret
    $unixTime = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $counter  = [int64][math]::Floor($unixTime / $PeriodSeconds)

    $counterBytes = [BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder($counter))
    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $key
    $hash = $hmac.ComputeHash($counterBytes)
    $hmac.Dispose()

    $offset = $hash[$hash.Length - 1] -band 0x0f
    $binary = (($hash[$offset]     -band 0x7f) -shl 24) -bor
              (($hash[$offset + 1] -band 0xff) -shl 16) -bor
              (($hash[$offset + 2] -band 0xff) -shl 8)  -bor
               ($hash[$offset + 3] -band 0xff)
    $otp = $binary % [math]::Pow(10, $Digits)
    return ([string]$otp).PadLeft($Digits, '0')
}

# ──────────────────────────────────────────────────────────────────────────
# Notifications
# ──────────────────────────────────────────────────────────────────────────

function Send-Notification {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Success','Failure')][string]$Severity = 'Info'
    )
    $settings = Get-Settings
    $n = $settings.notifications

    if ($Severity -eq 'Success' -and -not $n.notifyOnSuccess) { return }
    if ($Severity -eq 'Failure' -and -not $n.notifyOnFailure) { return }

    # Toast
    if ($n.toast.enabled) {
        try {
            if (Get-Module -ListAvailable -Name BurntToast) {
                Import-Module BurntToast -ErrorAction Stop
                New-BurntToastNotification -Text $Title, $Message -AppLogo $null | Out-Null
            } else {
                Write-Log "BurntToast not installed; skipping toast. (install-prerequisites.ps1 adds it)" -Level Warn
            }
        } catch { Write-Log "Toast notification failed: $($_.Exception.Message)" -Level Warn }
    }

    # Slack
    if ($n.slack.enabled) {
        $hook = [Environment]::GetEnvironmentVariable($n.slack.webhookEnvVar)
        if ($hook) {
            try {
                $payload = @{ text = "*$Title*`n$Message" } | ConvertTo-Json
                Invoke-RestMethod -Uri $hook -Method Post -ContentType 'application/json' -Body $payload | Out-Null
            } catch { Write-Log "Slack notification failed: $($_.Exception.Message)" -Level Warn }
        }
    }

    # Teams
    if ($n.teams.enabled) {
        $hook = [Environment]::GetEnvironmentVariable($n.teams.webhookEnvVar)
        if ($hook) {
            try {
                $color = switch ($Severity) { 'Failure' { 'D93F3F' } 'Success' { '2EB67D' } default { '0078D4' } }
                $payload = @{
                    '@type' = 'MessageCard'; '@context' = 'http://schema.org/extensions'
                    themeColor = $color; summary = $Title; title = $Title; text = $Message
                } | ConvertTo-Json -Depth 4
                Invoke-RestMethod -Uri $hook -Method Post -ContentType 'application/json' -Body $payload | Out-Null
            } catch { Write-Log "Teams notification failed: $($_.Exception.Message)" -Level Warn }
        }
    }

    # Email
    if ($n.email.enabled) {
        try {
            $cred = Get-StoredCredentialSafe -Target $n.email.credentialManagerTarget
            if (-not $cred) { throw "SMTP app password not found in Credential Manager ($($n.email.credentialManagerTarget))." }
            Send-MailMessage -From $n.email.from -To $n.email.to -Subject $Title -Body $Message `
                -SmtpServer $n.email.smtpServer -Port $n.email.smtpPort -UseSsl:$n.email.useSsl `
                -Credential $cred -ErrorAction Stop
        } catch { Write-Log "Email notification failed: $($_.Exception.Message)" -Level Warn }
    }
}

Export-ModuleMember -Function `
    Get-AutomationRoot, Expand-ConfigPath, Get-Settings, Get-TasksConfig, Get-TaskDefinition, `
    Initialize-Log, Write-Log, Write-TaskStatus, New-StatusObject, `
    Get-StoredCredentialSafe, Resolve-MonarchCredentials, ConvertFrom-Base32, Get-TotpCode, `
    Send-Notification
