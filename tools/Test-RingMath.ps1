param()

$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$runtimePath = Join-Path $root "src\CodexPetLimitRings.ps1"
$settingsScriptPath = Join-Path $root "bin\powershell\Settings.ps1"
$languageDetectionPath = Join-Path $root "src\LanguageDetection.ps1"

. $languageDetectionPath

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors)
if ($errors) { throw "Runtime parser errors: $($errors -join '; ')" }

function Get-RuntimeFunctionText {
  param([string]$Name)
  $definition = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
  }, $true)
  if ($null -eq $definition) { throw "Runtime function not found: $Name" }
  return $definition.Extent.Text
}

$settingsTokens = $null
$settingsErrors = $null
$settingsAst = [System.Management.Automation.Language.Parser]::ParseFile($settingsScriptPath, [ref]$settingsTokens, [ref]$settingsErrors)
if ($settingsErrors) { throw "Settings parser errors: $($settingsErrors -join '; ')" }
function Get-SettingsFunctionText {
  param([string]$Name)
  $definition = $settingsAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
  }, $true)
  if ($null -eq $definition) { throw "Settings function not found: $Name" }
  return $definition.Extent.Text
}

Invoke-Expression (Get-RuntimeFunctionText "New-ArcGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PolylineGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-ProgressPolylineGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PotionOrbGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PotionDiamondGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PotionFrameGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PotionFacetGeometry")
Invoke-Expression (Get-RuntimeFunctionText "New-PotionGemBrush")
Invoke-Expression (Get-RuntimeFunctionText "Get-EffectiveLanguage")
Invoke-Expression (Get-RuntimeFunctionText "Test-KoreanLanguage")
Invoke-Expression (Get-RuntimeFunctionText "Expand-UnicodeText")
Invoke-Expression (Get-RuntimeFunctionText "Format-Percent")
Invoke-Expression (Get-RuntimeFunctionText "Format-Duration")
Invoke-Expression (Get-RuntimeFunctionText "Convert-ResetValue")
Invoke-Expression (Get-RuntimeFunctionText "Format-PotionResetMoment")
Invoke-Expression (Get-RuntimeFunctionText "Format-PotionRemainingTime")
Invoke-Expression (Get-RuntimeFunctionText "Get-PotionReadoutText")
Invoke-Expression (Get-RuntimeFunctionText "Get-UsageFreshnessText")
Invoke-Expression (Get-RuntimeFunctionText "Update-UsageState")
Invoke-Expression (Get-RuntimeFunctionText "Test-UsageTransitionStable")
foreach ($functionName in @(
  "Get-PropertyValue",
  "Normalize-Hex",
  "Normalize-Number",
  "Normalize-Language",
  "Resolve-SettingsAutomaticLanguage",
  "Normalize-VisibilityMode",
  "Normalize-AppearanceMode",
  "Get-NormalizedSettings"
)) {
  Invoke-Expression (Get-SettingsFunctionText $functionName)
}

$empty = New-ArcGeometry -Center 100 -Radius 80 -Percent 0 -StrokeThickness 7
if ($empty -ne [System.Windows.Media.Geometry]::Empty) { throw "0% must render as empty geometry." }

$full = New-ArcGeometry -Center 100 -Radius 80 -Percent 100 -StrokeThickness 7
if ($full -isnot [System.Windows.Media.EllipseGeometry]) { throw "100% must render as a complete ellipse." }

$percent = 83.0
$radius = 80.0
$stroke = 7.0
$arc = New-ArcGeometry -Center 100 -Radius $radius -Percent $percent -StrokeThickness $stroke
$path = [System.Windows.Media.PathGeometry]::CreateFromGeometry($arc)
$figure = $path.Figures[0]
$segment = $figure.Segments[0]
$center = [System.Windows.Point]::new(100, 100)
$startAngle = [Math]::Atan2($figure.StartPoint.Y - $center.Y, $figure.StartPoint.X - $center.X) * 180.0 / [Math]::PI
$endAngle = [Math]::Atan2($segment.Point.Y - $center.Y, $segment.Point.X - $center.X) * 180.0 / [Math]::PI
$geometrySweep = ($endAngle - $startAngle + 360.0) % 360.0
$capSweep = ($stroke / $radius) * 180.0 / [Math]::PI
$visiblePercent = ($geometrySweep + $capSweep) / 360.0 * 100.0
if ([Math]::Abs($visiblePercent - $percent) -gt 0.05) {
  throw "83% visible sweep mismatch: $visiblePercent"
}

