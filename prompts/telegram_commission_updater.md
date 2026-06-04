# Cowork Task — Telegram Commission Updater (daily)

You are operating inside Claude Cowork on Windows 11. Your job is to pull the latest
commission figure(s) from Telegram and record them in Monarch Money.

## 0. Preflight: confirm the environment is warm (do this FIRST)

1. Read `{{STATUS_FILE}}`; require `success == true` and a healthy `session.state`.
2. On failure / missing / stale (>~2h): **STOP**, log to
   `C:\ClaudeAutomation\logs\cowork_telegramcommission_<date>.md` with `errors`,
   notify, end.
3. Open `https://app.monarch.com`, confirm the dashboard (not `/login`). Login wall
   → STOP and notify; do not enter credentials.

> Note: the preparation script assures the **Monarch** session. If your Telegram
> access also needs a warm session, say so and I'll extend `prepare_task.ps1` with a
> Telegram provider — for now this prompt assumes Telegram is reachable (Telegram
> Desktop already signed in, or a bot/API token available).

## 1. Read the commission figure(s) from Telegram

> ⚙️ **Configure the source.** Options:
- Telegram Desktop is open and signed in: read the latest message(s) from the
  specific chat/channel that posts commissions.
- A bot/API path: read from `C:\ClaudeAutomation\status\inputs\telegram_commission.json`
  if a helper has already fetched it (`{ "date":"", "amount":0, "raw":"" }`).

Identify, for the relevant period:
- the commission **amount**, the **date**, and any label/source needed for Monarch.
- Screenshot the Telegram message you parsed (evidence of the source value).

## 2. Record in Monarch

1. Navigate to where commissions are tracked (a category/transaction or recurring
   income line).
2. Screenshot "before".
3. Enter / add the commission amount for the correct date.
4. Save. Screenshot "after".

## 3. Verify

- Re-read the recorded value; confirm amount and date match what you parsed.
- Guard against duplicates: if today's commission was already recorded, record
  "no change needed" instead of adding a second entry.

## 4. Report & notify

- Append to `C:\ClaudeAutomation\logs\cowork_telegramcommission_<date>.md`: source
  message, parsed amount/date, what was recorded, screenshots, `RESULT: ...`.
- Write `C:\ClaudeAutomation\status\cowork_result.TelegramCommission.json`.

## Error handling

- No new commission message today → record `RESULT: SUCCESS` with "nothing to update".
- Ambiguous/unparseable message, can't reach Telegram, or save fails → screenshot,
  `RESULT: FAILED` with reason, notify, stop. Do not guess an amount.
