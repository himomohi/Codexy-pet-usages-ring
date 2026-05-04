<p align="center">
  <img src="docs/assets/codex-pet-limit-rings-win-hero.png" alt="Codex Pet Limit Rings for Windows hero banner showing the live pet usage rings" width="100%">
</p>

<h1 align="center">Codex Pet Limit Rings for Windows</h1>

<p align="center">
  A transparent Windows companion overlay that follows your Codex <code>/pet</code> and shows live 5h and weekly usage rings.
</p>

<p align="center">
  <a href="VERSION"><img alt="Version 0.1.1" src="https://img.shields.io/badge/version-0.1.1-3CEBBD?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-56B2FF?style=for-the-badge"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=for-the-badge">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-3CEBBD?style=for-the-badge">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a>
  · <a href="#install">Install</a>
  · <a href="#customize">Customize</a>
  · <a href="#data-and-privacy">Data And Privacy</a>
  · <a href="README.ko.md">한국어</a>
</p>

Windows companion overlay that draws translucent Codex usage-limit rings around
the visible `/pet` avatar.

This project follows the companion-app model from
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings),
but is built for Windows with PowerShell, WPF, and Win32 window positioning.

[한국어 README 보기](README.ko.md)

## What It Does

- Current version: `0.1.1`.
- Draws a complete circular ring around the current Codex `/pet` avatar.
- Auto-discovers the installed Codex Desktop app and starts it when the helper starts.
- Automatically waits for `/pet` and shows the rings when the pet overlay opens.
- Keeps the ring behind the Codex avatar overlay, so the pet and its message stay in front.
- Shows per-ring hover readouts: outer ring is the 5h limit, inner ring is the weekly limit.
- Uses a translucent, click-through WPF window. It does not intercept mouse input.
- Reads Codex avatar bounds from `%USERPROFILE%\.codex\.codex-global-state.json`.
- Reads live usage from `https://chatgpt.com/backend-api/wham/usage` using the local Codex `auth.json` token.
- Falls back to recent local `codex.rate_limits` logs when Python and Codex logs are available.
- Installs into `%LOCALAPPDATA%\CodexPetLimitRingsWin` and can register a Windows startup shortcut.

## What It Does Not Do

- It does not patch the Codex Desktop app.
- It does not modify `pet.json`, `spritesheet.webp`, or any pet package.
- It does not create duplicate pets.
- It does not clip or cut the ring to avoid messages. The ring remains a full circle.
- It is not an official OpenAI or Codex feature.

## License And Attribution

This Windows project is a derivative/fork of
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings),
which is distributed under the MIT License.

The original MIT copyright notice is preserved in [LICENSE](LICENSE), together
with the Windows project notice. Additional attribution is kept in
[NOTICE.md](NOTICE.md).

## Requirements

- Windows 10 or Windows 11.
- Codex Desktop installed and signed in. The installer can discover the Store/AppX install automatically.
- PowerShell 5.1 or newer. Windows PowerShell is enough.
- The Codex `/pet` overlay must be open for the ring to appear.

Python is optional. It is only used for the local SQLite log fallback. Live usage
does not require Python.

## Quick Start

Install the rings and register startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

The installer tries to find and start Codex Desktop automatically. Then use
`/pet` normally. No pet setup step is required. If the ring app starts before
`/pet` is open, it simply waits and appears automatically when `/pet` opens.

After the first install, the ring helper starts immediately. The installer also
adds a Windows Startup shortcut, so on the next Windows login it starts again
automatically, detects Codex Desktop, launches Codex if needed, and waits until
`/pet` is visible.

Run without installing:

```powershell
.\bin\powershell\Start.ps1
```

Uninstall everything the installer adds:

```powershell
.\bin\powershell\Uninstall.ps1
```

## Give This Repo To An AI Agent

If you want another AI/Codex agent to install this without doing separate web
searches, give it this repository link and paste this instruction:

