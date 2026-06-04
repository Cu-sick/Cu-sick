# Windows Task Scheduler — setup

Two ways to create the four tasks: **scripted** (recommended) or **manual**
(click-by-click). Both produce the same result: a task that runs
`Launch-ClaudeCowork.ps1 -TaskName <Name>`, which runs preparation first and only
opens Cowork if the Monarch session is live.

The four tasks and default cadences (from `config/tasks.config.json`):

| Task name (`-TaskName`) | Scheduled task name        | Default trigger          |
|-------------------------|----------------------------|--------------------------|
| `Paycheck`              | `ClaudeCowork-Paycheck`    | Weekly, Fri 07:00        |
| `R1Transfer`            | `ClaudeCowork-R1Transfer`  | Weekly, Fri 07:30        |
| `TelegramCommission`    | `ClaudeCowork-TelegramCommission` | Daily 08:00       |
| `StudentLoan`           | `ClaudeCowork-StudentLoan` | Weekly, Mon 07:00        |

Change cadence/time by editing `tasks.config.json` and re-running the scripted
registration, or by editing the trigger in the manual steps below.

---

## Option A — Scripted (recommended)

From an elevated PowerShell:

```powershell
cd C:\ClaudeAutomation
pwsh -File .\tools\Register-ScheduledTasks.ps1 -WhatIf    # preview what will be created
pwsh -File .\tools\Register-ScheduledTasks.ps1            # create/update all enabled tasks
```

Useful follow-ups:

```powershell
Get-ScheduledTask -TaskName ClaudeCowork-* | Format-Table TaskName,State
Start-ScheduledTask -TaskName ClaudeCowork-Paycheck      # run now (does prep + launch)
pwsh -File .\tools\Register-ScheduledTasks.ps1 -Remove    # delete all four
```

The registration sets sensible defaults: **Start when available** (catches up if the
PC was asleep), **restart twice** 5 min apart on failure, and a **1-hour** execution
limit. It runs as your interactive user (so Cowork can show UI). Add
`-RunWithHighestPrivileges` only if you actually need elevation.

---

## Option B — Manual (click-by-click), per task

Do this once for **each** of the four tasks, substituting the task name.

1. Press `Win`, type **Task Scheduler**, open it.
2. Right pane → **Create Task…** (not "Basic Task" — we need the action arguments).
3. **General** tab:
   - **Name:** `ClaudeCowork-Paycheck` (use the matching name from the table).
   - **Description:** `Refresh Monarch session, then launch Claude Cowork: Paycheck Updater.`
   - Select **Run only when user is logged on** (Cowork needs your desktop session).
   - Leave **Run with highest privileges** unchecked unless you know you need it.
   - **Configure for:** Windows 10/11.
4. **Triggers** tab → **New…**:
   - **Begin the task:** *On a schedule*.
   - **Weekly** example (Paycheck): tick **Weekly**, **Recur every 1 week**, check
     **Friday**, set **Start** time `07:00:00`.
   - **Daily** example (TelegramCommission): tick **Daily**, **Recur every 1 day**,
     **Start** `08:00:00`.
   - Optional: enable **Stop task if it runs longer than** `1 hour`.
   - **OK**.
5. **Actions** tab → **New…**:
   - **Action:** *Start a program*.
   - **Program/script:** full path to pwsh, e.g.
     `C:\Program Files\PowerShell\7\pwsh.exe`
     (or `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` for 5.1).
   - **Add arguments:**
     ```
     -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ClaudeAutomation\scripts\Launch-ClaudeCowork.ps1" -TaskName Paycheck
     ```
     (Change `-TaskName` to `R1Transfer`, `TelegramCommission`, or `StudentLoan`.)
   - **Start in:** `C:\ClaudeAutomation`
   - **OK**.
6. **Conditions** tab:
   - Uncheck **Start the task only if the computer is on AC power** if you want it to
     run on battery (laptops).
   - Optionally check **Wake the computer to run this task**.
7. **Settings** tab:
   - Check **Allow task to be run on demand**.
   - Check **Run task as soon as possible after a scheduled start is missed**.
   - **If the task fails, restart every:** `5 minutes`, **up to** `2 times`.
   - **Stop the task if it runs longer than:** `1 hour`.
8. **OK**. If prompted, enter your Windows password.

### Test a manual task

- In Task Scheduler, select the task → **Run** (right pane), or:
  ```powershell
  Start-ScheduledTask -TaskName ClaudeCowork-Paycheck
  ```
- Watch `C:\ClaudeAutomation\logs\prepare_task_<date>.log` and confirm
  `C:\ClaudeAutomation\status\task_status.Paycheck.json` shows `"success": true`.

---

## Sequencing note (Paycheck → R1Transfer)

R1Transfer is scheduled 30 minutes after Paycheck so balances reflect the new
deposit. If you'd rather chain them strictly, set R1Transfer's trigger to
**On an event** or add a second action — but the simple time gap is usually enough
and keeps the tasks independent (one failing doesn't block the other).

## Why a wrapper instead of two actions?

Task Scheduler runs multiple actions sequentially but does **not** stop if the first
fails. We deliberately use a single action that calls `Launch-ClaudeCowork.ps1`,
which runs preparation and **gates** the Cowork launch on success — so Cowork never
starts against a stale session.
