param(
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-pet-limit-rings-smoke-" + [Guid]::NewGuid().ToString("N"))
$releaseOut = Join-Path $tempRoot "release"
$installRoot = Join-Path $tempRoot "install"
$fixtures = @()
$startingLocation = (Get-Location).Path

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
    "settings.json",
    ".codex-pet-language-cache.json",
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
    if ($readme -notmatch [regex]::Escape("codex-pet-limit-rings-Win-$version.zip") -or $readme -notmatch 'docs/assets/windows-tray-settings-guide\.png') {
      throw "$readmeName must include the current release download and tray settings guide."
    }
  }

  if (-not (Test-Path -LiteralPath (Join-Path $root "docs\assets\windows-tray-settings-guide.png"))) {
    throw "Windows tray settings guide image is missing."
  }

  return $version
}

try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

  Add-Fixture -RelativePath "logs/smoke.log"
  Add-Fixture -RelativePath "qa/smoke.tmp"
  Add-Fixture -RelativePath ".gitignore"
  Add-Fixture -RelativePath "settings.json" -Content "{`"theme`":`"smoke`"}"
  Add-Fixture -RelativePath ".codex-pet-language-cache.json" -Content "{`"country`":`"KR`"}"
  Add-Fixture -RelativePath "docs/assets/current-pet-usage-capture.png"
  Add-Fixture -RelativePath "docs/assets/imagegen-hero-background.png"
  Add-Fixture -RelativePath "smoke.tmp"

  $version = Assert-VersionMetadata

  $defaultSettings = Get-Content -Raw -LiteralPath (Join-Path $root "settings.defaults.json") | ConvertFrom-Json
  if ($defaultSettings.behavior.visibilityMode -ne "always") {
    throw "Default ring visibility must be always."
  }
  if ($defaultSettings.appearance.mode -ne "rings") {
    throw "Default usage visualization must be rings."
  }
  if ($defaultSettings.layout.offsetX -ne 0 -or $defaultSettings.layout.offsetY -ne 0) {
    throw "Default visualization offset must be centered."
  }
  $runtimeText = Get-Content -Raw -LiteralPath (Join-Path $root "src\CodexPetLimitRings.ps1")
  foreach ($trayIconMarker in @('tray-cat-icon.ico', '[System.Drawing.Icon]::new', 'NotifyIcon.Icon')) {
    if ($runtimeText -notmatch [regex]::Escape($trayIconMarker)) {
      throw "Runtime is missing cat tray icon integration: $trayIconMarker"
    }
  }
  if ($runtimeText -notmatch '\$script:Style\.VisibilityMode\s+-eq\s+"always"') {
    throw "Runtime must keep rings visible in always mode."
  }
  $settingsPage = Get-Content -Raw -LiteralPath (Join-Path $root "settings\index.html")
  $settingsScript = Get-Content -Raw -LiteralPath (Join-Path $root "bin\powershell\Settings.ps1")
  $languageDetectionText = Get-Content -Raw -LiteralPath (Join-Path $root "src\LanguageDetection.ps1")
  foreach ($marker in @("https://api.country.is/", "Get-AutomaticLanguageResult", ".codex-pet-language-cache.json")) {
    if ($languageDetectionText -notmatch [regex]::Escape($marker)) {
      throw "IP language detection is missing marker: $marker"
    }
  }
  if ($settingsScript -notmatch 'automaticLanguage' -or $settingsScript -notmatch 'languageCountry' -or $settingsScript -notmatch 'languageSource') {
    throw "Settings API must expose IP-based automatic language diagnostics."
  }
  if ($settingsPage -notmatch 'Auto \(IP location\)' -or $settingsPage -notmatch '자동 \(IP 위치\)') {
    throw "Settings page must explain that automatic language uses IP location."
  }
  if ($settingsPage -notmatch 'data-path="behavior\.visibilityMode"') {
    throw "Settings page is missing the ring visibility selector."
  }
  if ($settingsPage -notmatch 'data-path="appearance\.mode"') {
    throw "Settings page is missing the usage visualization selector."
  }
  foreach ($offsetPath in @("layout.offsetX", "layout.offsetY")) {
    if ($settingsPage -notmatch [regex]::Escape("data-path=`"$offsetPath`"")) {
      throw "Settings page is missing position control: $offsetPath"
    }
  }
  if ($settingsPage -notmatch 'id="centerOnPet"' -or $settingsPage -notmatch "offsetX'\)\.value = '0'" -or $settingsPage -notmatch "offsetY'\)\.value = '0'") {
    throw "Settings page is missing the pet-centered alignment action."
  }
  if ($settingsPage -notmatch 'id="potionScale"' -or $settingsPage -notmatch 'data-path="appearance\.potionScale"') {
    throw "Settings page is missing the potion scale control."
  }
  foreach ($mode in @("rings", "bars", "wings", "corners", "potions", "heart_potions")) {
    if ($settingsPage -notmatch [regex]::Escape("value=`"$mode`"")) {
      throw "Settings page is missing visualization mode: $mode"
    }
  }
  foreach ($potionMarker in @("previewPixelPotions", "potion-pixel-frame.png", "potion-pixel-mask.png", "pixel-potion-value", "pixel-potion-label")) {
    if ($settingsPage -notmatch [regex]::Escape($potionMarker)) {
      throw "Settings page is missing pixel potion marker: $potionMarker"
    }
  }
  foreach ($heartPotionMarker in @("heart_potions", "heart-potion-pixel-frame.png", "heart-potion-pixel-mask.png", "appearanceHeartPotions")) {
    if ($settingsPage -notmatch [regex]::Escape($heartPotionMarker)) {
      throw "Settings page is missing heart-potion option support: $heartPotionMarker"
    }
  }
  foreach ($assetName in @("potion-pixel-frame.png", "potion-pixel-mask.png", "heart-potion-pixel-frame.png", "heart-potion-pixel-mask.png")) {
    $assetPath = Join-Path $root "assets\runtime\$assetName"
    if (-not (Test-Path -LiteralPath $assetPath)) { throw "Pixel potion asset is missing: $assetName" }
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($assetPath)
    try {
      $expectedSize = if ($assetName -like "heart-*") { @(76, 80) } else { @(68, 73) }
      if ($image.Width -ne $expectedSize[0] -or $image.Height -ne $expectedSize[1]) {
        throw "Pixel potion asset has an unexpected size: $assetName"
      }
    } finally {
      $image.Dispose()
    }
  }
  foreach ($trayAsset in @("tray-cat-icon.png", "tray-cat-icon.ico")) {
    if (-not (Test-Path -LiteralPath (Join-Path $root "assets\runtime\$trayAsset"))) {
      throw "Cat tray icon asset is missing: $trayAsset"
    }
  }
  if ($settingsPage -match '>LIVE<' -or $settingsPage -notmatch 'data-i18n="previewSample"' -or $settingsPage -match '90% left|64% left') {
    throw "Settings preview must be clearly labeled as a consistent sample, not live usage."
  }
  if ($settingsPage -notmatch 'aria-valuetext' -or $settingsPage -notmatch "setAttribute\('for', input\.id\)") {
    throw "Settings range values must be associated with their controls for assistive technology."
  }
  if ($settingsPage -notmatch '\.actions\s*\{\s*position:\s*static') {
    throw "Settings actions must not overlay configuration cards."
  }
  foreach ($ambientMarker in @('class="ambient-scene"', 'assets/codex-pet-ambient.webp', '@keyframes ambient-drift', 'prefers-reduced-motion')) {
    if ($settingsPage -notmatch [regex]::Escape($ambientMarker)) {
      throw "Settings page is missing the lightweight animated pet background: $ambientMarker"
    }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root "settings\assets\codex-pet-ambient.webp"))) {
    throw "Settings imagegen background asset is missing."
  }
  if ($settingsPage -notmatch 'ambient-scene"\s+aria-hidden="true"') {
    throw "Decorative settings artwork must stay hidden from assistive technology."
  }
  if ($runtimeText -notmatch 'Noto Sans KR, Segoe UI') {
    throw "Runtime hover readouts must use Noto Sans KR with a Segoe UI fallback."
  }
  foreach ($staleMarker in @('UsageStaleSeconds', 'Get-UsageFreshnessText', 'Update-StaleIndicator', 'Usage data is stale')) {
    if ($runtimeText -notmatch [regex]::Escape($staleMarker)) {
      throw "Runtime is missing stale usage feedback: $staleMarker"
    }
  }
  foreach ($logFreshnessMarker in @('SELECT feedback_log_body, ts, ts_nanos', 'observedAt', 'Usage log fallback is stale')) {
    if ($runtimeText -notmatch [regex]::Escape($logFreshnessMarker)) {
      throw "Runtime is missing SQLite observation-time freshness handling: $logFreshnessMarker"
    }
  }
  foreach ($previewEndpoint in @("/api/pet-preview", "/api/pet-spritesheet")) {
    if ($settingsPage -notmatch [regex]::Escape($previewEndpoint)) {
      throw "Settings page is missing calibrated pet preview endpoint: $previewEndpoint"
    }
  }
  foreach ($syncMarker in @("refreshPetPreview", "spriteVersion", "cache: 'no-store'")) {
    if ($settingsPage -notmatch [regex]::Escape($syncMarker)) {
      throw "Settings page is missing current-pet preview synchronization: $syncMarker"
    }
  }
  foreach ($livePreviewMarker in @("schedulePreviewUpdate", "requestAnimationFrame", "input.addEventListener('input', collect)", "input.addEventListener('change', collect)")) {
    if ($settingsPage -notmatch [regex]::Escape($livePreviewMarker)) {
      throw "Settings page is missing real-time preview updates: $livePreviewMarker"
    }
  }
  if ($settingsPage -notmatch 'potionGroup\.style\.transform\s*=\s*`translate\(') {
    throw "Potion preview must follow live horizontal and vertical position controls."
  }
  $settingsServerText = Get-Content -Raw -LiteralPath (Join-Path $root "bin\powershell\Settings.ps1")
  if ($settingsServerText -notmatch '/assets/codex-pet-ambient\.webp' -or $settingsServerText -notmatch 'ContentType "image/webp"') {
    throw "Settings server must serve the imagegen background as WebP."
  }
  if ($settingsServerText -notmatch 'function Get-PetPreviewInfo' -or $settingsServerText -notmatch 'electron-avatar-overlay-bounds') {
    throw "Settings server is missing live pet preview calibration."
  }
  foreach ($syncMarker in @('selected-avatar-id', 'Sort-Object LastWriteTimeUtc -Descending', 'spriteVersion')) {
    if ($settingsServerText -notmatch [regex]::Escape($syncMarker)) {
      throw "Settings server is missing current-pet selection handling: $syncMarker"
    }
  }

  $installLauncher = Get-Content -Raw -LiteralPath (Join-Path $root "Install.bat")
  if ($installLauncher -notmatch '(?i)install\.cmd"\s+-Startup') {
    throw "Install.bat must enable reboot-safe Windows auto-start."
  }
  $autoStartLauncher = Get-Content -Raw -LiteralPath (Join-Path $root "Install-AutoStart.bat")
  if ($autoStartLauncher -notmatch '(?i)install\.cmd"\s+-Startup') {
    throw "Install-AutoStart.bat must explicitly opt in to Windows auto-start."
  }
  $applyInstalledLauncher = Get-Content -Raw -LiteralPath (Join-Path $root "Apply-Installed.bat")
  if ($applyInstalledLauncher -notmatch '(?i)tools\\Sync-Installed\.ps1') {
    throw "Apply-Installed.bat must run the guarded installed-copy sync."
  }
  $syncInstalledText = Get-Content -Raw -LiteralPath (Join-Path $root "tools\Sync-Installed.ps1")
  foreach ($syncMarker in @("Get-CodexPetInstallMarker", "settingsHashBefore", "Installed file hash mismatch", "NoStartCodex")) {
    if ($syncInstalledText -notmatch [regex]::Escape($syncMarker)) {
      throw "Installed-copy sync is missing safety behavior: $syncMarker"
    }
  }
  $installerText = Get-Content -Raw -LiteralPath (Join-Path $root "bin\powershell\Install.ps1")
  if ($installerText -notmatch '\$Startup\s+-and\s+-not\s+\$NoStartup') {
    throw "PowerShell installation must honor explicit startup registration."
  }
  if ($installerText -match '(?im)^\s*\$startup\s*=') {
    throw "Installer startup-folder variables must not collide with the -Startup switch."
  }
  if ($installerText -notmatch 'Get-StartScriptShortcutArguments\s+-StartScript\s+\$startScript\s+-ForStartup' -or
      $installerText -notmatch '\$ForStartup\s+-or\s+\$NoStartCodex') {
    throw "Windows startup must arm the companion without launching Codex Desktop."
  }
  $runtimeStateText = Get-Content -Raw -LiteralPath (Join-Path $root "bin\powershell\RuntimeState.ps1")
  if ($runtimeStateText -notmatch '\$markedRoot\s+-ne\s+\$expectedRoot') {
    throw "Install marker validation must bind installDir to the actual target root."
  }
  $releaseScriptText = Get-Content -Raw -LiteralPath (Join-Path $root "tools\New-ReleaseZip.ps1")
  if ($releaseScriptText -notmatch 'NewGuid') {
    throw "Release staging must use a unique directory for parallel-safe builds."
  }
  $uninstallLauncher = Get-Content -Raw -LiteralPath (Join-Path $root "Uninstall.bat")
  if ($uninstallLauncher -notmatch '(?i)uninstall\.cmd"\s+-RemoveFiles') {
    throw "Uninstall.bat must remove the installed copy by default."
  }
  $manageBytes = [System.IO.File]::ReadAllBytes((Join-Path $root "Manage.bat"))
  for ($i = 0; $i -lt $manageBytes.Length; $i++) {
    if ($manageBytes[$i] -eq 10 -and ($i -eq 0 -or $manageBytes[$i - 1] -ne 13)) {
      throw "Manage.bat must use CRLF line endings."
    }
  }
  try {
    [void]([System.Text.UTF8Encoding]::new($false, $true).GetString($manageBytes))
    throw "Manage.bat must be encoded as CP949, not UTF-8."
  } catch [System.Text.DecoderFallbackException] {
    # CP949 한글 바이트는 엄격한 UTF-8 디코딩에 실패해야 한다.
  }
  $manageText = [System.Text.Encoding]::GetEncoding(949).GetString($manageBytes)
  if ($manageText -notmatch [regex]::Escape("Codex Pet 사용량 링 관리")) {
    throw "Manage.bat did not decode to the expected Korean CP949 text."
  }

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

  & (Join-Path $root "tools\Test-RingMath.ps1") | Out-Host

  # .gitignore는 저장소에는 필요하지만 릴리스/설치 산출물에는 포함하지 않는다.
  $trackedFiles = @(git -C $root ls-files | Where-Object { $_ -ne ".gitignore" })
  Assert-NoForbiddenPaths -Paths $trackedFiles -Scope "Git tracked files"

  & (Join-Path $root "tools\New-ReleaseZip.ps1") -OutputDirectory $releaseOut | Out-Host
  $zip = Get-ChildItem -LiteralPath $releaseOut -Filter "*.zip" | Select-Object -First 1
  if (-not $zip) { throw "Release zip was not created." }
  if ($zip.Name -ne "codex-pet-limit-rings-Win-$version.zip") {
    throw "Release zip name must match VERSION $version. Found: $($zip.Name)"
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
  try {
    $zipEntries = @($archive.Entries | ForEach-Object { ($_.FullName.TrimEnd("/")) -replace '\\', '/' })
  } finally {
    $archive.Dispose()
  }
  Assert-NoForbiddenPaths -Paths $zipEntries -Scope "Release zip"
  foreach ($requiredEntry in @("Manage.bat", "Install.bat", "Install-AutoStart.bat", "Apply-Installed.bat", "tools/Sync-Installed.ps1", "Diagnose.bat", "Uninstall.bat", "assets/runtime/potion-pixel-frame.png", "assets/runtime/potion-pixel-mask.png", "assets/runtime/heart-potion-pixel-frame.png", "assets/runtime/heart-potion-pixel-mask.png", "assets/runtime/tray-cat-icon.ico")) {
    if ($zipEntries -notcontains $requiredEntry) {
      throw "Release zip is missing $requiredEntry."
    }
  }

  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $installRoot -NoStartup -NoStartMenu -NoStart | Out-Host
  $installedFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Force | ForEach-Object {
    $_.FullName.Substring($installRoot.TrimEnd("\").Length + 1) -replace '\\', '/'
  })
  Assert-NoForbiddenPaths -Paths $installedFiles -Scope "Temp install"
  foreach ($requiredFile in @("Manage.bat", "Install-AutoStart.bat", "Apply-Installed.bat", "tools\Sync-Installed.ps1", "Diagnose.bat", "assets\runtime\potion-pixel-frame.png", "assets\runtime\potion-pixel-mask.png", "assets\runtime\heart-potion-pixel-frame.png", "assets\runtime\heart-potion-pixel-mask.png", "assets\runtime\tray-cat-icon.ico", "src\LanguageDetection.ps1", ".codex-pet-limit-rings-win.install.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot $requiredFile))) {
      throw "Temp install is missing $requiredFile."
    }
  }
  . (Join-Path $root "bin\powershell\RuntimeState.ps1")
  $runtimeRoots = @(Get-CodexPetRuntimeRoots -ScriptProjectRoot $installRoot)
  foreach ($expectedRoot in @($installRoot, $root)) {
    $expectedFullPath = [System.IO.Path]::GetFullPath($expectedRoot).TrimEnd("\")
    if ($runtimeRoots -notcontains $expectedFullPath) {
      throw "Runtime root discovery is missing $expectedFullPath."
    }
  }

  $settingsPath = Join-Path $installRoot "settings.json"
  $settingsSentinel = '{"smokeSettingsPreserved":true}'
  [System.IO.File]::WriteAllText($settingsPath, $settingsSentinel, [System.Text.Encoding]::UTF8)
  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $installRoot -NoStartup -NoStartMenu -NoStart | Out-Host
  if ([System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8) -ne $settingsSentinel) {
    throw "Updating an install must preserve settings.json."
  }

  $copiedMarkerRoot = Join-Path $tempRoot "copied-marker-target"
  New-Item -ItemType Directory -Force -Path (Join-Path $copiedMarkerRoot "bin\powershell") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $copiedMarkerRoot "src") | Out-Null
  Set-Content -LiteralPath (Join-Path $copiedMarkerRoot "VERSION") -Value "do-not-delete" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $copiedMarkerRoot "bin\powershell\Uninstall.ps1") -Value "do-not-delete" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $copiedMarkerRoot "src\CodexPetLimitRings.ps1") -Value "do-not-delete" -Encoding UTF8
  Copy-Item -LiteralPath (Join-Path $installRoot ".codex-pet-limit-rings-win.install.json") -Destination $copiedMarkerRoot -Force
  $copiedMarkerRejected = $false
  try {
    & (Join-Path $root "bin\powershell\Uninstall.ps1") -InstallDir $copiedMarkerRoot -RemoveFiles | Out-Null
  } catch {
    $copiedMarkerRejected = $true
  }
  if (-not $copiedMarkerRejected -or -not (Test-Path -LiteralPath (Join-Path $copiedMarkerRoot "VERSION"))) {
    throw "Uninstall must reject a copied install marker whose installDir does not match the target."
  }

  $unsafeRoot = Join-Path $tempRoot "unsafe-target"
  New-Item -ItemType Directory -Force -Path $unsafeRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $unsafeRoot "keep.txt") -Value "do not delete" -Encoding UTF8
  $unsafeRejected = $false
  try {
    & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $unsafeRoot -NoStartup -NoStartMenu -NoStart | Out-Null
  } catch {
    $unsafeRejected = $true
  }
  if (-not $unsafeRejected -or -not (Test-Path -LiteralPath (Join-Path $unsafeRoot "keep.txt"))) {
    throw "Installer must reject and preserve a non-empty unmarked target."
  }

  $sourceMarker = Join-Path $root ".codex-pet-limit-rings-win.install.json"
  if (Test-Path -LiteralPath $sourceMarker) {
    throw "Source checkout unexpectedly contains an install marker."
  }
  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $root -NoStartup -NoStartMenu -NoStart | Out-Host
  if (Test-Path -LiteralPath $sourceMarker) {
    throw "Installing with sourceRoot equal to targetRoot must not mark the source as removable."
  }

  & (Join-Path $root "bin\powershell\Uninstall.ps1") -InstallDir $installRoot -RemoveFiles | Out-Host
  if ((Get-Location).Path -ne $startingLocation) {
    throw "Uninstall.ps1 changed the caller's working directory."
  }
  if (Test-Path -LiteralPath $installRoot) {
    throw "Temp install directory still exists after removal."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root "VERSION"))) {
    throw "Removing an install must preserve the source folder."
  }

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