$linePoints = @(
  [System.Windows.Point]::new(0, 0),
  [System.Windows.Point]::new(100, 0)
)
$lineEmpty = New-ProgressPolylineGeometry -Points $linePoints -Percent 0
if ($lineEmpty -ne [System.Windows.Media.Geometry]::Empty) { throw "Polyline 0% must be empty." }
$lineHalf = New-ProgressPolylineGeometry -Points $linePoints -Percent 50
if ([Math]::Abs($lineHalf.Bounds.Width - 50.0) -gt 0.01) { throw "Polyline 50% width mismatch." }
$lineFull = New-ProgressPolylineGeometry -Points $linePoints -Percent 100
if ([Math]::Abs($lineFull.Bounds.Width - 100.0) -gt 0.01) { throw "Polyline 100% width mismatch." }

$cornerPoints = @(
  [System.Windows.Point]::new(0, 0),
  [System.Windows.Point]::new(100, 0),
  [System.Windows.Point]::new(100, 100)
)
$cornerProgress = New-ProgressPolylineGeometry -Points $cornerPoints -Percent 75
if ([Math]::Abs($cornerProgress.Bounds.Width - 100.0) -gt 0.01 -or [Math]::Abs($cornerProgress.Bounds.Height - 50.0) -gt 0.01) {
  throw "Corner 75% topology mismatch."
}
$hoverPen = [System.Windows.Media.Pen]::new([System.Windows.Media.Brushes]::Black, 36.0)
$lineGeometry = New-PolylineGeometry -Points $linePoints
if (-not $lineGeometry.StrokeContains($hoverPen, [System.Windows.Point]::new(50, 12))) { throw "Bar hover hit test failed." }
if ($lineGeometry.StrokeContains($hoverPen, [System.Windows.Point]::new(50, 30))) { throw "Bar hover miss test failed." }

$potion = New-PotionOrbGeometry -CenterX 50 -CenterY 50 -Radius 24
if (-not $potion.FillContains([System.Windows.Point]::new(50, 50))) { throw "Potion center hit test failed." }
if ($potion.FillContains([System.Windows.Point]::new(5, 5))) { throw "Potion outside hit test failed." }
$potionFrame = New-PotionFrameGeometry -CenterX 50 -CenterY 50 -Radius 24
if (-not $potionFrame.FillContains([System.Windows.Point]::new(50, 19))) { throw "Potion top ornament hit test failed." }
$potionFacets = New-PotionFacetGeometry -CenterX 50 -CenterY 50 -Radius 24
if ($potionFacets.Bounds.Width -le 30 -or $potionFacets.Bounds.Height -le 30) { throw "Potion facet geometry is unexpectedly small." }
$baseGemBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(210, 220, 30, 30))
$gemBrush = New-PotionGemBrush $baseGemBrush
if ($gemBrush.GradientStops.Count -ne 3 -or -not $gemBrush.IsFrozen) { throw "Potion gem gradient must contain three frozen stops." }

