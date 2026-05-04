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

## Local Settings Server

The settings UI starts a temporary HTTP server bound to `127.0.0.1`. Each launch
generates a random session token and opens the browser with that token. API
requests to `/api/settings` and `/api/defaults` are rejected unless they include
the token in the query string or the `X-Codex-Pet-Settings-Token` header.

This guard is meant to reduce blind localhost requests from unrelated browser
pages while the settings UI is open. The settings server still writes only the
local `settings.json` file and does not expose a remote network listener.

## Install And Uninstall Safety

Root `.bat` files are user-friendly launchers around the PowerShell scripts.
They do not replace the PowerShell implementation. The installer writes an
install marker into the target directory, and `Uninstall.ps1 -RemoveFiles`
requires that marker before recursively deleting the install directory.

Only install from a source you trust. The scripts use PowerShell
`-ExecutionPolicy Bypass` so they can run unsigned local project scripts without
requiring a machine-wide policy change.

## Reporting Issues

Do not paste your `auth.json`, access token, or full local Codex logs into public issues.
