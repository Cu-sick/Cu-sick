# Testing & debugging

## Fast loop

```powershell
# Static + credential + token checks (no browser):
pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck

# Add the live Playwright validation, watch it run:
pwsh -File .\tests\Test-Preparation.ps1 -TaskName Paycheck -Browser -Interactive
```

## Manual stage-by-stage

```powershell
# 1. Just the session refresh, headful, see exactly what Playwright does:
pwsh -File .\scripts\Refresh-MonarchSession.ps1 -Interactive

# 2. Full preparation for one task (writes status + log, no Cowork):
pwsh -File .\scripts\prepare_task.ps1 -TaskName StudentLoan -Interactive

# 3. Preparation + prompt staging, but DON'T launch Cowork:
pwsh -File .\scripts\Launch-ClaudeCowork.ps1 -TaskName StudentLoan -PrepareOnly
```

## Where to look when something fails

| Symptom | Look here |
|---------|-----------|
| Task "ran" but Cowork didn't open | `logs\prepare_task_<date>.log` — prep likely failed (exit 1) |
| Prep failed | `status\task_status.<Task>.json` → `errors[]`; the log around that run's `runId` |
| Login/MFA trouble | Run `Refresh-MonarchSession.ps1 -Interactive` and watch the browser |
| Scheduled task didn't fire | Task Scheduler → **History** tab; check Last Run Result |

## Reading the status file

`status\task_status.<Task>.json` (and `task_status.json` for the latest run):

```json
{
  "task": "Paycheck",
  "success": true,
  "session": { "state": "refreshed", "method": "playwright-validate", "wasStale": false },
  "errors": [], "runId": "…", "completedUtc": "…"
}
```

- `state: fresh` + `method: token-validate` → fast path hit, no browser needed.
- `state: refreshed` → storageState was valid, cookies rolled forward.
- `state: reauthenticated` → session was stale; full login happened (this is the
  recovery you wanted).
- `state: stale-failed`, `success: false` → see `errors[]`; Cowork is **not** launched.

## Common issues

- **`node not found`** — close/reopen PowerShell after installing Node, or re-run
  `install-prerequisites.ps1`. Confirm with `node --version`.
- **Playwright can't find Chromium** — `npx playwright install chromium` from the
  toolkit root.
- **`Email field not found on login page (selectors may be stale)`** — Monarch
  changed its DOM. See *Refreshing selectors* below.
- **`MFA challenge presented but MONARCH_MFA_SECRET is not set`** — store the TOTP
  secret: `Set-MonarchCredentials.ps1`.
- **Token fast path always misses** — the stored token expired; the browser path
  still recovers. Re-extract and store a fresh token if you rely on the fast path.
- **Toast doesn't appear** — install `BurntToast`; toasts only show in an interactive
  session (so keep tasks as "run only when user is logged on").

## Refreshing selectors (when Monarch changes its UI)

1. Run headful and pause at the login page:
   `pwsh -File .\scripts\Refresh-MonarchSession.ps1 -Interactive`
2. Or use Playwright's inspector to find robust selectors:
   ```powershell
   $env:PWDEBUG=1; node .\scripts\monarch-session.mjs refresh
   ```
3. Update the selector candidate arrays in `config\settings.config.json` →
   `monarch.selectors.*`. The helper tries each candidate in order, so add the new
   one first and keep the old as fallback.

## Simulating a stale session

Delete or corrupt the saved state, then run preparation — you should see
`reauthenticated`:

```powershell
Remove-Item C:\ClaudeAutomation\state\monarch_storage_state.json -ErrorAction SilentlyContinue
pwsh -File .\scripts\prepare_task.ps1 -TaskName Paycheck -Interactive
```

## Notifications dry-run

Temporarily set `notifications.notifyOnSuccess: true` in `settings.config.json`, run
any prep, and confirm your enabled channel(s) receive the message. Revert afterward.