$geometryText = Get-RuntimeFunctionText "Update-RingGeometry"
foreach ($mode in @('"bars"', '"wings"', '"corners"')) {
  if ($geometryText -notmatch [regex]::Escape($mode)) { throw "Runtime geometry is missing mode $mode." }
}
$hoverText = Get-RuntimeFunctionText "Update-HoverReadout"
if ($hoverText -notmatch 'StrokeContains' -or $hoverText -notmatch 'FillContains') {
  throw "Alternative visualization hover hit testing is missing."
}
if ($hoverText -notmatch 'OuterPotionBackdrop\.Data' -or $hoverText -notmatch 'InnerPotionBackdrop\.Data') {
  throw "Potion hover hit testing must target the full orb backdrop."
}
$showReadoutText = Get-RuntimeFunctionText "Show-RingReadout"
if ($showReadoutText -notmatch 'Set-PotionReadoutWindow -Ring "Outer"' -or $showReadoutText -notmatch 'Set-PotionReadoutWindow -Ring "Inner"') {
  throw "Potion readouts must use independent left and right placement."
}
$potionReadoutText = Get-RuntimeFunctionText "Get-PotionReadoutText"
if ($potionReadoutText -notmatch 'PrimaryRemaining' -or $potionReadoutText -notmatch 'SecondaryRemaining') {
  throw "Potion readouts must keep 5h and weekly values separated."
}
$krAutomatic = Get-AutomaticLanguageResult -CountryCodeOverride "KR"
$usAutomatic = Get-AutomaticLanguageResult -CountryCodeOverride "US"
if ($krAutomatic.Language -ne "ko" -or $usAutomatic.Language -ne "en") {
  throw "IP country language mapping must use Korean only for KR and English elsewhere."
}
$languageCacheTestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-pet-language-test-{0}.json" -f [Guid]::NewGuid().ToString("N"))
try {
  Write-IpCountryCache -CachePath $languageCacheTestPath -CountryCode "KR"
  $cachedCountry = Get-IpCountryResult -CachePath $languageCacheTestPath -CacheHours 24
  if ($cachedCountry.CountryCode -ne "KR" -or $cachedCountry.Source -ne "cache") {
    throw "IP country cache round-trip failed."
  }
} finally {
  Remove-Item -LiteralPath $languageCacheTestPath -Force -ErrorAction SilentlyContinue
}
function Get-AutomaticLanguageResult { throw "Manual language unexpectedly triggered IP detection." }
$manualLanguage = Resolve-SettingsAutomaticLanguage -Settings ([PSCustomObject]@{ language = "en" })
if ($manualLanguage.Source -ne "manual" -or -not [string]::IsNullOrWhiteSpace($manualLanguage.CountryCode)) {
  throw "Explicit language settings must bypass IP detection."
}
$script:Style = [ordered]@{ Language = "auto" }
$script:AutomaticLanguageResult = [PSCustomObject]@{ Language = "ko"; CountryCode = "KR"; Source = "cache" }
if ((Get-EffectiveLanguage) -ne "ko") { throw "Automatic runtime language must use the IP-derived result." }
$script:Style.Language = "en"
if ((Get-EffectiveLanguage) -ne "en") { throw "Explicit runtime language must override IP detection." }
$script:Style = [ordered]@{ Language = "ko" }
$remainingBase = [datetime]"2026-07-11T14:35:00"
if ((Format-PotionRemainingTime -ResetAt ([datetime]"2026-07-11T16:45:00") -Now $remainingBase) -ne "남은 시간 2시간 10분") {
  throw "Korean potion remaining-time formatting failed."
}
if ((Format-PotionRemainingTime -ResetAt $null -Now $remainingBase) -ne "남은 시간 --") {
  throw "Unknown potion remaining-time formatting failed."
}
$script:UsageState = [ordered]@{
  PrimaryRemaining = 83
  PrimaryResetAt = [datetime]"2026-07-11T16:45:00"
  SecondaryRemaining = 58
  SecondaryResetAt = [datetime]"2026-07-17T09:30:00"
}
$outerPotionText = Get-PotionReadoutText -Ring "Outer"
$innerPotionText = Get-PotionReadoutText -Ring "Inner"
if ($outerPotionText -notmatch '^5h  83% 남음\r?\n초기화 16:45\r?\n남은 시간 .+$') { throw "Unexpected left potion readout: $outerPotionText" }
if ($innerPotionText -notmatch '^주간  58% 남음\r?\n초기화 7월 17일 09:30\r?\n남은 시간 .+$') { throw "Unexpected right potion readout: $innerPotionText" }
$script:UsageIsStale = $true
$script:LastUsageSuccessAt = [datetime]"2026-07-10T14:35:20"
if ((Get-UsageFreshnessText) -ne "오프라인 · 마지막 갱신 14:35:20") { throw "Stale usage timestamp text mismatch." }
$observedResetBase = [datetime]"2026-06-30T14:35:37"
if ((Convert-ResetValue -ResetAt $null -ResetAfterSeconds 3600 -ObservedAt $observedResetBase) -ne $observedResetBase.AddHours(1)) {
  throw "Log reset-after value must be anchored to the log observation time."
}

foreach ($mode in @("rings", "bars", "wings", "corners", "potions", "heart_potions")) {
  $normalized = Get-NormalizedSettings ([pscustomobject]@{ appearance = [pscustomobject]@{ mode = $mode } })
  $roundTrip = ($normalized | ConvertTo-Json -Depth 10) | ConvertFrom-Json
  if ($roundTrip.appearance.mode -ne $mode) { throw "Appearance mode round-trip failed: $mode" }
}
$invalidMode = Get-NormalizedSettings ([pscustomobject]@{ appearance = [pscustomobject]@{ mode = "invalid" } })
if ($invalidMode.appearance.mode -ne "rings") { throw "Invalid appearance mode must fall back to rings." }
$smallPotion = Get-NormalizedSettings ([pscustomobject]@{ appearance = [pscustomobject]@{ potionScale = 20 } })
$largePotion = Get-NormalizedSettings ([pscustomobject]@{ appearance = [pscustomobject]@{ potionScale = 220 } })
if ($smallPotion.appearance.potionScale -ne 70 -or $largePotion.appearance.potionScale -ne 140) {
  throw "Potion scale must be clamped to 70-140%."
}
$positioned = Get-NormalizedSettings ([pscustomobject]@{ layout = [pscustomobject]@{ offsetX = 120; offsetY = -80 } })
if ($positioned.layout.offsetX -ne 120 -or $positioned.layout.offsetY -ne -80) {
  throw "Visualization offset round-trip failed."
}
$clampedPosition = Get-NormalizedSettings ([pscustomobject]@{ layout = [pscustomobject]@{ offsetX = 999; offsetY = -999 } })
if ($clampedPosition.layout.offsetX -ne 240 -or $clampedPosition.layout.offsetY -ne -240) {
  throw "Visualization offset clamp failed."
}
$frameText = Get-RuntimeFunctionText "Update-PetFrame"
if ($frameText -notmatch 'Style\.OffsetX' -or $frameText -notmatch 'Style\.OffsetY') {
  throw "Runtime pet-relative positioning is missing."
}
$visibilityText = Get-RuntimeFunctionText "Set-RingVisualsVisible"
if ($visibilityText -notmatch 'Update-StaleIndicator') {
  throw "Stale usage indicator must refresh after the overlay window becomes visible."
}

