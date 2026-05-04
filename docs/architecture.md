# Architecture

Codex Pet Limit Rings for Windows is a companion overlay. It runs next to Codex
Desktop instead of modifying Codex itself.

## Data Flow

1. `bin\powershell\Start.ps1` auto-discovers Codex Desktop and starts it unless
   `-NoStartCodex` is used. Discovery checks a running `Codex.exe`, the
   `OpenAI.Codex` AppX package, the Start Menu AppID, and matching
   `WindowsApps` folders.
2. Codex Desktop writes avatar overlay state to:

   ```text
   %USERPROFILE%\.codex\.codex-global-state.json
   ```

3. The app polls `electron-avatar-overlay-bounds.mascot` on a low-frequency
   pet timer and reuses the cached parse while the state file timestamp is
   unchanged.
4. A transparent WPF window is positioned around that mascot rectangle.
5. The WPF window draws two circular arcs:

   - outer ring: 5h primary-window remaining usage
   - inner ring: weekly or secondary-window remaining usage

   Hover readouts are selected by ring radius. The outer readout shows the 5h
   percentage and reset time; the inner readout shows the weekly percentage and
   reset time.

6. The app uses Win32 `SetWindowPos` to place the ring window behind the Codex
   avatar overlay. The ring is never clipped.
7. Live usage is read from `https://chatgpt.com/backend-api/wham/usage` with the
   local Codex access token.
8. If live usage is unavailable, the app tries to parse local Codex log events
   of type `codex.rate_limits`.
9. Runtime styling is read from `settings.json`. The helper checks the file
   timestamp every 2 seconds and applies color, opacity, and readout text
   changes without restarting.

## Settings UI

- `bin\powershell\Settings.ps1` starts a temporary `127.0.0.1` HTTP server and opens
  `settings\index.html`.
- The HTML page reads `/api/settings`, writes `/api/settings`, and can reset
  values from `/api/defaults`.
- `settings.defaults.json` is shipped with the project. User edits go to
  `settings.json`, which is intentionally not overwritten by installer updates.
- The tray menu includes a Settings item when `bin\powershell\Settings.ps1` is present.

## Resource Use

- The pet detection timer defaults to 300 ms and only parses the Codex state
  JSON when the file timestamp changes.
- The animation timer idles at 300 ms, speeds up to 120 ms while usage values
  are visually animating, does not read files, and stops while `/pet` is closed.
- Ring geometry is redrawn only when the pet bounds change or the displayed
  usage value moves toward a new target.
- Hover text is refreshed at most once per second while the pointer is near a
  ring.
- Live usage polling defaults to 10 seconds to avoid aggressive background
  network and JSON processing.
- Z-order maintenance is throttled so the Win32 window scan does not run on
  every pet detection tick.
- The process sets below-normal priority and trims its working set after
  startup, then at a long maintenance interval.

## Why a Companion Overlay?

The Codex pet format currently uses static package assets such as `pet.json` and
`spritesheet.webp`. That format is good for animation frames, but it does not
provide a live UI layer that can draw dynamic usage state. A companion overlay
keeps the official pet package untouched while still showing directly around
the visible `/pet`.

## Windows Implementation

- PowerShell hosts the app and installer.
- `src\CodexAppDiscovery.ps1` centralizes Codex Desktop path/AppID detection.
- WPF draws the transparent ring window.
- WinForms provides the tray icon.
- Win32 interop makes the window click-through and places it behind Codex.
- Startup integration uses a normal `.lnk` shortcut in the user's Startup folder.
- The settings page uses a short-lived local HTTP server rather than a permanent
  web service.
