<#
.SYNOPSIS
    Stores Monarch Money credentials securely in Windows Credential Manager.

.DESCRIPTION
    Prompts for (and never echoes) your Monarch email, password, and — if you use
    2FA — your TOTP secret. Optionally stores a pre-extracted bearer token to enable
    the no-browser GraphQL fast path, and an SMTP app password for email alerts.

    Credentials are written to the Windows Credential Manager under the targets
    configured in settings.config.json. They are scoped to the current Windows user
    and protected by DPAPI. Nothing is written to disk in the repo.

.NOTES
    Requires the CredentialManager module (install-prerequisites.ps1 installs it).
    The MFA "secret" is the base32 "two-factor text/setup code" from Monarch:
        Settings → Security → Enable MFA → "Can't scan?" / manual entry code.
#>
[CmdletBinding()]
param([switch]$IncludeToken, [switch]$IncludeSmtp)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$([IO.Path]::Combine((Split-Path -Parent $PSScriptRoot),'scripts','Common.psm1'))" -Force

if (-not (Get-Command New-StoredCredential -ErrorAction SilentlyContinue)) {
    throw "CredentialManager module not available. Run tools\install-prerequisites.ps1 first."
}

$settings = Get-Settings
$target   = $settings.credentials.credentialManagerTarget

Write-Host "Storing Monarch credentials under Credential Manager target: $target" -ForegroundColor Cyan

$email = Read-Host 'Monarch email'
$pw    = Read-Host 'Monarch password' -AsSecureString
$plainPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))

New-StoredCredential -Target $target -UserName $email -Password $plainPw -Persist LocalMachine | Out-Null
Write-Host "  ✓ Email + password stored." -ForegroundColor Green

$mfa = Read-Host 'Monarch MFA/TOTP secret (base32, blank to skip)'
if ($mfa) {
    New-StoredCredential -Target ($target + '/MFA') -UserName 'totp' -Password $mfa -Persist LocalMachine | Out-Null
    # Sanity-check we can generate a code from it.
    try {
        $code = Get-TotpCode -Secret $mfa
        Write-Host "  ✓ MFA secret stored. (current code preview: $code)" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ MFA secret stored but a test code could not be generated: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($IncludeToken) {
    Write-Host ''
    Write-Host 'Optional GraphQL fast-path token. Paste the Monarch bearer/Token value' -ForegroundColor Cyan
    Write-Host '(from a logged-in session''s Authorization header), or leave blank to skip.'
    $tok = Read-Host 'Monarch token'
    if ($tok) {
        New-StoredCredential -Target $settings.credentials.tokenCredentialManagerTarget -UserName 'token' -Password $tok -Persist LocalMachine | Out-Null
        Write-Host "  ✓ Token stored (enables no-browser validation)." -ForegroundColor Green
    }
}

if ($IncludeSmtp) {
    $smtpTarget = $settings.notifications.email.credentialManagerTarget
    $appPw = Read-Host "SMTP app password for $($settings.notifications.email.from)" -AsSecureString
    $plainSmtp = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($appPw))
    New-StoredCredential -Target $smtpTarget -UserName $settings.notifications.email.from -Password $plainSmtp -Persist LocalMachine | Out-Null
    Write-Host "  ✓ SMTP app password stored under $smtpTarget." -ForegroundColor Green
}

# Scrub plaintext copies.
$plainPw = $null; $plainSmtp = $null; [GC]::Collect()
Write-Host ''
Write-Host 'Verify any time with:  Get-StoredCredential -Target ' -NoNewline; Write-Host $target -ForegroundColor Yellow