function Write-AppLog { param([string]$Message) }
function Format-Percent { param($Value) if ($null -eq $Value) { return "--" }; return ("{0:N0}%" -f [double]$Value) }
function Format-ResetAt { param($Value) if ($null -eq $Value) { return "--" }; return ([datetime]$Value).ToString("yyyy-MM-dd HH:mm") }
function Get-LiveUsage { return $null }
function Get-LogUsage { return $script:TestLogUsage }
function Update-TrayText {}
function Update-ReadoutText { return $true }
function Update-StaleIndicator {}
function Update-RingGeometry {}
function Set-FrameTimerInterval { param([bool]$Fast) }

$UsageStaleSeconds = 45
$oldLogObservedAt = (Get-Date).AddMinutes(-10)
$script:TestLogUsage = [PSCustomObject]@{
  Source = "log"
  Plan = "test"
  PrimaryRemaining = 70.0
  SecondaryRemaining = 80.0
  PrimaryResetAt = $oldLogObservedAt.AddHours(1)
  SecondaryResetAt = $oldLogObservedAt.AddDays(1)
  PrimaryWindowSeconds = 18000
  SecondaryWindowSeconds = 604800
  ObservedAt = $oldLogObservedAt
}
$script:HasUsageSnapshot = $false
$script:UsageIsStale = $false
$script:LastUsageSuccessAt = [datetime]::MinValue
$script:DisplayedUsageState = [PSCustomObject]@{ PrimaryRemaining = $null; SecondaryRemaining = $null }
$script:LastUsageSignature = ""
Update-UsageState
if (-not $script:UsageIsStale -or $script:LastUsageSuccessAt -ne $oldLogObservedAt) {
  throw "An old SQLite fallback must remain stale and preserve its observation time."
}

$script:TestLogUsage = $null
$script:HasUsageSnapshot = $true
$script:UsageIsStale = $false
$script:LastUsageSuccessAt = (Get-Date).AddSeconds(-60)
Update-UsageState
if (-not $script:UsageIsStale) { throw "Usage must become stale after live and log updates both fail." }

$now = Get-Date
$script:HasUsageSnapshot = $true
$script:UsageState = [PSCustomObject]@{
  PrimaryRemaining = 83.0
  SecondaryRemaining = 92.0
  PrimaryResetAt = $now.AddHours(3)
  SecondaryResetAt = $now.AddDays(6)
}
$script:PendingUsageSignature = ""
$script:PendingUsageCount = 0
$transient = [PSCustomObject]@{
  PrimaryRemaining = 99.0
  SecondaryRemaining = 100.0
  PrimaryResetAt = $now.AddHours(1)
  SecondaryResetAt = $now.AddDays(6).AddHours(3)
}
if (Test-UsageTransitionStable -Next $transient -Signature "transient") {
  throw "First suspicious recovery must be deferred."
}
if (-not (Test-UsageTransitionStable -Next $transient -Signature "transient")) {
  throw "Repeated matching recovery must eventually be accepted."
}
$stable = [PSCustomObject]@{
  PrimaryRemaining = 82.0
  SecondaryRemaining = 92.0
  PrimaryResetAt = $script:UsageState.PrimaryResetAt
  SecondaryResetAt = $script:UsageState.SecondaryResetAt
}
if (-not (Test-UsageTransitionStable -Next $stable -Signature "stable")) {
  throw "Normal usage decrease must be accepted immediately."
}

Write-Output "Visualization math checks passed: rings, bars, wings, corners, potions, hover hits, and usage stabilization."
