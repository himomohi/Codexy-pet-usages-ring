# Changelog

## 0.1.12

### Added

- Added realtime keyboard-count gamification with larger HUD feedback, delayed burst text, and low-probability reward drops.
- Added a clickable reward chest inventory with localized popover flows for fonts and theme cosmetics.
- Added five unlockable theme tiers: Forest, Arcane, Royal, Cyber, and Celestial, each with runtime border assets.
- Added a redesigned settings reward section that previews active loadout, locked/unlocked cosmetics, and the chest-to-picker flow.

### Changed

- Kept locked cosmetic themes unavailable until directly acquired through reward drops.
- Improved ring, battery, and badge layout spacing so key counters, reward chests, and usage readouts stay clear of the pet.
- Reduced key-count feedback latency while keeping the counter lightweight and event-driven.
- Excluded local reward state, source art, QA captures, and deployment staging files from release zips.

### Fixed

- Fixed reward chest hit testing so hover highlights, hand cursor, rapid clicks, and popover toggles behave consistently.
- Fixed key counter centering and themed-border rendering when the count grows or status text changes.
- Fixed settings and release smoke checks to cover reward assets, theme state, and deployment freshness.

## 0.1.11

### Added

- Added a lightweight `/pet` watcher that starts the companion helper only when the real Codex `/pet` overlay is visible.
- Added lifecycle cleanup so the helper stops when `/pet` closes or Codex Desktop exits.

### Changed

- Made the Windows tray icon opt-in with `-ShowTrayIcon` so the companion no longer looks like a second Codex app by default.
- Changed startup shortcuts to launch the watcher first, keeping the heavier WPF overlay dormant until `/pet` appears.

### Fixed

- Verified installed `settings/index.html` against the source file during install so settings-page edits cannot silently ship stale.
- Kept install contents aligned with the release zip by including every localized README variant.

## 0.1.10

### Changed

- Changed pet growth so today's XP fills directly from 5h usage progress instead of waiting on weekly usage thresholds.
- Clarified growth-mode copy in the pixel-art settings page: Light, Balanced, and Focused modes now explain their 5h usage targets and +30 XP daily cap.
- Updated growth hover readouts to show today's 5h progress, target, and earned XP.

### Fixed

- Hid ring, battery, badge, growth chip, and hover readouts immediately when the real `/pet` overlay closes.
- Kept weekly usage as a reset/depletion guard instead of letting it block normal 5h-based XP gains.

## 0.1.9

### Added

- Added opt-in pet growth gamification tied to the real `/pet` visibility and existing usage snapshots.
- Added usage-based growth modes for light, balanced, and focused Codex usage, with fun pet states such as Hyped, Warming Up, Overheated, and Cooldown.
- Added a pixel-art settings page with an animated pet hero, growth rules, and live HUD preview.
- Added a compact badge display mode and pixel-style theme presets.

### Changed

- Made pet growth respond to Codex usage amount instead of remaining quota, while pausing XP when remaining quota is near depletion.
- Restarted pet level and XP from Lv1 when the weekly quota resets.
- Kept growth HUD, badge, battery, and ring layouts from overlapping the real `/pet` avatar.

### Fixed

- Hardened the local settings server response handling for browser refresh and headless capture requests.
- Kept local `gamification.json` state out of release zips and installs.

## 0.1.8

### Fixed

- Made the root `Settings.bat` open the active installed settings file so saved changes apply to the running helper immediately.
- Added a smoke regression check to prevent the settings launcher from forcing repo-local settings again.

## 0.1.7

### Changed

- Renamed release zip, install directory, runtime marker, PID file, log file, shortcuts, and settings title to match Codexy pet usages ring.
- Renamed the overlay entry script to `CodexyPetUsagesRing.ps1` while keeping legacy process detection for existing installs.

## 0.1.6

### Fixed

- Preserved display and visibility settings when saving from the settings UI.
- Made the live preview visibly react to ring/battery and hover/always visibility choices.
- Kept settings select text readable after changing localized option values.

## 0.1.5

### Added

- Added a settings-selectable battery display mode for the Codex `/pet` usage overlay.
- Added a shared visibility setting for hover-only or always-visible usage displays.

### Fixed

- Kept battery hover mode visible while moving from the pet to the battery bars so usage readouts can be inspected.
- Improved settings select contrast so selected values stay readable on the dark settings surface.

## 0.1.4

### Added

- Added Japanese and Chinese localization for ring readouts, tray text, and settings UI.
- Extended automatic language selection to match Windows UI languages for Korean, Japanese, Chinese, and English.

## 0.1.3

### Added

- Added pet-hover ring visibility with configurable hover range and fade timing.
- Added localized ring/readout text with automatic Korean or English selection and settings override.
- Added settings controls and live preview for ring gap, hover range, fade timing, and language.

### Fixed

- Rendered usage readouts in separate topmost windows so they are not hidden behind the pet.

## 0.1.2

### Fixed

- Fixed release and install packaging so local development artifacts are not copied into fresh installs or release zips.
- Made installed startup, Start Menu, and settings shortcuts launch PowerShell hidden so helper terminal windows do not remain open.
- Made Codex Desktop auto-start prefer the Windows app identity through Explorer, detaching it from the helper launcher process.

## 0.1.1

### Added

- Added root `.bat` launchers for double-click install, start, stop, status, settings, and uninstall.
- Added a live settings preview for ring colors, track opacity, warning/caution colors, readout backgrounds, and text sizing.

### Fixed

- Hardened the local settings server with a random per-session token for settings API requests.
- Made CMD, Bash, and root `.bat` launchers automatically use the installed helper when an install exists.
- Replaced broad stop/status process matching with exact project-script path checks and PID file tracking.
- Required an install marker before `Uninstall.ps1 -RemoveFiles` recursively removes files.
- Made uninstall remove shortcuts only when they point at the selected install directory.

## 0.1.0

### Added

- Initial Windows companion overlay.
- Full circular translucent usage rings.
- Ring window is kept behind the Codex avatar overlay without clipping.
- Installer, startup shortcut, Start Menu shortcut, diagnostics, and release zip helper.
- CMD and Bash wrappers for basic terminal environments on Windows.
- HTML settings page for ring colors, opacity, and hover text sizing.
- Live settings reload from local `settings.json`.
- Codex Desktop auto-discovery and auto-start from install/start shortcuts.
