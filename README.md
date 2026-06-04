# Claude Cowork — Monarch Money Session-Assurance Toolkit

Hybrid Windows automation that guarantees a **live Monarch Money login session**
*before* each scheduled Claude Cowork task runs — eliminating the "stale session →
task lands on the login screen → task fails" class of failures.

> **Status: infrastructure only.** This repository is the reusable plumbing and the
> prompt *language* that is intended to be inserted into the Claude Cowork skill
> later. Nothing here is wired into your live Cowork tasks yet. Deploy and connect
> it deliberately (see [`docs/COWORK_INTEGRATION.md`](docs/COWORK_INTEGRATION.md)).

## The problem this solves

All four scheduled tasks depend on the same thing — an authenticated Monarch Money
web session:

| # | Task                          | Default cadence | Touches Monarch |
|---|-------------------------------|-----------------|-----------------|
| 1 | Paycheck Updater              | Weekly          | ✅              |
| 2 | R1 Transfer Calculator        | Weekly          | ✅              |
| 3 | Telegram Commission Updater   | Daily           | ✅              |
| 4 | Student Loan Balance Updater  | Weekly          | ✅              |

When the session cookie/token goes stale, Cowork opens Monarch and finds a login
wall instead of the dashboard, and the task fails. This toolkit refreshes the
session up front so Cowork always starts warm.

## How it works (the hybrid model)

```
Windows Task Scheduler  ─┐
  (per-task trigger)     │  1. runs prepare_task.ps1 -TaskName <Task>
                         │       ├─ resolves Monarch creds from Credential Manager
                         │       ├─ FAST PATH: validate token via GraphQL  (no browser)
                         │       ├─ SLOW PATH: Playwright validates/re-auths the
                         │       │             saved storageState, handles TOTP MFA
                         │       ├─ writes status\task_status.<Task>.json
                         │       └─ logs everything + notifies on failure
                         │
                         └─ 2. Launch-ClaudeCowork.ps1 hands the task's main prompt
                               to Claude Cowork. The prompt FIRST reads the status
                               file, confirms the session is fresh, then does the
                               real work and verifies with screenshots/file output.
```

Two independent assurance layers, cheapest first:

1. **Token fast path** (`Refresh-MonarchSession.ps1`) — a single GraphQL `me`
   query against `api.monarch.com`. Milliseconds, no browser. Confirms the saved
   bearer token still authenticates.
2. **Browser path** (`monarch-session.mjs`, Playwright) — loads the saved
   `storageState`, navigates to `app.monarch.com`, and detects a login redirect.
   If stale, it performs a full email + password + **TOTP** re-auth and saves a
   fresh `storageState` that Cowork's browser can reuse.

## Repository layout

```
.
├── config/
│   ├── settings.config.json     # global: paths, Monarch URLs/selectors, notifications
│   └── tasks.config.json        # the 4 tasks: cadence, prompt file, enabled flag
├── scripts/
│   ├── prepare_task.ps1         # ★ entry point — prepare_task.ps1 -TaskName Paycheck
│   ├── Common.psm1              # shared: logging, status, creds, notifications, TOTP
│   ├── Refresh-MonarchSession.ps1   # token fast-path + orchestrates Playwright
│   ├── Launch-ClaudeCowork.ps1  # opens Cowork with the right main prompt
│   └── monarch-session.mjs      # Playwright (Node) validate/refresh helper
├── prompts/
│   ├── paycheck_updater.md
│   ├── r1_transfer_calculator.md
│   ├── telegram_commission_updater.md
│   └── student_loan_balance_updater.md
├── tools/
│   ├── install-prerequisites.ps1    # PS modules, Node, Playwright, browsers
│   ├── Set-MonarchCredentials.ps1   # store creds in Windows Credential Manager
│   └── Register-ScheduledTasks.ps1  # create all 4 tasks from tasks.config.json
├── tests/
│   └── Test-Preparation.ps1         # dry-run + diagnostics
└── docs/
    ├── SETUP.md                 # one-time install + first run
    ├── TASK_SCHEDULER.md        # exact click-by-click + scripted setup
    ├── SECURITY.md              # credential & session-state hardening
    ├── TESTING.md               # testing & debugging playbook
    └── COWORK_INTEGRATION.md    # the language to insert into the Cowork skill
```

## Deployment target

The scripts assume they run from `C:\ClaudeAutomation\` on Windows 11. Clone/copy
this repo there (or set `$env:CLAUDE_AUTOMATION_ROOT` to wherever you put it — every
script honors it). Start with [`docs/SETUP.md`](docs/SETUP.md).

## Quick start (TL;DR)

```powershell
# 1. From an elevated PowerShell, install prerequisites
cd C:\ClaudeAutomation
pwsh -File .\tools\install-prerequisites.ps1

# 2. Store your Monarch credentials securely (prompts for password + MFA secret)
pwsh -File .\tools\Set-MonarchCredentials.ps1

# 3. Prime the session once (interactive, so you can solve any first-time MFA)
pwsh -File .\scripts\prepare_task.ps1 -TaskName Paycheck -Interactive

# 4. Dry-run the whole pipeline
pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck

# 5. Register the scheduled tasks (review tasks.config.json first)
pwsh -File .\tools\Register-ScheduledTasks.ps1
```

See the `docs/` folder for the full guides.
