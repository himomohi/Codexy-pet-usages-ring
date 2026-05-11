param(
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
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
  $leaf = Split-Path -Leaf $normalized
  if ($normalized -in @(
    ".gitignore",
    "gamification.json",
    "settings.json",
    "docs/assets/current-pet-usage-capture.png",
    "docs/assets/imagegen-hero-background.png"
  )) { return $true }
  if ($normalized -like "dist/*" -or $normalized -eq "dist") { return $true }
  if ($normalized -like "logs/*" -or $normalized -eq "logs") { return $true }
  if ($normalized -like "qa/*" -or $normalized -eq "qa") { return $true }
  if ($normalized -like "*.log" -or $normalized -like "*.tmp" -or $normalized -like "*.bak" -or $normalized -like "*.zip") { return $true }
  if ($leaf -eq ".DS_Store" -or $leaf -eq "Thumbs.db") { return $true }
  return $false
}

function Assert-NoForbiddenPaths {
  param([string[]]$Paths, [string]$Scope)
  $bad = @($Paths | Where-Object { Test-ForbiddenPath -Path $_ })
  if ($bad.Count -gt 0) {
    throw "$Scope contains forbidden paths: $($bad -join ', ')"
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
  if ($defaults.gamification.showGrowthChip -ne $true -or $defaults.gamification.showHoverReadout -ne $true) {
    throw "Default gamification chip/readout settings should remain true."
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
  $invalidGrowth = Get-NormalizedSettings ([PSCustomObject]@{ gamification = [PSCustomObject]@{ enabled = "maybe"; growthMode = "chaos"; showGrowthChip = "no"; showHoverReadout = "yes" } })
  if ($invalidGrowth.gamification.enabled -ne $false) {
    throw "Invalid gamification.enabled should fall back to false."
  }
  if ($invalidGrowth.gamification.growthMode -ne "balanced") {
    throw "Invalid gamification.growthMode should fall back to balanced."
  }
  if ($invalidGrowth.gamification.showGrowthChip -ne $false -or $invalidGrowth.gamification.showHoverReadout -ne $true) {
    throw "Boolean gamification values should normalize from yes/no strings."
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
  if ($result.State.totalXp -ne 1 -or $result.State.todayXp -ne 1) {
    throw "Usage target should award 1 XP per accumulated minute."
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
  if ($low.State.totalXp -ne 1 -or $low.State.condition -ne "sleepy") {
    throw "Low remaining usage should stop XP and mark the pet sleepy."
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
  if ($light.State.totalXp -ne 1 -or $light.State.condition -ne "healthy") {
    throw "Light use growth mode should award XP at the light usage threshold."
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
  if ($tooLittleUse.State.totalXp -ne 0 -or $tooLittleUse.State.condition -ne "stable") {
    throw "Too little usage should stay stable without XP."
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
  if ($balanced.State.totalXp -ne 1 -or $balanced.State.condition -ne "healthy") {
    throw "Balanced use growth mode should award XP at the balanced usage threshold."
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
  if ($active.State.totalXp -ne 1 -or $active.State.condition -ne "healthy") {
    throw "Focused use growth mode should award XP at the focused usage threshold."
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
  if ($resetResult.State.totalXp -ne 11) {
    throw "Healthy reset crossing should award 1 minute XP plus one 10 XP reset bonus."
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
  if ($resetAgain.State.totalXp -ne 11) {
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
  if ($weeklyResetAgain.State.totalXp -ne 1 -or $weeklyResetAgain.State.level -ne 1) {
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
  } finally {
    $archive.Dispose()
  }
  Assert-NoForbiddenPaths -Paths $zipEntries -Scope "Release zip"

  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $installRoot -NoStartup -NoStartMenu -NoStart | Out-Host
  $installedFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Force | ForEach-Object {
    $_.FullName.Substring($installRoot.TrimEnd("\").Length + 1) -replace '\\', '/'
  })
  Assert-NoForbiddenPaths -Paths $installedFiles -Scope "Temp install"
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
