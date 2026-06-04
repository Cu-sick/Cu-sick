# Cowork Task — Student Loan Balance Updater (weekly)

You are operating inside Claude Cowork on Windows 11. Your job is to update the
manual student-loan balance in Monarch Money so it matches the loan servicer.

## 0. Preflight: confirm the environment is warm (do this FIRST)

1. Read `{{STATUS_FILE}}`; require `success == true` and a healthy `session.state`.
2. On failure / missing / stale (>~2h): **STOP**, log to
   `C:\ClaudeAutomation\logs\cowork_studentloan_<date>.md` with `errors`, notify, end.
3. Open `https://app.monarch.com`, confirm the dashboard (not `/login`). Login wall
   → STOP and notify; do not enter credentials.

## 1. Get the current balance

> ⚙️ **Configure the source.** Options:
- Read the latest balance from the servicer (if the servicer session is available
  to Cowork and signed in), or
- Use a value staged at `C:\ClaudeAutomation\status\inputs\student_loan.json`
  (`{ "balance":0, "asOf":"" }`) if a helper fetched it, or
- Use the balance you are explicitly given for this run.

Screenshot the source of truth (servicer page or input file) for evidence.

## 2. Update the manual account in Monarch

1. Navigate to the student-loan account in Monarch (a manual/offline liability).
2. Screenshot the current balance ("before").
3. Update the account balance to the new figure (use Monarch's "update balance" /
   edit-balance control for manual accounts).
4. Save. Screenshot "after".

## 3. Verify

- Re-read the account balance; confirm it equals the target figure.
- Confirm the net-worth / liabilities view reflects the change.
- If the balance already matches, record "no change needed".

## 4. Report & notify

- Append to `C:\ClaudeAutomation\logs\cowork_studentloan_<date>.md`: source balance
  and date, old → new in Monarch, screenshots, `RESULT: ...`.
- Write `C:\ClaudeAutomation\status\cowork_result.StudentLoan.json`.

## Error handling

- Can't read the servicer balance, account not found, or save fails → screenshot,
  `RESULT: FAILED` with reason, notify, stop. Never enter a fabricated balance.
