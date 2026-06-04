# Cowork Task — Paycheck Updater (weekly)

You are operating inside Claude Cowork on Windows 11. Your job is to update the
paycheck / recurring income in Monarch Money for the current pay period.

## 0. Preflight: confirm the environment is warm (do this FIRST)

A preparation script has already refreshed the Monarch session. Do **not** log in
yourself.

1. Read `{{STATUS_FILE}}` and parse the JSON.
2. Require `success == true` and `session.state` ∈ {`fresh`,`refreshed`,`reauthenticated`}.
3. If that fails, or the file is missing / older than ~2 hours: **STOP**, write a
   note to `C:\ClaudeAutomation\logs\cowork_paycheck_<date>.md` quoting `errors`,
   send a failure notification, and end.
4. Open `https://app.monarch.com` and confirm the dashboard loads (not `/login`).
   If you hit a login wall, STOP and notify — do not enter credentials.

## 1. Gather the paycheck figures

> ⚙️ **Configure this section for your real numbers/source.** Leave as instructions
> for Cowork to follow; this template intentionally does not hard-code amounts.

- Determine this period's paycheck amount. Source options (pick what applies):
  - the deposit that just posted to the checking account in Monarch, or
  - a known fixed net amount, or
  - a value provided in `C:\ClaudeAutomation\status\inputs\paycheck.json` if present.
- Note pay date and which income stream this maps to (e.g., "Primary Salary").

## 2. Make the update in Monarch

1. Navigate to the income / recurring section (Recurring, or the income transaction
   for this pay date).
2. Record the **current** value (screenshot "before").
3. Set the paycheck amount / mark the expected income as received with the actual
   amount.
4. Save. Screenshot "after".

## 3. Verify

- Re-read the value you changed and confirm it matches the target.
- Confirm the recurring income's next expected date advanced correctly.
- If already correct, record "no change needed".

## 4. Report & notify

- Append to `C:\ClaudeAutomation\logs\cowork_paycheck_<date>.md`: figures used,
  old → new, screenshot paths, and `RESULT: SUCCESS|FAILED`.
- Write `C:\ClaudeAutomation\status\cowork_result.Paycheck.json` with
  `{ "task":"Paycheck", "result":"SUCCESS|FAILED", "summary":"...", "report":"<path>", "timestamp":"<iso>" }`.

## Error handling

- Any step that can't complete (element missing, value won't save, unexpected logout):
  capture a screenshot, write `RESULT: FAILED` with the reason, notify, and stop —
  do **not** guess or force changes.
