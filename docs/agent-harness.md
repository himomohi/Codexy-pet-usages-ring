# Codexy Pet Agent Harness

This document is a local working harness for future Codex agents and subthreads.
Use it before touching the gamification, HUD, settings, release, or install flow.

## 2026-05-30 Gamification Session

### Scope Completed

- Added keyboard-count gamification beside the pet HUD.
- Added selectable gamification focus so level/growth and key-count combo HUD do not show at the same time.
- Reworked settings UI into clearer toggle and preview sections.
- Added reward chest HUD with hover/click feedback and a pop-up inventory panel.
- Added generic reward assets for font and theme unlocks.
- Reworked reward logic from common item drops to rare cosmetic unlocks.
- Localized reward/inventory labels for the runtime panel and settings summary.
- Improved click reliability with a low-level mouse hook and clearer hover border.
- Increased key counter responsiveness, then split the key counter timer from the heavier HUD frame loop.
- Fixed HUD overflow around the key counter, status text, chest icon, and badge.
- Refreshed the installed copy under `%LOCALAPPDATA%\CodexyPetUsagesRing` after runtime changes.

### Good Patterns To Repeat

- Validate repo code and the installed helper, not only source files.
- After editing runtime or settings files, run:

```powershell
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'src\CodexyPetUsagesRing.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | Format-List; exit 1 }
```

- Compile the embedded native C# hook block after hook changes:

```powershell
$src = Get-Content -LiteralPath 'src\CodexyPetUsagesRing.ps1' -Raw
$match = [regex]::Match($src, 'Add-Type @"\r?\n([\s\S]*?)\r?\n"@')
if (-not $match.Success) { throw 'native type block not found' }
Add-Type -TypeDefinition $match.Groups[1].Value
```

- Run release/install smoke before saying the work is ready:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\Test-Smoke.ps1
```

- Refresh the installed helper after source edits:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File bin\powershell\Install.ps1 -NoStartCodex
```

- Confirm the installed overlay process and latest log:

```powershell
$install = Join-Path $env:LOCALAPPDATA 'CodexyPetUsagesRing'
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like ('*' + $install + '*') } |
  Select-Object ProcessId,CommandLine |
  Format-List

$log = Join-Path $install 'logs\codexy-pet-usages-ring.log'
Get-Content -LiteralPath $log -Tail 40
```

- For visual changes, think in fixed bounds first: chip width, chip height, line height, icon bounds, hit bounds, and window width.
- Keep high-frequency behavior narrow. A fast timer for one small surface is safer than making the entire HUD loop fast.
- Keep user-visible counters centered with stable dimensions instead of letting text resize the layout.

### Mistakes To Avoid

- Do not trust source edits until `%LOCALAPPDATA%\CodexyPetUsagesRing` has been refreshed.
- Do not let PowerShell `-f` formatting receive an array accidentally. Use explicit comma-separated format arguments.
  Bad formatting caused the overlay to crash in a restart loop.
- Do not reuse legacy reward counters for new cosmetic unlocks.
  `totalDrops` previously showed old snack/gem/ticket/patch drops even when no new reward was unlocked.
- Do not make the full HUD run at 16ms just to make key counting feel instant.
  That raised CPU usage too much for a companion app. Use a key-counter-only timer.
- Do not commit source image sheets or local-only ignore files if smoke treats them as release-forbidden paths.
  Runtime-ready PNGs are OK; generated source sheets should stay untracked.
- Do not place layout compensation code inside the post-signature window update block unless the variables are in scope and part of the signature.
  A misplaced width correction briefly referenced variables from another function.
- Do not make reward assets pet-specific unless the user asks for pet-specific skins.
  Generic assets work better for reusable fonts/themes.
- Do not use a tiny hit target for visual inventory controls. Hover border and click bounds must match the thing the user sees.
- Do not let status text such as `Rest +` share a box sized only for digits. Two-line states need extra width and height.

### Verification Harness

Run this sequence for HUD/gamification changes:

```powershell
$files = @(
  'src\CodexyPetUsagesRing.ps1',
  'src\PetGrowth.ps1',
  'bin\powershell\Settings.ps1',
  'tools\Test-Smoke.ps1',
  'tools\ReleaseManifest.ps1'
)
foreach ($file in $files) {
  if (-not (Test-Path -LiteralPath $file)) { continue }
  $tokens = $null
  $errors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors)
  if ($errors.Count) {
    Write-Host "Parse failed: $file"
    $errors | Format-List
    exit 1
  }
}

$src = Get-Content -LiteralPath 'src\CodexyPetUsagesRing.ps1' -Raw
$match = [regex]::Match($src, 'Add-Type @"\r?\n([\s\S]*?)\r?\n"@')
if (-not $match.Success) { throw 'native type block not found' }
Add-Type -TypeDefinition $match.Groups[1].Value

powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\Test-Smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File bin\powershell\Install.ps1 -NoStartCodex
```

