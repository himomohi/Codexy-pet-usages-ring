# Changelog

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
- Prevented repository-local ignored files such as `.gitignore`, `settings.json`, `dist/`, `logs/`, and QA captures from being copied into fresh installs or release zips.

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
