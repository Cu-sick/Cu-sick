# Cowork integration — the seam (and the language to insert later)

> This toolkit is intentionally **not** wired into your live Cowork tasks. This
> document is the staging ground: the integration seam, plus ready-to-insert
> language for the Cowork skill once you decide to connect it.

## The seam

The launch flow is:

```
Scheduled Task → Launch-ClaudeCowork.ps1 → prepare_task.ps1 (gate)
                                          → stage prompt → start Cowork
```

Two things are environment-specific and deliberately left as configuration, because
Claude Cowork Desktop does not (today) expose a documented, stable "open with this
exact prompt" command-line contract:

1. **How Cowork is launched** — `settings.cowork.exePathCandidates` and `launchArgs`.
2. **How the prompt reaches Cowork** — `settings.cowork.promptDelivery`:
   - `file` (default): the resolved prompt is written to
     `status\prompts-outbox\<Task>.prompt.md`. You configure the Cowork task **once**
     to read its main instruction from that file.
   - `clipboard`: the prompt is placed on the clipboard for a paste step.

When you confirm how your Cowork build accepts an initial prompt (CLI flag, deep
link, automation file, or skill trigger), set those two config values — no script
changes needed.

## The status-file contract (stable)

Whatever the delivery mechanism, the contract Cowork relies on is the status file.
The launcher substitutes `{{STATUS_FILE}}` in each prompt with the absolute path
`status\task_status.<Task>.json`. Every task prompt opens by reading it and refuses
to run unless `success == true` and the session is healthy. This is the durable
interface — keep it even if the launch mechanism changes.

---

## Language to insert into the Cowork skill (when ready)

When you fold this into the Cowork skill, add a preamble like the block below to the
skill's instructions. It encodes the "assume warm, verify first, never self-login"
discipline so every scheduled task inherits it.

```markdown
### Scheduled-task preflight (Monarch session assurance)

Before doing any scheduled financial task, a Windows preparation script has already
ensured the Monarch Money session is live. You MUST:

1. Read the preparation status file whose path is provided in the task prompt
   (the `Preparation status file:` line of the auto-generated header, or the
   `{{STATUS_FILE}}` value), and parse it as JSON.
2. Proceed only if `success == true` and `session.state` is one of
   `fresh`, `refreshed`, or `reauthenticated`. Otherwise STOP, record why, and
   notify — do not attempt the task.
3. Assume Monarch is already authenticated (browser storageState at
   `session.storageStatePath`). Never enter Monarch credentials yourself. If you hit
   a login wall, the session went stale after preparation: STOP and notify so the
   prep script can recover on the next run.
4. Verify every change with before/after screenshots and a dated run report under
   `C:\ClaudeAutomation\logs\`, and write a result JSON to
   `C:\ClaudeAutomation\status\cowork_result.<Task>.json`.
5. Be idempotent: if the target value already matches, record "no change needed".
```

### Optional: have Cowork trigger preparation itself

If you'd rather Cowork own the whole flow (instead of Task Scheduler calling the
launcher), the skill can shell out to preparation as its first step:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ClaudeAutomation\scripts\prepare_task.ps1 -TaskName <Task>
```

…then read the status file and continue only on exit code 0. Keep the same status
contract either way.

## Extending to other providers (e.g., Telegram)

The session layer is provider-shaped around Monarch today. To assure a second
service (Telegram, a loan servicer), add a sibling refresh function and a
`requiresXSession` flag in `tasks.config.json`, then extend the status object's
`session` block (or add a `sessions[]` array). The prompt preflight pattern stays
identical — just check more entries. Say the word and I'll add the Telegram provider.
