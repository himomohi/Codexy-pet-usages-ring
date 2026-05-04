# Security

This project is a local companion overlay for Codex Desktop on Windows.

## Local Files Read

The app reads:

- `%USERPROFILE%\.codex\.codex-global-state.json` for `/pet` window bounds.
- `%USERPROFILE%\.codex\auth.json` for the local Codex access token.
- `%USERPROFILE%\.codex\logs_2.sqlite` or `logs_1.sqlite` for optional local fallback usage events.

## Network Access

By default, live usage calls are made to:

```text
https://chatgpt.com/backend-api/wham/usage
```

Disable live usage with:

```powershell
.\bin\powershell\Install.ps1 -NoLiveUsage
.\bin\powershell\Start.ps1 -NoLiveUsage
```

## Reporting Issues

Do not paste your `auth.json`, access token, or full local Codex logs into public issues.
