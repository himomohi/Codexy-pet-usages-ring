param(
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot "ReleaseManifest.ps1")
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codexy-pet-usages-ring-smoke-" + [Guid]::NewGuid().ToString("N"))
$releaseOut = Join-Path $tempRoot "release"
$installRoot = Join-Path $tempRoot "install"
$fixtures = @()

function Add-Fixture {
  param([string]$RelativePath, [string]$Content = "smoke")
  $path = Join-Path $root ($RelativePath -replace '/', '\')
  if (Test-Path -LiteralPath $path) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
  $script:fixtures += $path
}

function Test-ForbiddenPath {
  param([string]$Path)
  $normalized = $Path -replace '\\', '/'
  return (Test-CodexPetReleasePathExcluded -RelativePath $normalized)
}

function Assert-NoForbiddenPaths {
  param([string[]]$Paths, [string]$Scope)
  $bad = @($Paths | Where-Object { Test-ForbiddenPath -Path $_ })
  if ($bad.Count -gt 0) {
    throw "$Scope contains forbidden paths: $($bad -join ', ')"
  }
}

function Assert-InstalledFileMatches {
  param([string]$InstallRoot, [string]$RelativePath)
  $normalized = $RelativePath -replace '/', '\'
  $source = Join-Path $root $normalized
  $installed = Join-Path $InstallRoot $normalized
  if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) {
    throw "Temp install is missing required file: $RelativePath"
  }

  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
  $installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installed).Hash
  if ($sourceHash -ne $installedHash) {
    throw "Temp install file does not match source: $RelativePath"
  }
}

function Assert-ZipFileMatches {
  param($Archive, [string]$RelativePath)
  $normalized = $RelativePath -replace '\\', '/'
  $entry = $Archive.Entries | Where-Object { ($_.FullName.TrimEnd("/") -replace '\\', '/') -eq $normalized } | Select-Object -First 1
  if (-not $entry) {
    throw "Release zip is missing required file: $RelativePath"
  }

  $source = Join-Path $root ($normalized -replace '/', '\')
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Release manifest required file is missing from source: $RelativePath"
  }

  $stream = $entry.Open()
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $zipHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
  if ($sourceHash -ne $zipHash) {
    throw "Release zip file does not match source: $RelativePath"
  }
}

function Assert-VersionMetadata {
  $version = (Get-Content -Raw -LiteralPath (Join-Path $root "VERSION")).Trim()
  if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must use MAJOR.MINOR.PATCH format. Found: $version"
  }

  $changelog = Get-Content -LiteralPath (Join-Path $root "CHANGELOG.md")
  $latest = $changelog | Where-Object { $_ -match '^##\s+(\d+\.\d+\.\d+)\s*$' } | Select-Object -First 1
  if (-not $latest -or $latest -notmatch "^##\s+$([regex]::Escape($version))\s*$") {
    throw "Top CHANGELOG.md version must match VERSION $version."
  }

  foreach ($readmeName in @("README.md", "README.ko.md")) {
    $readme = Get-Content -Raw -LiteralPath (Join-Path $root $readmeName)
    if ($readme -notmatch [regex]::Escape("Version $version") -or $readme -notmatch [regex]::Escape("version-$version-")) {
      throw "$readmeName version badge must match VERSION $version."
    }
  }

  return $version
}

function Assert-SettingsLauncherUsesActiveInstall {
  $settingsLauncher = Get-Content -Raw -LiteralPath (Join-Path $root "Settings.bat")
  if ($settingsLauncher -match 'CODEX_PET_USE_REPO') {
    throw "Settings.bat must not force repo settings. It should let bin\\cmd\\settings.cmd resolve the active install so saved settings apply to the running helper."
  }
}

