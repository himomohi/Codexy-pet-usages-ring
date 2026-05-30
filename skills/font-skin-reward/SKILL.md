---
name: font-skin-reward
description: Add or refine unlockable font skin rewards for Codexy pet usages ring. Use when adding font cosmetics, text color effects, glyph-style previews, or font reward inventory items.
---

# Font Skin Reward Skill

Use this skill when adding an unlockable font skin for the key counter and reward HUD.

## Hard Rule

Always use imagen for the font skin visual asset or preview badge. Even if the runtime font uses an installed Windows font family, the reward icon or preview asset must be generated with imagen.

Keep the original generated image in its generated-images folder. Copy the optimized runtime PNG into `assets/runtime/`.

## Project Targets

- Runtime asset path: `assets/runtime/unlock-font-<name>.png`
- Runtime state: `src/PetGrowth.ps1`
- Runtime font mapping: `Get-CosmeticFontFamily` in `src/CodexyPetUsagesRing.ps1`
- Runtime optional color/effect mapping: `Get-CosmeticTextRgb`, `Get-CosmeticAccentRgb`
- Settings UI: `settings/index.html`
- Release coverage: `tools/ReleaseManifest.ps1`
- Smoke coverage: `tools/Test-Smoke.ps1`

## Naming

- Use unlock keys shaped like `fontPixel`, `fontTerminal`, or `fontCandy`.
- Use asset files shaped like `unlock-font-pixel.png`.
- Use display labels that clearly describe the text style.

## Imagen Prompt Requirements

The prompt must ask for:

- transparent background
- small reward icon or preview badge
- no unrelated character or pet dependency
- stylized sample glyphs or abstract text blocks
- readable at inventory icon size
- no words that must be legible in the final image unless the user provides exact text

For cute font skins, ask for:

- rounded glyph blocks
- soft highlights
- playful color accents

For terminal or cyber font skins, ask for:

- crisp glyph blocks
- scanline or monitor-style accents
- high contrast

## Implementation Checklist

1. Generate the font reward icon with imagen.
2. Copy the optimized PNG into `assets/runtime/unlock-font-<name>.png`.
3. Add the unlock key to the font unlock list.
4. Add default and normalized inventory state in `src/PetGrowth.ps1`:
   - default inventory bool
   - bool read during normalization
   - font unlock key array or candidate list
   - `cosmeticDropCount`
   - `activeFont` validation
   - output inventory field
5. Add runtime font selection in `Get-CosmeticFontFamily`.
6. Add optional text/accent color behavior if the reward needs more than a font-family change.
7. Add localized labels in `Get-InventoryUiText`.
8. Add the item to `Get-RandomDropItem` so it can actually drop, including weight and rarity intent.
9. Confirm `Add-InventoryDrop` activates or records the font correctly after a drop.
10. Add settings UI support:
    - HTML item card
    - i18n labels in all supported languages
    - `rewardFonts`
    - `rewardItems`
    - status id
    - unlock summary count
11. Add release manifest and smoke-test markers.

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
