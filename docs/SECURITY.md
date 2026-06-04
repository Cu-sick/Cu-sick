# Security — credentials & session state on Windows

These tasks hold the keys to your finances. Treat the secrets accordingly.

## What secrets exist

| Secret | Sensitivity | Where it lives |
|--------|-------------|----------------|
| Monarch password | High | Windows Credential Manager (`ClaudeAutomation/Monarch`) |
| Monarch MFA/TOTP secret | **Critical** (full 2FA bypass) | Credential Manager (`ClaudeAutomation/Monarch/MFA`) |
| Monarch bearer token | High | Credential Manager (`ClaudeAutomation/MonarchToken`) — optional |
| Playwright `storageState` | **High** (live session cookies/token) | `state\monarch_storage_state.json` |
| SMTP app password | Medium | Credential Manager (`ClaudeAutomation/SmtpAppPassword`) — optional |

## Rules this toolkit follows

1. **No secrets in the repo or in code.** `.gitignore` excludes `secrets/`,
   `state/`, `status/`, `logs/`, and any `*storage_state*.json` / `*.token`.
2. **No secrets on command lines.** Secrets are passed to the Node helper via the
   child process's *environment*, then scrubbed from the parent process immediately
   after (`Remove-Item Env:MONARCH_*`). Never put them in `-Argument` strings —
   those are visible in Task Scheduler and process listings.
3. **Credential Manager + DPAPI.** Secrets are encrypted at rest, scoped to your
   Windows user account. Another user on the same machine cannot read them.

## Hardening checklist

- **Lock down the toolkit folder.** Restrict `C:\ClaudeAutomation\state` (and the
  whole folder) to your user:
  ```powershell
  $acl = Get-Acl C:\ClaudeAutomation\state
  $acl.SetAccessRuleProtection($true, $false)   # break inheritance
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      "$env:USERDOMAIN\$env:USERNAME","FullControl","ContainerInherit,ObjectInherit","None","Allow")
  $acl.AddAccessRule($rule); Set-Acl C:\ClaudeAutomation\state $acl
  ```
- **Encrypt the storageState file** with EFS (per-user transparent encryption):
  ```powershell
  cipher /e C:\ClaudeAutomation\state
  ```
  Optionally enable **BitLocker** on the drive for at-rest protection.
- **Prefer the token fast path sparingly.** Storing a long-lived bearer token is
  convenient but is a standing credential. If you store it, treat it like the
  password and rotate it (re-run `Set-MonarchCredentials.ps1 -IncludeToken`).
- **Run as the interactive user, not SYSTEM.** SYSTEM can't reach your per-user
  Credential Manager or DPAPI scope, and Cowork needs your desktop.
- **Rotate on suspicion.** If the machine is lost/compromised: change the Monarch
  password, **regenerate the MFA secret** (old TOTP secret = permanent 2FA bypass),
  delete `state\monarch_storage_state.json`, and clear the Credential Manager
  entries (`cmdkey /delete:ClaudeAutomation/Monarch` etc.).
- **Logs may contain hints, not secrets.** The toolkit logs actions and statuses,
  never passwords/tokens. Still, keep `logs\` and `status\` inside the ACL'd folder.
- **Notifications leak summaries.** Slack/Teams/email messages describe task outcomes
  (e.g., balances). Use private channels and app-specific passwords, never your main
  email password.

## What "stale session recovery" does and doesn't do

- If the saved session is stale, the toolkit re-authenticates using your stored
  password + freshly generated TOTP. This requires the MFA secret to be present.
- If Monarch presents a **new** challenge it can't satisfy (new-device email code,
  CAPTCHA, forced password reset), it **stops and notifies** rather than guessing.
  Resolve interactively (`prepare_task.ps1 -TaskName <T> -Interactive`).
