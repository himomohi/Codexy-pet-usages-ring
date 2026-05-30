---
name: paw-effect-reward
description: Add or refine keyboard reward burst effects for Codexy pet usages ring. Use when adding cat paw, sparkle, pop, papapang, or other reward effect assets and wiring them into the effect inventory.
---

# Effect Reward Skill

Use this skill when adding or changing an unlockable keyboard-count effect in this project, including paw, sparkle, pop, papapang, or other reward effects.

## Hard Rule

Always use imagen for the visual asset. Do not ship a manually drawn final effect asset unless it is only a technical cleanup of an imagen-generated source, such as trimming transparent padding, resizing, or palette normalization.

Keep the original generated image in its generated-images folder. Copy the approved result into the project asset path.

## Project Targets

- Runtime asset path: `assets/runtime/effect-<key>.png`
- Runtime state: `src/PetGrowth.ps1`
- Runtime behavior: `src/CodexyPetUsagesRing.ps1`
- Settings UI: `settings/index.html`
- Release coverage: `tools/ReleaseManifest.ps1`
- Smoke coverage: `tools/Test-Smoke.ps1`

## Naming

- Use unlock keys shaped like `effectPawBurst`, `effectStarPop`, or `effectSparkRain`.
- Use asset files shaped like `effect-paw-burst.png`.
- Use UI labels that describe the effect, not a specific pet.

## Imagen Prompt Requirements

The prompt must ask for:

- transparent background
- isolated game effect sprite or sprite icon
- no text
- no frame or card background
- style matching the current reward HUD
- enough contrast at 32-96 px display sizes

For paw effects, ask for:

- white cat paw
- pink toe beans
- cute pixel-art or game-sprite shape
- sparkle or pop fragments around the paw

## Implementation Checklist

1. Generate the effect asset with imagen.
2. Copy the selected PNG into `assets/runtime/`.
3. Add the unlock key to `$CosmeticEffectKeys`.
4. Add the asset path to `$InventoryIconPaths`.
5. Add default and normalized inventory state in `src/PetGrowth.ps1`:
   - default inventory bool
   - bool read during normalization
   - effect key array
   - `cosmeticDropCount`
   - `activeEffect` validation
   - output inventory field
6. Add localized labels and picker text in `Get-InventoryUiText`.
7. Add the item to `Get-RandomDropItem` so it can actually drop, including weight and rarity intent.
8. Confirm `Add-InventoryDrop` activates or records the effect correctly after a drop.
9. Wire the visual effect into `Start-KeyBurstEffect` or a dedicated helper.
10. Keep normal typing effects small and predictable.
11. Keep milestone effects explicitly milestone-gated.
12. Add settings UI support:
    - HTML item card
    - i18n labels in all supported languages
    - `rewardEffects`
    - `rewardItems`
    - status id
    - unlock summary count
13. Add release manifest and smoke-test markers.

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
