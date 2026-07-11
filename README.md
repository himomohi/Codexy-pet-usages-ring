<p align="center">
  <img src="docs/assets/codex-pet-limit-rings-win-titlebar.png" alt="Codex Pet Limit Rings for Windows GitHub title bar" width="100%">
</p>

<p align="center">
  <a href="https://github.com/himomohi/Codexy-pet-usages-ring/releases/latest"><img alt="Download latest release" src="https://img.shields.io/badge/download-latest_release-3CEBBD?style=for-the-badge&logo=github"></a>
  <a href="VERSION"><img alt="Version 0.1.20" src="https://img.shields.io/badge/version-0.1.20-3CEBBD?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-56B2FF?style=for-the-badge"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=for-the-badge">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-3CEBBD?style=for-the-badge">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a>
  · <a href="#download">Download</a>
  · <a href="#commands">Commands</a>
  · <a href="#privacy">Privacy</a>
  · <a href="README.ko.md">한국어</a>
</p>

Codex Pet Limit Rings for Windows draws translucent usage-limit rings around
the Codex Desktop `/pet` avatar. It is a Windows companion implementation of
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
using PowerShell, WPF, and Win32 window positioning.

## Features

- Offers rings, dual bars, side gauges, corner frames, and reference-matched pixel-art potion orbs.
- Shows 5h and weekly remaining usage continuously or only on hover.
- Adjusts position and spacing relative to the pet, including one-click centering.
- Scales potion orbs from 70-140% while preserving pet-relative spacing.
- Separates left 5h and right weekly hover readouts using Noto Sans KR.
- Selects Korean for South Korean public IPs and English elsewhere when language is set to Auto.
- Auto-detects and can start Codex Desktop.
- Waits quietly until `/pet` is visible.
- Uses a click-through WPF overlay, so it does not intercept mouse input.
- Optionally installs a Windows Startup shortcut; the safer default only creates Start Menu shortcuts.
- Provides root `.bat` launchers for double-click install, settings, status, start, stop, and uninstall.
- Provides a cute cat-face icon in the Windows taskbar notification area; right-click it to open Settings, refresh usage, open logs, or quit.

## Requirements

- Windows 10 or Windows 11.
- Codex Desktop installed and signed in.
- PowerShell 5.1 or newer.
- The Codex `/pet` overlay must be open for the usage HUD to appear.

Python is optional and only used for the local SQLite log fallback.

## Download

For the easiest installation, open the [latest GitHub release](https://github.com/himomohi/Codexy-pet-usages-ring/releases/latest), download `codex-pet-limit-rings-Win-0.1.20.zip`, and extract the ZIP to a normal folder. Then double-click `Install.bat` or `Manage.bat`.

You can also download the repository source with GitHub's **Code → Download ZIP** button, extract it, and run the same installer. Developers can clone it instead:

```powershell
git clone https://github.com/himomohi/Codexy-pet-usages-ring.git
cd Codexy-pet-usages-ring
.\Install.bat
```

## Quick Start

Double-click `Manage.bat` for a single menu that installs, checks, configures,
stops, or completely removes the companion.

- `Install.bat` installs and starts the rings without Windows auto-start.
- `Install-AutoStart.bat` installs, starts, and explicitly enables auto-start.
- `Apply-Installed.bat` applies later source edits to the trusted current install, preserves settings, and restarts it only when it was running.
- `Uninstall.bat` removes the running helper, shortcuts, and installed copy while keeping this source folder.

Open `/pet` in Codex Desktop after installation. The left/outer display is the
5-hour remaining allowance and the right/inner display is weekly remaining
allowance. Hover a usage display for exact percentages, reset times, and a live countdown showing the remaining time.

The installer copies files to `%LOCALAPPDATA%\CodexPetLimitRingsWin` and starts
the helper. Auto-start is registered only through `Install-AutoStart.bat` or the
explicit PowerShell `-Startup` option.

PowerShell install:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

Add `-Startup` when you explicitly want Windows auto-start registration.

## Commands

Double-click launchers:

```text
Manage.bat
Install.bat
Install-AutoStart.bat
Apply-Installed.bat
Start.bat
Stop.bat
Status.bat
Settings.bat
Diagnose.bat
Uninstall.bat
```

When an install exists, these launchers automatically use the installed helper
under `%LOCALAPPDATA%\CodexPetLimitRingsWin`.

The source and installed folders include reciprocal shortcuts (`설치본 열기.lnk` and `원본 프로젝트 열기.lnk`) so either copy is easy to locate. Run `Apply-Installed.bat` after editing the source to update the installed copy without overwriting `settings.json`.

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\tools\Sync-Installed.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
.\bin\powershell\Diagnose.ps1
.\bin\powershell\Uninstall.ps1
```

Useful install options:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
.\bin\powershell\Install.ps1 -Startup
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

While the companion is running, find the orange cat-face icon in the notification area at the right side of the Windows taskbar. If it is folded away, open **Show hidden icons**, right-click the cat icon, and choose **Settings**.

<p align="center">
  <img src="docs/assets/windows-tray-settings-guide.png" alt="Open the Codex Pet settings from the orange cat icon in the Windows notification area" width="100%">
</p>

The tray menu also provides **Refresh**, **Open logs**, and **Quit** actions without opening the project folder.

The settings UI saves to:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\settings.json
```

You can change visualization style, colors, opacity, pet-relative placement and
spacing, potion size, and hover readout colors and typography. The running helper
automatically reloads settings file changes.

## Privacy

The app reads these local Codex files:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` or `logs_1.sqlite`

It does not require an OpenAI API key and does not send pet images,
screenshots, prompts, repository contents, or spritesheets anywhere.

When language is set to `Auto (IP location)`, the app requests the caller's
country code from `https://api.country.is/`. The service necessarily receives
the public IP for the request, but the app stores only the returned two-letter
country code in a local 24-hour cache. Select Korean or English explicitly to
skip this lookup. If the lookup fails, the app falls back to the Windows UI
language.

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
Install Codex Pet Limit Rings for Windows from:
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
