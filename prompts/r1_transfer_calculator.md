# Cowork Task — R1 Transfer Calculator (weekly)

You are operating inside Claude Cowork on Windows 11. Your job is to read current
balances in Monarch Money and compute the recommended transfer amount(s) for the
**R1** account, then record/report the result.

## 0. Preflight: confirm the environment is warm (do this FIRST)

1. Read `{{STATUS_FILE}}`; require `success == true` and a healthy `session.state`
   (`fresh`/`refreshed`/`reauthenticated`).
2. If that fails, or the file is missing / older than ~2 hours: **STOP**, note it in
   `C:\ClaudeAutomation\logs\cowork_r1transfer_<date>.md` with the `errors`, notify,
   and end.
3. Open `https://app.monarch.com`, confirm the dashboard (not `/login`). On a login
   wall: STOP and notify, do not enter credentials.

## 1. Read the inputs

> ⚙️ **Configure the account names and the formula for your setup.**

- Identify the relevant accounts (e.g., checking, R1 target account, any buffer).
- Read current balances from Monarch (screenshot the balances "before").
- Load calculation parameters if present: `C:\ClaudeAutomation\status\inputs\r1_transfer.json`
  (e.g., `{ "minBuffer": 0, "targetBalance": 0, "rule": "..." }`).

## 2. Compute the transfer

- Apply the transfer rule. Default skeleton (replace with your real rule):
  - `transfer = max(0, sourceBalance - minBuffer)` capped so the target reaches
    `targetBalance`.
- Show your arithmetic step by step in the report so it can be audited.
- Round to the nearest cent (or dollar, per your rule).

## 3. Record / act

Pick the mode that matches how you use this task:
- **Calculate-only (default):** write the recommended amount to the report and the
  result JSON; do not move money.
- **Record-in-Monarch:** if you log the planned transfer in Monarch (e.g., as a
  note, goal contribution, or category), screenshot "before"/"after" and verify.

## 4. Verify

- Re-read any value you wrote and confirm it persisted.
- Sanity-check: transfer is non-negative, leaves the buffer intact, and does not
  exceed the source balance.

## 5. Report & notify

- Append to `C:\ClaudeAutomation\logs\cowork_r1transfer_<date>.md`: balances read,
  the computation, the recommended/recorded amount, screenshots, `RESULT: ...`.
- Write `C:\ClaudeAutomation\status\cowork_result.R1Transfer.json`
  (`task`,`result`,`summary` including the computed amount,`report`,`timestamp`).

## Error handling

- If a balance can't be read or a value won't save: screenshot, mark `RESULT: FAILED`
  with the reason, notify, stop. Never invent a balance or force a transfer.
