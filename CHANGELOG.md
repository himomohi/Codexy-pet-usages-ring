# Changelog

## 0.1.22

### Changed

- Made the Codex `/pet` open state the authoritative trigger for showing the companion usage overlay.

### Fixed

- Prevented stale saved pet bounds from leaving the companion overlay visible after the Codex pet is closed.
- Added a regression check requiring an explicit `electron-avatar-overlay-open=true` state before rendering around the pet.

## 0.1.21

### Changed

- Made the recommended `Install.bat` flow register the helper at Windows login so the HUD remains available after a reboot.
- Updated Korean and English installation guidance for reboot-safe startup and the `-NoStartup` opt-out.

### Fixed

- Fixed the `-Startup` switch/folder-variable collision that prevented the Startup shortcut from being created.
- Prevented the login shortcut from launching Codex Desktop; the helper now waits quietly and shows the HUD when an existing `/pet` overlay appears.

## 0.1.20

### Added

- Added a generated Windows notification-area guide image showing the cat tray icon and its Settings, refresh, logs, and quit actions.
- Added illustrated Korean and English README guidance for opening Settings from the Windows taskbar notification area.

### Changed

- Updated release badges, download filenames, documentation, installed-copy verification, and packaging for version 0.1.20.

### Fixed

- Made heart-potion previews follow horizontal and vertical position sliders immediately, matching the live behavior already used by rings, bars, gauges, and corner frames.
- Stabilized frame-scheduled preview updates so style, size, position, color, opacity, and current-pet changes render before saving.

## 0.1.19

### Added

- Added five lightweight usage display styles, including reference-matched pixel-art potion orbs with adjustable size and placement.
- Added a selectable high-quality pixel-art heart potion style with independent runtime and settings-preview assets.
- Added a cute multi-resolution cat-face Windows notification-area icon with direct access to Settings and runtime actions.
- Added Korean/English automatic language selection, live settings preview, safe installed-copy synchronization, and visible source/install folder links.
- Added hover readouts that show the exact reset moment and continuously updated remaining time for both the 5-hour and weekly limits.

### Changed

- Streamlined the companion around usage visualization and removed the previous keyboard counter, pet-growth, reward, theme, and watcher subsystems.
- Made settings controls update the display preview immediately before saving, including style, size, position, color, and opacity changes.
- Documented how to open Settings from the Windows taskbar notification area.
- Reworked installation around `%LOCALAPPDATA%\CodexPetLimitRingsWin`, with explicit optional auto-start and settings-preserving updates through `Apply-Installed.bat`.
- Updated the settings UI, documentation, diagnostics, runtime naming, and release packaging for the streamlined Windows companion.

### Fixed

- Hardened process discovery, install markers, full uninstall cleanup, source/install linking, potion hover hit testing, ring sweep math, and transient usage-reset stabilization.

## 0.1.18

### Fixed

- Hid the inactive reward claim button when every reward is already unlocked so the reward popover no longer shows an unexplained gray bar.

## 0.1.17

### Added

- Added low-cost combo heat and reward charge meters to the gamification HUD, with settings toggles for each.
- Added a 1000-key reward chest claim button in the reward popover, with a 10-minute cooldown after each claim.
- Added a generated ready-state chest icon that appears on the HUD when a reward chest can be opened.
- Added an interactive settings sidebar with section-aware navigation for General, Growth, Rewards, Presets, Colors, Readout, Opacity, and Motion.

### Changed

- Kept the new meters event-driven and fixed-size so typing feedback stays responsive without adding new polling timers.
- Changed reward drops to roll only when the user opens a charged chest, deducting 1000 stored key points instead of resetting the counter.
- Wrapped reward popover status/button text so Korean and long charge values do not get clipped.
- Reworked the settings page from a pixel hero layout into a compact settings app with a left navigation rail, single-column control flow, and sticky HUD preview.

### Fixed

- Migrated already-typed key totals into the new reward charge bank so existing 1000+ users can see the ready chest icon immediately.
- Kept the ready chest icon tied to the 1000-key charge state so fully unlocked test inventories still show that the chest is charged.

## 0.1.16

### Added

- Added a root `Diagnose.bat` launcher so double-click users can run diagnostics without opening PowerShell manually.
- Served runtime reward assets from the local settings server so the settings inventory can show the actual unlock/effect images.

### Changed

- Made `Settings.bat` explain why its helper window stays open while the local settings page is active.
- Made `Uninstall.bat` ask whether to remove installed files when double-clicked, while keeping installed files by default for safety.
- Made the release harness explicitly fail deployment when reward unlock state keys appear in defaults, and remind final replies to confirm locked/reset deployment state.

### Fixed

- Fixed the settings reward summary API so unlocked paw effects and the active effect appear correctly in the settings inventory.

## 0.1.15

### Changed

- Reduced perceived keyboard counter latency by updating the visible count before reward drops and burst effects run.
- Deferred reward drop processing and typing burst effects to background dispatcher priority so typing feedback can render first.
- Reduced live usage polling pressure by polling less often, shortening the live usage timeout, and skipping usage refresh while typing is active.
- Capped batched paw and text burst effects so delayed input batches cannot flood the UI thread.

### Fixed

- Fixed slow keyboard counter feedback when live usage lookups timed out or returned 503 errors on the WPF UI thread.
- Fixed batched typing effects from delaying the next visible key count update.

## 0.1.14

### Added

- Added release announcement output to the release harness with separate Korean and English text blocks generated from the current changelog entry.
- Added deployment validation that fails the release if local reward or settings state files are included in the deploy package.

### Changed

- Repositioned the reward bag and reward picker popovers below their HUD anchors so they avoid covering the pet, counter, and other HUD elements.
- Kept deployment defaults locked by verifying release packages do not include inventory unlock state and keep gamification disabled by default.

### Fixed

- Fixed stale fully unlocked local test state from leaking into the deployment folder or release zip.
- Fixed reward bag popover placement so it no longer opens to the side over nearby HUD controls.

## 0.1.13

### Changed

- Replaced cat, dog, and bear paw reward effect sprites with cleaner animal-specific paws and no surrounding particle clutter.
- Changed the keyboard counter hook to count only the first key-down event for each held key, preventing OS key-repeat from inflating counts.

### Fixed

- Added key-up state tracking and hook reset cleanup so held keys cannot remain stuck as already counted after visibility or hook changes.
- Updated smoke checks to guard the no-repeat keyboard counter behavior and the refreshed reward effect assets.

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
