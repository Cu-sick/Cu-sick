<#
.SYNOPSIS
    Installs everything the toolkit needs: PowerShell modules, Node.js, Playwright,
    and the Chromium browser. Run from an elevated PowerShell on Windows 11.

.NOTES
    Idempotent — safe to re-run. Uses winget for Node if Node is missing.
#>
[CmdletBinding()]
param([switch]$SkipNode)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '== Claude Cowork / Monarch toolkit prerequisites ==' -ForegroundColor Cyan

# 1. PowerShell modules ──────────────────────────────────────────────────────
function Ensure-Module($name) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        Write-Host "Installing PowerShell module: $name" -ForegroundColor Yellow
        Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Host "PowerShell module present: $name" -ForegroundColor Green
    }
}

# Trust PSGallery for an unattended install.
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

Ensure-Module 'CredentialManager'   # Get-StoredCredential / New-StoredCredential
Ensure-Module 'BurntToast'          # Windows Toast notifications

# 2. Node.js ─────────────────────────────────────────────────────────────────
if (-not $SkipNode) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host 'Node.js not found — installing via winget (OpenJS.NodeJS.LTS)...' -ForegroundColor Yellow
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
            Write-Host 'Node installed. Re-open PowerShell so PATH refreshes, then re-run this script.' -ForegroundColor Yellow
        } else {
            throw 'winget not available. Install Node.js LTS manually from https://nodejs.org and re-run.'
        }
    } else {
        Write-Host "Node.js present: $(node --version)" -ForegroundColor Green
    }
}

# 3. Playwright (+ Chromium) ─────────────────────────────────────────────────
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path (Join-Path $root 'package.json'))) {
        Write-Host 'Initializing Node project for Playwright...' -ForegroundColor Yellow
        npm init -y | Out-Null
    }
    Write-Host 'Installing Playwright...' -ForegroundColor Yellow
    npm install playwright@latest
    Write-Host 'Installing Chromium browser for Playwright...' -ForegroundColor Yellow
    npx playwright install chromium
    Write-Host 'Playwright + Chromium ready.' -ForegroundColor Green
}
finally { Pop-Location }

# 4. Folder scaffold ─────────────────────────────────────────────────────────
foreach ($sub in 'logs','state','status','status\prompts-outbox') {
    $p = Join-Path $root $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Cyan
Write-Host '  1. pwsh -File .\tools\Set-MonarchCredentials.ps1'
Write-Host '  2. pwsh -File .\scripts\prepare_task.ps1 -TaskName Paycheck -Interactive   (prime session)'
Write-Host '  3. pwsh -File .\tools\Register-ScheduledTasks.ps1'