function Assert-SettingsDisplayModes {
  $settingsScriptPath = Join-Path $root "bin\powershell\Settings.ps1"
  $settingsScript = Get-Content -Raw -LiteralPath $settingsScriptPath
  $marker = "`r`n`$projectRoot = Get-ProjectRoot"
  $markerIndex = $settingsScript.IndexOf($marker)
  if ($markerIndex -lt 0) {
    $marker = "`n`$projectRoot = Get-ProjectRoot"
    $markerIndex = $settingsScript.IndexOf($marker)
  }
  if ($markerIndex -lt 0) {
    throw "Could not locate Settings.ps1 runtime boundary for normalization smoke test."
  }

  . ([scriptblock]::Create($settingsScript.Substring(0, $markerIndex)))

  $defaults = Get-NormalizedSettings ((Get-Content -Raw -LiteralPath (Join-Path $root "settings.defaults.json")) | ConvertFrom-Json)
  if ($defaults.displayMode -ne "ring") {
    throw "Default settings displayMode should remain ring. Found: $($defaults.displayMode)"
  }
  if ($defaults.gamification.enabled -ne $false) {
    throw "Default gamification.enabled should remain false."
  }
  if ($defaults.gamification.growthMode -ne "balanced") {
    throw "Default gamification.growthMode should be balanced. Found: $($defaults.gamification.growthMode)"
  }
  if ($defaults.gamification.hudFocus -ne "growth") {
    throw "Default gamification.hudFocus should be growth. Found: $($defaults.gamification.hudFocus)"
  }
  if ($defaults.gamification.showGrowthChip -ne $true -or $defaults.gamification.showHoverReadout -ne $true) {
    throw "Default gamification chip/readout settings should remain true."
  }
  if ($defaults.gamification.showKeyCounter -ne $true -or $defaults.gamification.showKeyEffects -ne $true) {
    throw "Default key counter/effect settings should remain true."
  }

  $badgeSettings = Get-NormalizedSettings ([PSCustomObject]@{ displayMode = "badge" })
  if ($badgeSettings.displayMode -ne "badge") {
    throw "Settings normalizer should preserve displayMode=badge. Found: $($badgeSettings.displayMode)"
  }
  if ($badgeSettings.gamification.enabled -ne $false) {
    throw "Settings normalizer should default missing gamification.enabled to false."
  }

  $invalidSettings = Get-NormalizedSettings ([PSCustomObject]@{ displayMode = "sparkle" })
  if ($invalidSettings.displayMode -ne "ring") {
    throw "Invalid displayMode should fall back to ring. Found: $($invalidSettings.displayMode)"
  }
  $comboFocus = Get-NormalizedSettings ([PSCustomObject]@{ gamification = [PSCustomObject]@{ hudFocus = "combo" } })
  if ($comboFocus.gamification.hudFocus -ne "combo") {
    throw "Settings normalizer should preserve gamification.hudFocus=combo."
  }
  $invalidGrowth = Get-NormalizedSettings ([PSCustomObject]@{ gamification = [PSCustomObject]@{ enabled = "maybe"; growthMode = "chaos"; hudFocus = "both"; showGrowthChip = "no"; showHoverReadout = "yes" } })
  if ($invalidGrowth.gamification.enabled -ne $false) {
    throw "Invalid gamification.enabled should fall back to false."
  }
  if ($invalidGrowth.gamification.growthMode -ne "balanced") {
    throw "Invalid gamification.growthMode should fall back to balanced."
  }
  if ($invalidGrowth.gamification.hudFocus -ne "growth") {
    throw "Invalid gamification.hudFocus should fall back to growth."
  }
  if ($invalidGrowth.gamification.showGrowthChip -ne $false -or $invalidGrowth.gamification.showHoverReadout -ne $true) {
    throw "Boolean gamification values should normalize from yes/no strings."
  }

  $runtimeScript = Get-Content -Raw -LiteralPath (Join-Path $root "src\CodexyPetUsagesRing.ps1")
  foreach ($needle in @("function Update-KeyComboState", "function Get-KeyComboMultiplier", "Rest +", "Cooldown", 'LastKeyCounterIdleSyncAt')) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Key counter combo runtime marker is missing: $needle"
    }
  }
  foreach ($needle in @("function Add-InventoryDrop", "function Get-InventoryHudText", "function Get-InventoryReadoutText", "function Get-InventoryUiText", "function Update-InventoryReadoutContent", "function Set-ActiveInventoryUnlock", "function Test-InventoryUnlockActive", "function Set-KeyCounterBaseBorderVisibility", "function Show-InventoryReadout", "function Show-InventoryPicker", "function New-InventoryCategoryCell", "function New-PawBurstParticle", "function Toggle-InventoryReadout", "function Hide-InventoryReadout", "function Test-InventoryReadoutOpen", "function Set-InventoryHoverHighlight", "function Test-CursorInInventoryRange", "function Update-MouseClickHook", "function Get-ConsumedLeftMouseClickCursor", "function Invoke-InventoryToggle", "SetWindowsHookExMouse", "InstallMouseClickCounter", "UninstallMouseClickCounter", "ConsumeLeftMouseClick", "MouseHookCallback", "WH_KEYBOARD_LL", "WH_MOUSE_LL", "WM_KEYUP", "WM_SYSKEYUP", "KBDLLHOOKSTRUCT", "keyDownStates", "ResetKeyboardDownStates", "WM_LBUTTONDOWN", "IsLeftMouseButtonDown", "ConsumeLeftMouseButtonClick", '0x0001', "ShowHandCursor", "IDC_HAND", "handCursor", "InventoryHitBounds", "InventoryHoverBorder", "InventoryReadoutPinned", "InventoryReadoutWindow", "InventoryPickerWindow", "InventoryReadoutGrid", "InventoryPickerGrid", "InventoryIcon", "InventoryCountBackground", "Add_MouseLeftButtonUp", 'New-ReadoutWindow -Content $script:InventoryReadoutBorder -ClickThrough $false', 'New-ReadoutWindow -Content $script:InventoryPickerBorder -ClickThrough $false', "FontCategory", "ThemeCategory", "EffectCategory", "PickerHintTheme", "PickerHintEffect", "Active", "Select", "reward-chest.png", "unlock-font-pixel.png", "unlock-font-terminal.png", "unlock-theme-arcane.png", "unlock-theme-royal.png", "effect-paw-burst.png", "effect-bear-paw-burst.png", "effect-dog-paw-burst.png", "theme-forest-border.png", "theme-arcane-border.png", "theme-royal-border.png", "theme-cyber-border.png", "theme-celestial-border.png", "ThemeBorderPaths", "KeyCounterThemeBorder", "CosmeticEffectKeys", "effectPawBurst", "effectBearPaw", "effectDogPaw", "activeEffect", "PawBurstImageSources", "themeForest", "themeCyber", "themeCelestial", "rewardRolls", "activeTheme")) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Inventory reward runtime marker is missing: $needle"
    }
  }
  foreach ($needle in @("ScaleTransform", "RenderTransformOrigin", "LineStackingStrategy", 'BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty')) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Key counter centering marker is missing: $needle"
    }
  }
  foreach ($needle in @("System.Windows.Documents.Run", "System.Windows.Documents.LineBreak", '$statusRun.FontSize = 13.2')) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Key counter status layout marker is missing: $needle"
    }
  }
  $growthScript = Get-Content -Raw -LiteralPath (Join-Path $root "src\PetGrowth.ps1")
  foreach ($needle in @("inventory = [ordered]@", "fontPixel", "fontTerminal", "themeForest", "themeArcane", "themeRoyal", "themeCyber", "themeCelestial", "effectPawBurst", "effectBearPaw", "effectDogPaw", "activeFont", "activeTheme", "activeEffect", "rewardRolls", "totalDrops", "totalKeys", "lastDropItem")) {
    if ($growthScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Inventory state marker is missing: $needle"
    }
  }
  foreach ($needle in @('GamificationHudFocus -eq "growth"', 'GamificationHudFocus -eq "combo"', "function Get-GrowthChipWidth")) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Gamification HUD focus marker is missing: $needle"
    }
  }
  foreach ($needle in @('$batteryHudRowHeight', '12.0 + $batteryHudRowHeight + 8.0', 'Get-KeyCounterChipHeight', '$hudRowHeight + 56.0')) {
    if ($runtimeScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Battery key counter spacing marker is missing: $needle"
    }
  }
  if ($runtimeScript.IndexOf('$script:Style.ShowGrowthChip' + "`r`n  ) {", [System.StringComparison]::Ordinal) -ge 0) {
    throw "Growth chip visibility must use Test-GrowthHudVisible so combo focus cannot show level chip."
  }

  $settingsHtml = Get-Content -Raw -LiteralPath (Join-Path $root "settings\index.html")
  foreach ($needle in @("focus-control", "data-focus-panel=`"growth`"", "data-focus-panel=`"combo`"", "syncFocusPanels", "hudFocusNote", "inventory-summary", "reward-loadout", "reward-selector", "data-reward-tab=`"fonts`"", "data-reward-tab=`"effects`"", "data-reward-panel=`"themes`"", "data-reward-panel=`"effects`"", "syncRewardPanels", "activeFontName", "activeThemeName", "activeEffectName", "rewardRollCount", "inventoryFontPixel", "inventoryThemeForest", "inventoryThemeArcane", "inventoryThemeCyber", "inventoryThemeCelestial", "inventoryEffectPawBurst", "inventoryEffectBearPaw", "inventoryEffectDogPaw")) {
    if ($settingsHtml.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Settings HUD focus UI marker is missing: $needle"
    }
  }
  foreach ($needle in @("function Read-GamificationStateSummary", "gamificationState = Read-GamificationStateSummary", "function Open-SettingsUrl", "msedge.exe")) {
    if ($settingsScript.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Settings inventory API marker is missing: $needle"
    }
  }
  foreach ($asset in @("reward-chest.png", "inventory-snack.png", "inventory-gem.png", "inventory-ticket.png", "inventory-patch.png", "unlock-font-pixel.png", "unlock-font-terminal.png", "unlock-theme-arcane.png", "unlock-theme-royal.png", "effect-paw-burst.png", "effect-bear-paw-burst.png", "effect-dog-paw-burst.png", "theme-forest-border.png", "theme-arcane-border.png", "theme-royal-border.png", "theme-cyber-border.png", "theme-celestial-border.png")) {
    if (-not (Test-Path -LiteralPath (Join-Path $root "assets\runtime\$asset") -PathType Leaf)) {
      throw "Inventory runtime asset is missing: $asset"
    }
  }
  $releaseManifest = Get-Content -Raw -LiteralPath (Join-Path $root "tools\ReleaseManifest.ps1")
  foreach ($needle in @('"assets"', '"assets/runtime/reward-chest.png"', '"assets/runtime/unlock-font-pixel.png"', '"assets/runtime/unlock-font-terminal.png"', '"assets/runtime/unlock-theme-arcane.png"', '"assets/runtime/unlock-theme-royal.png"', '"assets/runtime/effect-paw-burst.png"', '"assets/runtime/effect-bear-paw-burst.png"', '"assets/runtime/effect-dog-paw-burst.png"', '"assets/runtime/theme-forest-border.png"', '"assets/runtime/theme-arcane-border.png"', '"assets/runtime/theme-royal-border.png"', '"assets/runtime/theme-cyber-border.png"', '"assets/runtime/theme-celestial-border.png"')) {
    if ($releaseManifest.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Reward chest release manifest marker is missing: $needle"
    }
  }
  $releaseHarness = Get-Content -Raw -LiteralPath (Join-Path $root "tools\Invoke-ReleaseHarness.ps1")
  foreach ($needle in @("Assert-ReleaseMetadata", "New-VerifiedDeployZip", "Invoke-InstallRefresh", "Publish-GitHubRelease", '"release", "create"', '"release", "upload"', "Codexy-pet-usages-ring-`$TargetVersion.zip")) {
    if ($releaseHarness.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
      throw "Project release harness marker is missing: $needle"
    }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root "skills\README.md") -PathType Leaf)) {
    throw "Project skills README is missing."
  }
  foreach ($skillPath in @(
    "skills/paw-effect-reward/SKILL.md",
    "skills/theme-border-reward/SKILL.md",
    "skills/font-skin-reward/SKILL.md"
  )) {
    $fullSkillPath = Join-Path $root ($skillPath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullSkillPath -PathType Leaf)) {
      throw "Project reward skill is missing: $skillPath"
    }
    $skillText = Get-Content -Raw -LiteralPath $fullSkillPath
    foreach ($needle in @("---", "name:", "description:", "Always use imagen", "assets/runtime", "src/PetGrowth.ps1", "src/CodexyPetUsagesRing.ps1", "settings/index.html", "tools/ReleaseManifest.ps1", "tools/Test-Smoke.ps1", "Get-RandomDropItem", "Add-InventoryDrop", "Invoke-ReleaseHarness.ps1", "Install.ps1 -NoStartCodex")) {
      if ($skillText.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Project reward skill marker is missing from ${skillPath}: $needle"
      }
    }
  }
}

