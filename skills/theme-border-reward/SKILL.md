---
name: theme-border-reward
description: Add or refine unlockable key-counter border theme cosmetics for Codexy pet usages ring. Use when adding themed borders, rarity tiers, counter frames, glow frames, or reward border art.
---

# Theme Border Reward Skill

Use this skill when adding an unlockable visual theme for the key counter border.

## Hard Rule

Always use imagen for the theme border artwork. The final shipped border may be post-processed for transparency, size, or edge cleanup, but the visual concept must originate from imagen.

Keep the original generated image in its generated-images folder. Copy only the optimized runtime PNG into `assets/runtime/`.

## Project Targets

- Runtime asset path: `assets/runtime/theme-<name>-border.png`
- Runtime state: `src/PetGrowth.ps1`
- Runtime mapping: `$CosmeticThemeKeys`, `$ThemeBorderPaths`, `$InventoryIconPaths` in `src/CodexyPetUsagesRing.ps1`
- Runtime render target: `$script:KeyCounterThemeBorder`
- Settings UI: `settings/index.html`
- Release coverage: `tools/ReleaseManifest.ps1`
- Smoke coverage: `tools/Test-Smoke.ps1`

## Naming

- Use unlock keys shaped like `themeForest`, `themeArcane`, or `themeCelestial`.
- Use asset files shaped like `theme-forest-border.png`.
- Use display labels with rarity-friendly names, such as `Mint Circuit Theme`.

## Imagen Prompt Requirements

The prompt must ask for:

- transparent background
- rectangular or rounded rectangular game HUD border
- center area transparent or visually open
- no text
- no full card background
- readable at key-counter chip size
- clean edges suitable for WPF image overlay

When matching a rarity tier:

- Common: readable, modest accents
- Rare: stronger color identity
- Epic: decorated but not noisy
- Legendary: animated-feeling high contrast
- Mythic: special but still readable behind text

## Implementation Checklist

1. Generate the border with imagen.
2. Post-process only for transparency, crop, scale, and edge cleanup.
3. Copy into `assets/runtime/theme-<name>-border.png`.
4. Add the key to `$CosmeticThemeKeys`.
5. Add the path to `$ThemeBorderPaths` and `$InventoryIconPaths`.
6. Add default and normalized inventory state in `src/PetGrowth.ps1`:
   - default inventory bool
   - bool read during normalization
   - theme key array
   - `cosmeticDropCount`
   - `activeTheme` validation
   - output inventory field
7. Add localized labels in `Get-InventoryUiText`.
8. Add the item to `Get-RandomDropItem` so it can actually drop, including weight and rarity intent.
9. Confirm `Add-InventoryDrop` activates or records the theme correctly after a drop.
10. Add settings UI support:
    - HTML item card
    - rarity class
    - i18n labels in all supported languages
    - `rewardThemes`
    - `rewardItems`
    - status id
    - unlock summary count
11. Ensure base rectangle border is hidden when a theme border is active.
12. Add release manifest and smoke-test markers.

## Verification

Run:

```powershell
$errors=$null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw src\CodexyPetUsagesRing.ps1), [ref]$errors) | Out-Null; if($errors){$errors; exit 1}
$errors=$null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw src\PetGrowth.ps1), [ref]$errors) | Out-Null; if($errors){$errors; exit 1}
node -e "const fs=require('fs'); const html=fs.readFileSync('settings/index.html','utf8'); const m=html.match(/<script>([\s\S]*)<\/script>\s*<\/body>/); if(!m) throw new Error('script not found'); new Function(m[1]);"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-ReleaseHarness.ps1 -AllowDirty -SkipInstallRefresh
```

After runtime or settings changes, refresh the installed helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1 -NoStartCodex
```
