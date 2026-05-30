<p align="center">
  <img src="docs/assets/codexy-pet-usages-ring-titlebar.png" alt="Codexy pet usages ring GitHub title bar" width="100%">
</p>

<p align="center">
  <a href="https://github.com/himomohi/Codexy-pet-usages-ring/releases/latest">
    <img alt="Download latest release" src="https://img.shields.io/badge/Download_latest_release-v0.1.12-3CEBBD?style=for-the-badge&logo=github">
  </a>
</p>

<p align="center">
  <a href="CHANGELOG.md#0112"><img alt="Version 0.1.12" src="https://img.shields.io/badge/version-0.1.12-3CEBBD?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-56B2FF?style=for-the-badge"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=for-the-badge">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-3CEBBD?style=for-the-badge">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a>
  · <a href="#commands">Commands</a>
  · <a href="#privacy">Privacy</a>
  · <span>English</span>
  · <a href="README.ko.md">한국어</a>
  · <a href="README.ja.md">日本語</a>
  · <a href="README.zh.md">中文</a>
</p>

I kept checking my Codex usage every few minutes.
So I made the rings follow the pet instead.

Codexy pet usages ring draws translucent usage-limit rings around
the Codex Desktop `/pet` avatar. It is a Windows companion implementation of
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
using PowerShell, WPF, and Win32 window positioning.

<p align="center">
  <a href="docs/assets/usage-rec.mp4">
    <img src="docs/assets/usage-rec.gif" alt="Codexy pet usage rings demo" width="100%">
  </a>
</p>

<p align="center">
  Stop checking usage pages every few minutes.<br>
  Let the pet tell you instead.
</p>

<!-- Features -->

## Features

- Shows circular rings, compact battery bars, or badge chips around the current Codex `/pet` avatar.
- Adds optional pet growth where today's XP fills from 5h usage progress, with weekly reset seasons and playful states.
- Adds realtime typing-count gamification, rare reward drops, a clickable reward chest, and unlockable font/theme cosmetics.
- Displays 5h and weekly usage readouts on hover.
- Localizes readouts, tray text, and settings UI for English, Korean, Japanese, and Chinese.
- Auto-detects and can start Codex Desktop.
- Starts the companion helper only while `/pet` is visible, then stops it when `/pet` closes.
- Keeps the Windows tray icon off by default so it does not look like a second Codex app.
- Uses a click-through WPF overlay, so it does not intercept mouse input.
- Installs Windows Startup and Start Menu shortcuts.
- Provides root `.bat` launchers for double-click install, settings, status, start, stop, and uninstall.

<!-- Requirements -->

## Requirements

- Windows 10 or Windows 11.
- Codex Desktop installed and signed in.
- PowerShell 5.1 or newer.
- The Codex `/pet` overlay must be open for rings to appear.

Python is optional and only used for the local SQLite log fallback.

<!-- Quick Start -->

## Quick Start

1. Download or clone this repository.
2. Open the repository folder.
3. Double-click `Install.bat`.
4. Open Codex Desktop and use `/pet`.

The installer copies files to `%LOCALAPPDATA%\CodexyPetUsagesRing`, starts the
lightweight `/pet` watcher, and registers it for Windows startup.

PowerShell install:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

## Commands

Double-click launchers:

```text
Install.bat
Start.bat
Stop.bat
Status.bat
Settings.bat
Uninstall.bat
```

When an install exists, these launchers automatically use the installed helper
under `%LOCALAPPDATA%\CodexyPetUsagesRing`.

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
.\bin\powershell\Diagnose.ps1
.\bin\powershell\Uninstall.ps1
```

Useful install options:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
.\bin\powershell\Install.ps1 -NoStartup -NoStartMenu -NoStart
.\bin\powershell\Install.ps1 -NoLiveUsage
```

Remove installed files too:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

`-RemoveFiles` requires an install marker in the target directory to prevent
accidental recursive deletion of the wrong folder.

## Customize

Open `Settings.bat` or run:

```powershell
.\bin\powershell\Settings.ps1
```

The settings UI saves to:

```text
%LOCALAPPDATA%\CodexyPetUsagesRing\settings.json
```

You can switch between ring, battery, and badge display modes, then change
colors, opacity, readout colors, and hover text size. Pet growth can be turned
off at any time, and the growth mode chooses the 5h usage target for today's XP:
Light 20%, Balanced 40%, or Focused 60%. Weekly usage is used for reset and
depletion guard behavior, not as the normal XP gate.

The gamification panel controls the keyboard counter and reward display mode.
Reward drops are intentionally rare; acquired cosmetics appear in the chest
inventory and can unlock font styles or themed key-counter borders.

The running helper reloads the settings file automatically.

## Privacy

The app reads these local Codex files:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` or `logs_1.sqlite`

It does not require an OpenAI API key and does not send pet images,
screenshots, prompts, repository contents, or spritesheets anywhere.

Live usage uses the local Codex access token only for:

```text
https://chatgpt.com/backend-api/wham/usage
```

Disable live network usage with `-NoLiveUsage`.

The settings page runs a temporary `127.0.0.1` server with a random session
token and writes only the local `settings.json` file.

## Notes

- This is not an official OpenAI or Codex feature.
- The live usage endpoint is not a documented third-party API and may change.
- Rings appear only while `/pet` is open.

## AI Install Handoff

Repository URL:

```text
https://github.com/himomohi/Codexy-pet-usages-ring
```

Give an AI agent this repository URL and ask it to install the project on
Windows:

```text
Install Codexy pet usages ring from:
https://github.com/himomohi/Codexy-pet-usages-ring

If the repository is not local, clone it first. Then run Install.bat from the
repository root. After installation, run Status.ps1 and Diagnose.ps1 to verify
that the helper is installed, running, and waiting for or following /pet.
```

CLI equivalent:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Diagnose.ps1
```

## More

- [CHANGELOG.md](CHANGELOG.md)
- [SECURITY.md](SECURITY.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/architecture.md](docs/architecture.md)
- [NOTICE.md](NOTICE.md)

Build a release zip:

```powershell
.\tools\New-ReleaseZip.ps1
```

Feature and bug-fix releases should update `VERSION`, the README badge, and the
top `CHANGELOG.md` section together.