function Assert-PetGrowthCalculations {
  $growthScriptPath = Join-Path $root "src\PetGrowth.ps1"
  . $growthScriptPath

  $start = [datetime]"2026-05-11T09:00:00"
  $state = New-PetGrowthState -Now $start
  $state.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $result = Update-PetGrowthState `
    -State $state `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($result.State.totalXp -ne 30 -or $result.State.todayXp -ne 30 -or [int]$result.State.todayPrimaryUsedPercent -ne 45) {
    throw "5h usage progress should fill today's XP from primary usage."
  }

  $low = Update-PetGrowthState `
    -State $result.State `
    -PrimaryRemaining 9 `
    -SecondaryRemaining 70 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(120) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -Enabled $true
  if ($low.State.totalXp -ne 30 -or $low.State.condition -ne "sleepy") {
    throw "Low remaining usage should stop XP and mark the pet sleepy."
  }

  $primaryProgressState = New-PetGrowthState -Now $start
  $primaryProgressState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $primaryProgress = Update-PetGrowthState `
    -State $primaryProgressState `
    -PrimaryRemaining 95 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(10) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  $primaryProgressNext = Update-PetGrowthState `
    -State $primaryProgress.State `
    -PrimaryRemaining 80 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(20) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($primaryProgress.State.totalXp -ne 3 -or $primaryProgressNext.State.totalXp -ne 15 -or $primaryProgressNext.AwardedXp -ne 12) {
    throw "Increasing 5h usage should award XP even when weekly usage is unchanged."
  }

  $lightState = New-PetGrowthState -Now $start
  $lightState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $light = Update-PetGrowthState `
    -State $lightState `
    -PrimaryRemaining 75 `
    -SecondaryRemaining 85 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "conserve" `
    -Enabled $true
  if ($light.State.totalXp -ne 30 -or $light.State.condition -ne "healthy") {
    throw "Light use growth mode should fill XP at the light 5h usage target."
  }

  $tooLittleUseState = New-PetGrowthState -Now $start
  $tooLittleUseState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $tooLittleUse = Update-PetGrowthState `
    -State $tooLittleUseState `
    -PrimaryRemaining 90 `
    -SecondaryRemaining 95 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "conserve" `
    -Enabled $true
  if ($tooLittleUse.State.totalXp -ne 15 -or $tooLittleUse.State.condition -ne "stable") {
    throw "Partial 5h usage should partially fill XP while staying stable."
  }

  $balancedState = New-PetGrowthState -Now $start
  $balancedState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $balanced = Update-PetGrowthState `
    -State $balancedState `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($balanced.State.totalXp -ne 30 -or $balanced.State.condition -ne "healthy") {
    throw "Balanced use growth mode should fill XP at the balanced 5h usage target."
  }

  $activeState = New-PetGrowthState -Now $start
  $activeState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $active = Update-PetGrowthState `
    -State $activeState `
    -PrimaryRemaining 35 `
    -SecondaryRemaining 55 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "active" `
    -Enabled $true
  if ($active.State.totalXp -ne 30 -or $active.State.condition -ne "healthy") {
    throw "Focused use growth mode should fill XP at the focused 5h usage target."
  }

  $resetState = New-PetGrowthState -Now $start
  $resetState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $resetAt = $start.AddSeconds(30)
  $resetResult = Update-PetGrowthState `
    -State $resetState `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $resetAt `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($resetResult.State.totalXp -ne 40) {
    throw "Healthy reset crossing should award 5h usage XP plus one 10 XP reset bonus."
  }
  $resetAgain = Update-PetGrowthState `
    -State $resetResult.State `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $resetAt `
    -SecondaryResetAt $start.AddDays(3) `
    -Now $start.AddSeconds(90) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($resetAgain.State.totalXp -ne 40) {
    throw "Reset bonus should only be awarded once per reset timestamp."
  }

  $weeklyResetState = New-PetGrowthState -Now $start
  $weeklyResetState.totalXp = 130
  $weeklyResetState.level = 3
  $weeklyResetState.todayXp = 12
  $weeklyResetState.todayHealthySeconds = 720
  $weeklyResetState.lastUpdatedAt = $start.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  $weeklyResetAt = $start.AddSeconds(30)
  $weeklyReset = Update-PetGrowthState `
    -State $weeklyResetState `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $weeklyResetAt `
    -Now $start.AddSeconds(60) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($weeklyReset.State.totalXp -ne 0 -or $weeklyReset.State.level -ne 1 -or $weeklyReset.State.todayXp -ne 0) {
    throw "Weekly reset should restart pet level and XP."
  }
  $weeklyResetAgain = Update-PetGrowthState `
    -State $weeklyReset.State `
    -PrimaryRemaining 55 `
    -SecondaryRemaining 75 `
    -PrimaryResetAt $start.AddHours(5) `
    -SecondaryResetAt $weeklyResetAt `
    -Now $start.AddSeconds(120) `
    -HasUsageSnapshot $true `
    -PetVisible $true `
    -GrowthMode "balanced" `
    -Enabled $true
  if ($weeklyResetAgain.State.totalXp -ne 30 -or $weeklyResetAgain.State.level -ne 1) {
    throw "Weekly reset should only restart once per reset timestamp, then allow XP again."
  }

  if ((Get-PetGrowthLevel -TotalXp 49) -ne 1 -or (Get-PetGrowthLevel -TotalXp 50) -ne 2 -or (Get-PetGrowthLevel -TotalXp 450) -ne 5) {
    throw "Pet growth level thresholds are incorrect."
  }
}

function Assert-PetHudHideCleanup {
  $runtimePath = Join-Path $root "src\CodexyPetUsagesRing.ps1"
  $source = Get-Content -Raw -LiteralPath $runtimePath
  foreach ($required in @(
    "function Hide-PetHud",
    '$script:LastPetRect = $null',
    '$script:GrowthChipBounds = $null',
    '$script:BatteryPrimaryBounds = $null',
    '$script:BadgePrimaryBounds = $null',
    'Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)',
    'Hide-PetHud -UpdateGrowth $true',
    'Hide-PetHud -UpdateGrowth $false'
  )) {
    if (-not $source.Contains($required)) {
      throw "Pet HUD hide cleanup is missing required code: $required"
    }
  }
  if ($source -match 'LastWriteTimeUtc[^\r\n]*-eq[^\r\n]*\$script:LastStateWriteTimeUtc[\s\S]{0,160}?return\s+\$script:CachedPetRect') {
    throw "Read-PetRect must not reuse stale cached pet bounds when /pet visibility may have changed."
  }
}

function Assert-CompanionLifecycle {
  $runtime = Get-Content -Raw -LiteralPath (Join-Path $root "src\CodexyPetUsagesRing.ps1")
  foreach ($required in @(
    '[switch]$NoExitWithCodex',
    'public static bool IsCodexDesktopRunning()',
    'function Stop-WhenCodexDesktopClosed',
    '$script:LifecycleTimer = [System.Windows.Threading.DispatcherTimer]::new()',
    'Stop-WhenCodexDesktopClosed',
    'Codex Desktop is not running; stopping companion helper.'
  )) {
    if (-not $runtime.Contains($required)) {
      throw "Companion lifecycle cleanup is missing required code: $required"
    }
  }

  $startScript = Get-Content -Raw -LiteralPath (Join-Path $root "bin\powershell\Start.ps1")
  foreach ($required in @(
    '[switch]$ShowTrayIcon',
    '[switch]$NoExitWithCodex',
    'if ($NoExitWithCodex) { $args += "-NoExitWithCodex" }',
    'src\WatchPetOverlay.ps1',
    'Started Codexy pet usages ring watcher.'
  )) {
    if (-not $startScript.Contains($required)) {
      throw "Start.ps1 lifecycle/tray defaults are missing required code: $required"
    }
  }

  $watcherScript = Get-Content -Raw -LiteralPath (Join-Path $root "src\WatchPetOverlay.ps1")
  foreach ($required in @(
    'function Test-PetOverlayOpen',
    'function Start-Companion',
    'function Stop-Companion',
    'if (-not $ShowTrayIcon) { $args += "-NoTrayIcon" }',
    'Stop-Companion',
    'Start-Companion'
  )) {
    if (-not $watcherScript.Contains($required)) {
      throw "WatchPetOverlay.ps1 trigger lifecycle is missing required code: $required"
    }
  }
}

try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

  Add-Fixture -RelativePath "logs/smoke.log"
  Add-Fixture -RelativePath "qa/smoke.tmp"
  Add-Fixture -RelativePath ".gitignore"
  Add-Fixture -RelativePath "settings.json" -Content "{`"theme`":`"smoke`"}"
  Add-Fixture -RelativePath "gamification.json" -Content "{`"totalXp`":999}"
  Add-Fixture -RelativePath "docs/assets/current-pet-usage-capture.png"
  Add-Fixture -RelativePath "docs/assets/imagegen-hero-background.png"
  Add-Fixture -RelativePath "smoke.tmp"

  $version = Assert-VersionMetadata
  Assert-SettingsLauncherUsesActiveInstall
  Assert-SettingsDisplayModes
  Assert-PetGrowthCalculations
  Assert-PetHudHideCleanup
  Assert-CompanionLifecycle

  $parseErrorsText = @()
  Get-ChildItem -LiteralPath $root -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch '\\.git\\' } | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors) {
      $parseErrorsText += $parseErrors | ForEach-Object { "$($_.Extent.File):$($_.Extent.StartLineNumber):$($_.Message)" }
    }
  }
  if ($parseErrorsText.Count -gt 0) { throw "PowerShell parser check failed: $($parseErrorsText -join '; ')" }

  $trackedFiles = @(git -C $root ls-files)
  Assert-NoForbiddenPaths -Paths $trackedFiles -Scope "Git tracked files"

  & (Join-Path $root "tools\New-ReleaseZip.ps1") -OutputDirectory $releaseOut | Out-Host
  $zip = Get-ChildItem -LiteralPath $releaseOut -Filter "*.zip" | Select-Object -First 1
  if (-not $zip) { throw "Release zip was not created." }
  if ($zip.Name -ne "Codexy-pet-usages-ring-$version.zip") {
    throw "Release zip name must match VERSION $version. Found: $($zip.Name)"
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
  try {
    $zipEntries = @($archive.Entries | ForEach-Object { $_.FullName.TrimEnd("/") })
    foreach ($requiredFile in $script:CodexPetRequiredFreshFiles) {
      Assert-ZipFileMatches -Archive $archive -RelativePath $requiredFile
    }
  } finally {
    $archive.Dispose()
  }
  Assert-NoForbiddenPaths -Paths $zipEntries -Scope "Release zip"

  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $installRoot -NoStartup -NoStartMenu -NoStart | Out-Host
  $installedFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Force | ForEach-Object {
    $_.FullName.Substring($installRoot.TrimEnd("\").Length + 1) -replace '\\', '/'
  })
  Assert-NoForbiddenPaths -Paths $installedFiles -Scope "Temp install"
  foreach ($requiredInstallFile in $script:CodexPetRequiredFreshFiles) {
    Assert-InstalledFileMatches -InstallRoot $installRoot -RelativePath $requiredInstallFile
  }
  & (Join-Path $root "bin\powershell\Uninstall.ps1") -InstallDir $installRoot -RemoveFiles | Out-Host

  Write-Output "Smoke checks passed."
} finally {
  foreach ($fixture in $fixtures) {
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
  }
  if (-not $KeepArtifacts) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Output "Kept smoke artifacts: $tempRoot"
  }
}