Then confirm:

```powershell
$install = Join-Path $env:LOCALAPPDATA 'CodexyPetUsagesRing'
$log = Join-Path $install 'logs\codexy-pet-usages-ring.log'
Get-Content -LiteralPath $log -Tail 20
```

Expected log line:

```text
Codex /pet overlay detected; showing usage visuals.
```

### Resource Harness

Use this after changing timer frequency, animation volume, hooks, or frame work:

```powershell
$install = Join-Path $env:LOCALAPPDATA 'CodexyPetUsagesRing'
$procInfo = Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like ('*' + $install + '*CodexyPetUsagesRing.ps1*') } |
  Select-Object -First 1

if ($null -eq $procInfo) { throw 'overlay process not found' }

$pidValue = [int]$procInfo.ProcessId
$p1 = Get-Process -Id $pidValue
$cpu1 = $p1.CPU
$ws1 = $p1.WorkingSet64
Start-Sleep -Seconds 5
$p2 = Get-Process -Id $pidValue
$cpu2 = $p2.CPU
$ws2 = $p2.WorkingSet64

[pscustomobject]@{
  PID = $pidValue
  CPUSecondsDelta = [math]::Round(($cpu2 - $cpu1), 3)
  ApproxSingleCoreCPUPercent = [math]::Round((($cpu2 - $cpu1) / 5.0) * 100.0, 2)
  WorkingSetMB = [math]::Round(($ws2 / 1MB), 1)
  WorkingSetDeltaMB = [math]::Round((($ws2 - $ws1) / 1MB), 2)
} | Format-List
```

Reference from this session:

| State | Approx single-core CPU | Working set |
| --- | ---: | ---: |
| Full HUD at 16ms | 14.37% | 108 MB |
| Key-counter-only 16ms timer | 8.75% | 78 MB |

### Runtime State Harness

Current gamification state lives here:

```powershell
$statePath = Join-Path (Join-Path $env:LOCALAPPDATA 'CodexyPetUsagesRing') 'gamification.json'
Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
```

When migrating rewards:

- Preserve `totalKeys`; it is typing history.
- Reset or normalize cosmetic unlock counters only when old item drops are being mistaken for new unlocks.
- `totalDrops` should reflect actual cosmetic unlocks, not legacy snack/gem/ticket/patch counts.
- `lastDropItem` should only be one of:
  - `fontPixel`
  - `fontTerminal`
  - `themeArcane`
  - `themeRoyal`

### Release Asset Harness

Runtime assets that should be installed:

- `assets/runtime/reward-chest.png`
- `assets/runtime/inventory-snack.png`
- `assets/runtime/inventory-gem.png`
- `assets/runtime/inventory-ticket.png`
- `assets/runtime/inventory-patch.png`
- `assets/runtime/unlock-font-pixel.png`
- `assets/runtime/unlock-font-terminal.png`
- `assets/runtime/unlock-theme-arcane.png`
- `assets/runtime/unlock-theme-royal.png`

Source sheets that should not be part of release packaging:

- `assets/runtime/inventory-items-source.png`
- `assets/runtime/cosmetic-unlocks-source.png`

`tools\ReleaseManifest.ps1` is the source of truth for release/install inclusion and exclusion.

### UI Harness

Before finishing any HUD change, inspect these cases mentally and, when possible, live:

- `battery` mode with `visibilityMode = always`
- `battery` mode with hover visibility
- `hudFocus = combo`
- `hudFocus = growth`
- key counter with 1, 2, 3, and 4+ digits
- key counter with status text such as `Rest +`, `Warmup`, `Flow`, `Rush`, `Papang`, `Cooldown`
- reward chest with zero unlocks
- reward chest after one unlock
- reward inventory panel open and closed
- mouse hover over chest should show hand cursor and highlighted border
- all visible elements must stay inside the WPF overlay bounds

### Decision Notes

- The user prefers visible, playful companion behavior over hidden counters.
- Store key counts only; never store key contents.
- Keep rewards rare enough to feel valuable, but make the feedback while typing frequent and visible.
- Use generic reward assets for fonts/themes unless a pet-specific skin is explicitly requested.
- Favor small, direct runtime changes over broad refactors unless the verification loop proves the abstraction helps.
