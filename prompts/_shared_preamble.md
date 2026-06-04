<!--
  _shared_preamble.md — reference copy of the gate every task prompt opens with.
  Each task prompt embeds its own copy (so a single file is self-contained for
  Cowork). Edit here first, then propagate. {{STATUS_FILE}} is substituted by
  Launch-ClaudeCowork.ps1 at run time with the absolute status path.
-->

## 0. Preflight: confirm the environment is warm (do this FIRST)

A preparation script has already run. **Do not** attempt to log in to Monarch
yourself unless this preflight tells you to stop.

1. Read the preparation status file: `{{STATUS_FILE}}`
2. Parse the JSON and check:
   - `success` must be `true`.
   - `session.state` must be one of: `fresh`, `refreshed`, `reauthenticated`.
3. **If `success` is false, or the file is missing/older than ~2 hours:**
   - **STOP.** Do not proceed with the task.
   - Write a short note to `C:\ClaudeAutomation\logs\cowork_<task>_<date>.md`
     explaining that preparation did not succeed, quoting `errors` from the status.
   - Send a failure notification (see "Notifications" at the end) and end the run.
4. If checks pass, assume Monarch is already authenticated in the browser session
   (storageState at `session.storageStatePath`). Open `https://app.monarch.com`
   and confirm you land on the dashboard, **not** the login page.
   - If you unexpectedly hit a login wall, STOP and notify (the session went stale
     between preparation and now); do not enter credentials.

## Verification & notification conventions (used by every task)

- **Screenshots:** save to `C:\ClaudeAutomation\logs\screenshots\<task>\<date>\` —
  at minimum: (a) the dashboard after preflight, (b) the screen showing the value
  you changed *before*, and (c) *after* the change is saved.
- **Run report:** append a dated markdown report to
  `C:\ClaudeAutomation\logs\cowork_<task>_<date>.md` with: what you read, what you
  changed (old → new), links to screenshots, and a final `RESULT: SUCCESS|FAILED`.
- **Notifications:** on completion (success or failure) post a one-line summary.
  Prefer the same channels the prep script uses; if you cannot send directly, write
  a file `C:\ClaudeAutomation\status\cowork_result.<task>.json` with
  `{ "task", "result", "summary", "report", "timestamp" }` — the prep/notify layer
  can relay it.
- **Idempotency:** if the value in Monarch already matches the target, record
  "no change needed" rather than re-saving.