Repository:

```text
https://github.com/himomohi/Codexy-pet-usages-ring
```

```text
Use only this repository URL as the source of truth:
https://github.com/himomohi/Codexy-pet-usages-ring

Do not search the web for another installer or another pet package. This is the
Windows version of Codex Pet Limit Rings.

If this repository is not already available locally, clone it first:

git clone https://github.com/himomohi/Codexy-pet-usages-ring.git
cd Codexy-pet-usages-ring

Install it on this Windows PC from the repository root. Prefer:

powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1

If the user is in CMD, use bin\cmd\install.cmd. If the user is in Git Bash,
MSYS, Cygwin, or WSL on Windows, use sh ./bin/bash/install.sh.

After installing, verify with:

.\bin\powershell\Status.ps1
.\bin\powershell\Diagnose.ps1

Confirm that the helper is running, the Windows Startup shortcut exists, Codex
Desktop is detected or started, and the ring waits for the Codex /pet overlay.
Do not patch Codex Desktop, app.asar, pet.json, spritesheet.webp, or any pet
package. Do not create duplicate pets.
```

For privacy-sensitive environments, also ask the agent to read
[Data And Privacy](#data-and-privacy), [SECURITY.md](SECURITY.md), and
[NOTICE.md](NOTICE.md) before installing.

## Install

Use the command that matches your terminal.

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

Windows CMD:

```bat
bin\cmd\install.cmd
```

Git Bash, MSYS, Cygwin, or WSL on Windows:

```sh
sh ./bin/bash/install.sh
```

The installer copies the project to:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin
```

It also creates:

- a Windows Startup shortcut
- a Start Menu shortcut
- a hidden background ring process

Default first-install behavior:

- starts the ring helper immediately
- registers the helper for Windows startup
- auto-detects and starts Codex Desktop when possible
- waits quietly until the Codex `/pet` overlay opens

During install and every later helper start, the app searches for Codex Desktop
in this order: an already-running `Codex.exe`, the `OpenAI.Codex` AppX package,
the Start Menu AppID, then matching `WindowsApps` folders. If found, it starts
Codex Desktop before starting the ring helper.

Disable Codex Desktop auto-start:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
```

Use an explicit Codex Desktop path or AppID when auto-discovery is not enough:

```powershell
.\bin\powershell\Install.ps1 -CodexAppPath "C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe"
.\bin\powershell\Install.ps1 -CodexAppId "OpenAI.Codex_2p2nqsd0c76g0!App"
```

Portable install without shortcuts:

```powershell
.\bin\powershell\Install.ps1 -NoStartup -NoStartMenu -NoStart
```

The same options can be passed through CMD or Bash:

```bat
bin\cmd\install.cmd -NoStartup -NoStartMenu -NoStart
```

```sh
sh ./bin/bash/install.sh -NoStartup -NoStartMenu -NoStart
```

## Start, Stop, Status

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
```

Windows CMD:

```bat
bin\cmd\start.cmd
bin\cmd\stop.cmd
bin\cmd\status.cmd
bin\cmd\settings.cmd
```

Bash:

```sh
sh ./bin/bash/start.sh
sh ./bin/bash/stop.sh
sh ./bin/bash/status.sh
sh ./bin/bash/settings.sh
```

## Customize

Open the HTML settings page:

```powershell
.\bin\powershell\Settings.ps1
```

The settings UI runs on `127.0.0.1`, saves to:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\settings.json
```

The running ring helper reloads `settings.json` automatically. The first
supported controls are:

- ring colors: outer 5h, inner weekly, warning, caution, and track
- readout colors: text and tooltip backgrounds
- opacity: rings, track, readout background, and readout text
- text: hover readout font size and line height

## Automatic Detection

The background app keeps running even when `/pet` is closed. On startup it
auto-detects and starts Codex Desktop unless `-NoStartCodex` is used. It then
polls Codex Desktop's avatar overlay state every 300 ms by default, hides the
ring while `/pet` is closed, and shows it automatically when `/pet` opens again.
This also means the app can start at Windows login before Codex or `/pet` is
ready.

Usage values are polled every 10 seconds by default. When a new value arrives,
the ring stays visible and animates toward the new percentage on the normal
frame loop. If a usage request fails, the last known value remains on screen
instead of clearing or hiding the ring.

The app keeps CPU and memory use low by separating the lightweight animation
loop from `/pet` detection, caching the Codex state file until it changes, and
redrawing ring geometry only when the pet bounds or displayed usage actually
change. The animation loop is stopped while `/pet` is closed, runs at a slower
idle cadence while nothing is moving, and speeds up only while the gauge is
animating toward a new value. The helper also runs at below-normal process
priority and trims its working set after startup, then occasionally during long
sessions.

Hovering near the outer ring shows the 5h limit percentage and reset time.
Hovering near the inner ring shows the weekly limit percentage and reset time.
Reset times use the local Windows time zone and include both remaining duration
and clock time when the usage source provides reset metadata.

You can confirm this behavior in:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\logs\rings.log
```

Look for:

```text
Codex /pet overlay is not visible; waiting automatically.
Codex /pet overlay detected; showing rings.
```

Run diagnostics:

```powershell
.\bin\powershell\Diagnose.ps1
```

Optionally test the live usage endpoint:

```powershell
.\bin\powershell\Diagnose.ps1 -TestLiveUsage
```

## Uninstall

Remove shortcuts and stop the background process:

```powershell
.\bin\powershell\Uninstall.ps1
```

Remove installed files too:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

## Data And Privacy

The app reads local Codex files:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` or `logs_1.sqlite`

It does not require an OpenAI API key. It does not send pet images,
screenshots, prompts, repository contents, or spritesheets anywhere.

The settings page uses a temporary local server bound to `127.0.0.1` and writes
only the local `settings.json` file. It does not send settings to any remote
server.

For live usage, it sends the local Codex access token only to:

```text
https://chatgpt.com/backend-api/wham/usage
```

Disable live network usage with:

```powershell
.\bin\powershell\Install.ps1 -NoLiveUsage
.\bin\powershell\Start.ps1 -NoLiveUsage
```

When live usage is disabled, the app tries the local log fallback. If no useful
local rate-limit event exists, the ring remains visible but may not show current
usage values.

## Project Shape

```text
codex-pet-limit-rings-Win/
  README.md
  README.ko.md
  CHANGELOG.md
  LICENSE
  NOTICE.md
  VERSION
  settings.defaults.json
  settings/
    index.html
  bin/
    powershell/
      Install.ps1
      Start.ps1
      Stop.ps1
      Status.ps1
      Settings.ps1
      Diagnose.ps1
      Uninstall.ps1
    cmd/
      install.cmd
      start.cmd
      stop.cmd
      status.cmd
      settings.cmd
      diagnose.cmd
      uninstall.cmd
    bash/
      install.sh
      start.sh
      stop.sh
      status.sh
      settings.sh
      diagnose.sh
      uninstall.sh
  src/
    CodexAppDiscovery.ps1
    CodexPetLimitRings.ps1
  docs/
    assets/
      codex-pet-limit-rings-win-hero.png
      current-pet-usage-capture.png
      imagegen-hero-background.png
    architecture.md
    troubleshooting.md
  tools/
    New-ReleaseZip.ps1
  SECURITY.md
```

## Build a Release Zip

```powershell
.\tools\New-ReleaseZip.ps1
```

The zip is written to `dist/`.

## Known Limitations

- Codex does not currently expose an official public usage-limit API for this overlay.
- The live usage endpoint can change because it is not a documented third-party API.
- The overlay follows the Codex avatar bounds stored by the Desktop app. If Codex changes that state shape, the app may need an update.
- The ring appears only while `/pet` is open.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).
