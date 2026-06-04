# Setup

One-time install and first run on Windows 11.

## Prerequisites

- Windows 11, with permission to create Scheduled Tasks for your user.
- PowerShell 7 (`pwsh`) recommended. Windows PowerShell 5.1 also works.
- A Monarch Money account; if you use 2FA, your **TOTP secret** (base32). Get it in
  Monarch: **Settings → Security → Enable MFA → manual / "can't scan" code**. Store
  this secret like a password.
- Claude Cowork Desktop installed and signed in once interactively.

## 1. Place the toolkit

Copy this repo to `C:\ClaudeAutomation\` (the default the scripts assume), e.g.:

```powershell
git clone <your-repo-url> C:\ClaudeAutomation
cd C:\ClaudeAutomation
```

> Using a different folder? Set `setx CLAUDE_AUTOMATION_ROOT "D:\path\to\toolkit"`
> (re-open PowerShell after). Every script honors `CLAUDE_AUTOMATION_ROOT`.

## 2. Install prerequisites

From an **elevated** PowerShell:

```powershell
pwsh -ExecutionPolicy Bypass -File .\tools\install-prerequisites.ps1
```

This installs the `CredentialManager` and `BurntToast` PowerShell modules, Node.js
(via winget if missing), Playwright + the Chromium browser, and creates the
`logs\`, `state\`, and `status\` folders. If Node was just installed, re-open
PowerShell and re-run the script so `node` is on PATH.

## 3. Store credentials securely

```powershell
pwsh -File .\tools\Set-MonarchCredentials.ps1            # email, password, MFA secret
# include the GraphQL fast-path token and/or SMTP alert password:
pwsh -File .\tools\Set-MonarchCredentials.ps1 -IncludeToken -IncludeSmtp
```

Secrets go into **Windows Credential Manager** (DPAPI-protected, per-user). Nothing
is written into the repo. See [SECURITY.md](SECURITY.md).

## 4. Prime the session once (interactive)

Run preparation headful so you can clear any first-time MFA/device prompt:

```powershell
pwsh -File .\scripts\prepare_task.ps1 -TaskName Paycheck -Interactive
```

A Chromium window opens, logs into Monarch, and saves
`state\monarch_storage_state.json`. Subsequent runs reuse and silently refresh it.

## 5. Validate the pipeline

```powershell
pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck
# include the live browser check:
pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck -Browser
```

All checks should pass (MFA/token rows may show WARN if you didn't store them).

## 6. Register the scheduled tasks

Review [`config/tasks.config.json`](../config/tasks.config.json) (cadences/times),
then:

```powershell
pwsh -File .\tools\Register-ScheduledTasks.ps1 -WhatIf   # preview
pwsh -File .\tools\Register-ScheduledTasks.ps1           # create
```

See [TASK_SCHEDULER.md](TASK_SCHEDULER.md) for the manual click-by-click equivalent.

## 7. Connect Cowork (deliberate, not automatic)

The launcher *stages* each task's prompt but the exact "hand prompt to Cowork" step
depends on your Cowork build. Read [COWORK_INTEGRATION.md](COWORK_INTEGRATION.md) and
wire that seam intentionally — this toolkit is built to be inserted into the Cowork
skill, not to assume an undocumented CLI.
