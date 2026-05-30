param(
  [string]$InstallDir = "",
  [string]$SettingsPath = "",
  [int]$Port = 8797,
  [int]$TimeoutMinutes = 20,
  [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Settings UI only supports Windows."
}

function Get-ProjectRoot {
  if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    return [System.IO.Path]::GetFullPath($InstallDir)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Read-Utf8Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8Text {
  param([string]$Path, [string]$Text)
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

function Get-PropertyValue {
  param($Object, [string]$Name, $Default)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Normalize-Hex {
  param($Value, [string]$Fallback)
  if ($null -eq $Value) { return $Fallback }
  $hex = ([string]$Value).Trim()
  if ($hex.StartsWith("#")) { $hex = $hex.Substring(1) }
  if ($hex.Length -eq 3) {
    $hex = -join ($hex.ToCharArray() | ForEach-Object { "$_$_" })
  }
  if ($hex -notmatch '^[0-9a-fA-F]{6}$') { return $Fallback }
  return "#$($hex.ToUpperInvariant())"
}

function Normalize-Number {
  param($Value, [double]$Fallback, [double]$Min, [double]$Max)
  if ($null -eq $Value) { return $Fallback }
  try { return [Math]::Round([Math]::Max($Min, [Math]::Min($Max, [double]$Value)), 3) } catch { return $Fallback }
}

function Normalize-Bool {
  param($Value, [bool]$Fallback)
  if ($null -eq $Value) { return $Fallback }
  if ($Value -is [bool]) { return [bool]$Value }
  $text = ([string]$Value).Trim().ToLowerInvariant()
  if ($text -in @("true", "1", "yes", "on")) { return $true }
  if ($text -in @("false", "0", "no", "off")) { return $false }
  return $Fallback
}

function Normalize-Language {
  param($Value)
  $language = if ($null -eq $Value) { "auto" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($language -in @("auto", "ko", "en", "ja", "zh")) { return $language }
  return "auto"
}

function Normalize-DisplayMode {
  param($Value)
  $displayMode = if ($null -eq $Value) { "ring" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($displayMode -in @("ring", "battery", "badge")) { return $displayMode }
  return "ring"
}

function Normalize-GrowthMode {
  param($Value)
  $growthMode = if ($null -eq $Value) { "balanced" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($growthMode -in @("conserve", "balanced", "active")) { return $growthMode }
  return "balanced"
}

function Normalize-GamificationHudFocus {
  param($Value)
  $focus = if ($null -eq $Value) { "growth" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($focus -in @("growth", "combo")) { return $focus }
  return "growth"
}

function Normalize-VisibilityMode {
  param($Value)
  $visibilityMode = if ($null -eq $Value) { "hover" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($visibilityMode -in @("hover", "always")) { return $visibilityMode }
  return "hover"
}

function Get-SystemLanguage {
  try {
    $cultureName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($cultureName -like "ko*") { return "ko" }
    if ($cultureName -like "ja*") { return "ja" }
    if ($cultureName -like "zh*") { return "zh" }
  } catch {}
  return "en"
}

function Get-NormalizedSettings {
  param($InputObject)
  $colors = Get-PropertyValue $InputObject "colors" $null
  $opacity = Get-PropertyValue $InputObject "opacity" $null
  $text = Get-PropertyValue $InputObject "text" $null
  $layout = Get-PropertyValue $InputObject "layout" $null
  $behavior = Get-PropertyValue $InputObject "behavior" $null
  $gamification = Get-PropertyValue $InputObject "gamification" $null

  return [ordered]@{
    version = 1
    language = Normalize-Language (Get-PropertyValue $InputObject "language" $null)
    displayMode = Normalize-DisplayMode (Get-PropertyValue $InputObject "displayMode" $null)
    colors = [ordered]@{
      primary = Normalize-Hex (Get-PropertyValue $colors "primary" $null) "#3CEBBD"
      secondary = Normalize-Hex (Get-PropertyValue $colors "secondary" $null) "#56B2FF"
      warning = Normalize-Hex (Get-PropertyValue $colors "warning" $null) "#FF4238"
      caution = Normalize-Hex (Get-PropertyValue $colors "caution" $null) "#FFAE33"
      track = Normalize-Hex (Get-PropertyValue $colors "track" $null) "#FFFFFF"
      readoutText = Normalize-Hex (Get-PropertyValue $colors "readoutText" $null) "#FFFFFF"
      outerReadoutBackground = Normalize-Hex (Get-PropertyValue $colors "outerReadoutBackground" $null) "#0D181E"
      innerReadoutBackground = Normalize-Hex (Get-PropertyValue $colors "innerReadoutBackground" $null) "#0F1624"
    }
    opacity = [ordered]@{
      primary = Normalize-Number (Get-PropertyValue $opacity "primary" $null) 0.67 0 1
      secondary = Normalize-Number (Get-PropertyValue $opacity "secondary" $null) 0.63 0 1
      warning = Normalize-Number (Get-PropertyValue $opacity "warning" $null) 0.73 0 1
      track = Normalize-Number (Get-PropertyValue $opacity "track" $null) 0.09 0 1
      readout = Normalize-Number (Get-PropertyValue $opacity "readout" $null) 0.71 0 1
      readoutText = Normalize-Number (Get-PropertyValue $opacity "readoutText" $null) 0.94 0 1
    }
    text = [ordered]@{
      fontSize = Normalize-Number (Get-PropertyValue $text "fontSize" $null) 10.5 8 24
      lineHeight = Normalize-Number (Get-PropertyValue $text "lineHeight" $null) 13 10 32
    }
    layout = [ordered]@{
      ringGap = Normalize-Number (Get-PropertyValue $layout "ringGap" $null) 22 0 96
    }
    behavior = [ordered]@{
      visibilityMode = Normalize-VisibilityMode (Get-PropertyValue $behavior "visibilityMode" $null)
      hoverRange = Normalize-Number (Get-PropertyValue $behavior "hoverRange" $null) 24 0 96
      fadeInMs = Normalize-Number (Get-PropertyValue $behavior "fadeInMs" $null) 120 0 1000
      fadeOutMs = Normalize-Number (Get-PropertyValue $behavior "fadeOutMs" $null) 180 0 1000
    }
    gamification = [ordered]@{
      enabled = Normalize-Bool (Get-PropertyValue $gamification "enabled" $null) $false
      growthMode = Normalize-GrowthMode (Get-PropertyValue $gamification "growthMode" $null)
      hudFocus = Normalize-GamificationHudFocus (Get-PropertyValue $gamification "hudFocus" $null)
      showGrowthChip = Normalize-Bool (Get-PropertyValue $gamification "showGrowthChip" $null) $true
      showHoverReadout = Normalize-Bool (Get-PropertyValue $gamification "showHoverReadout" $null) $true
      showKeyCounter = Normalize-Bool (Get-PropertyValue $gamification "showKeyCounter" $null) $true
      showKeyEffects = Normalize-Bool (Get-PropertyValue $gamification "showKeyEffects" $null) $true
    }
  }
}

function Ensure-SettingsFile {
  $settingsDirectory = Split-Path -Parent $script:SettingsFile
  if (-not [string]::IsNullOrWhiteSpace($settingsDirectory)) {
    New-Item -ItemType Directory -Force -Path $settingsDirectory | Out-Null
  }
  if (Test-Path -LiteralPath $script:SettingsFile) { return }
  if (Test-Path -LiteralPath $script:DefaultsFile) {
    Copy-Item -LiteralPath $script:DefaultsFile -Destination $script:SettingsFile -Force
    return
  }
  $defaults = Get-NormalizedSettings $null
  Write-Utf8Text -Path $script:SettingsFile -Text ($defaults | ConvertTo-Json -Depth 8)
}

function Read-Settings {
  Ensure-SettingsFile
  $raw = Read-Utf8Text -Path $script:SettingsFile
  return Get-NormalizedSettings ($raw | ConvertFrom-Json)
}

function Read-Defaults {
  if (Test-Path -LiteralPath $script:DefaultsFile) {
    return Get-NormalizedSettings ((Read-Utf8Text -Path $script:DefaultsFile) | ConvertFrom-Json)
  }
  return Get-NormalizedSettings $null
}

function Read-GamificationStateSummary {
  $statePath = Join-Path $env:LOCALAPPDATA "CodexyPetUsagesRing\gamification.json"
  $empty = [ordered]@{
    inventory = [ordered]@{
      snack = 0
      gem = 0
      ticket = 0
      patch = 0
      fontPixel = $false
      fontTerminal = $false
      themeForest = $false
      themeArcane = $false
      themeRoyal = $false
      themeCyber = $false
      themeCelestial = $false
      activeFont = ""
      activeTheme = ""
      rewardRolls = 0
      totalDrops = 0
      totalKeys = 0
      lastDropAt = $null
      lastDropItem = ""
    }
  }
  try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $empty }
    $state = (Read-Utf8Text -Path $statePath) | ConvertFrom-Json
    $inventory = Get-PropertyValue $state "inventory" $null
    if ($null -eq $inventory) { return $empty }
    $fontPixel = [bool](Get-PropertyValue $inventory "fontPixel" $false)
    $fontTerminal = [bool](Get-PropertyValue $inventory "fontTerminal" $false)
    $themeForest = [bool](Get-PropertyValue $inventory "themeForest" $false)
    $themeArcane = [bool](Get-PropertyValue $inventory "themeArcane" $false)
    $themeRoyal = [bool](Get-PropertyValue $inventory "themeRoyal" $false)
    $themeCyber = [bool](Get-PropertyValue $inventory "themeCyber" $false)
    $themeCelestial = [bool](Get-PropertyValue $inventory "themeCelestial" $false)
    $themeKeys = @("themeForest", "themeArcane", "themeRoyal", "themeCyber", "themeCelestial")
    $unlockKeys = @("fontPixel", "fontTerminal") + $themeKeys
    $cosmeticDropCount = @($fontPixel, $fontTerminal, $themeForest, $themeArcane, $themeRoyal, $themeCyber, $themeCelestial).Where({ $_ }).Count
    $activeFont = [string](Get-PropertyValue $inventory "activeFont" "")
    if ($activeFont -notin @("fontPixel", "fontTerminal") -or -not [bool](Get-PropertyValue $inventory $activeFont $false)) { $activeFont = "" }
    $activeTheme = [string](Get-PropertyValue $inventory "activeTheme" "")
    if ($activeTheme -notin $themeKeys -or -not [bool](Get-PropertyValue $inventory $activeTheme $false)) { $activeTheme = "" }
    $lastDropItem = [string](Get-PropertyValue $inventory "lastDropItem" "")
    $lastDropAt = Get-PropertyValue $inventory "lastDropAt" $null
    if ($lastDropItem -notin $unlockKeys) {
      $lastDropItem = ""
      $lastDropAt = $null
    }
    $rewardRolls = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "rewardRolls" 0))
    if ($cosmeticDropCount -le 0) { $rewardRolls = 0 }
    return [ordered]@{
      inventory = [ordered]@{
        snack = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "snack" 0))
        gem = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "gem" 0))
        ticket = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "ticket" 0))
        patch = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "patch" 0))
        fontPixel = $fontPixel
        fontTerminal = $fontTerminal
        themeForest = $themeForest
        themeArcane = $themeArcane
        themeRoyal = $themeRoyal
        themeCyber = $themeCyber
        themeCelestial = $themeCelestial
        activeFont = $activeFont
        activeTheme = $activeTheme
        rewardRolls = $rewardRolls
        totalDrops = $cosmeticDropCount
        totalKeys = [Math]::Max(0, [int][double](Get-PropertyValue $inventory "totalKeys" 0))
        lastDropAt = $lastDropAt
        lastDropItem = $lastDropItem
      }
    }
  } catch {
    return $empty
  }
}

function Write-JsonResponse {
  param($Context, $Value, [int]$StatusCode = 200)
  $json = $Value | ConvertTo-Json -Depth 12
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "application/json; charset=utf-8"
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-TextResponse {
  param($Context, [string]$Text, [string]$ContentType = "text/plain; charset=utf-8", [int]$StatusCode = 200)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = $ContentType
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Get-RequestBody {
  param($Request)
  $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
  try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function New-UrlSafeToken {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return ([Convert]::ToBase64String($bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_")
}

function Test-RequestToken {
  param($Request)
  if ([string]::IsNullOrWhiteSpace($script:SessionToken)) { return $false }
  $queryToken = $Request.QueryString["token"]
  $headerToken = $Request.Headers["X-Codex-Pet-Settings-Token"]
  return ($queryToken -eq $script:SessionToken -or $headerToken -eq $script:SessionToken)
}

function Start-SettingsListener {
  param([int]$StartPort)
  for ($candidate = $StartPort; $candidate -lt ($StartPort + 30); $candidate++) {
    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://127.0.0.1:$candidate/"
    $listener.Prefixes.Add($prefix)
    try {
      $listener.Start()
      return [PSCustomObject]@{ Listener = $listener; Url = $prefix; Port = $candidate }
    } catch {
      $listener.Close()
    }
  }
  throw "Could not start a local settings server on ports $StartPort-$($StartPort + 29)."
}

function Open-SettingsUrl {
  param([string]$Url)
  foreach ($browser in @("msedge.exe", "chrome.exe", "firefox.exe")) {
    try {
      $command = Get-Command $browser -ErrorAction SilentlyContinue
      if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        Start-Process -FilePath $command.Source -ArgumentList @($Url) | Out-Null
        return
      }
    } catch {}
  }
  try {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($Url) | Out-Null
  } catch {
    Write-Warning "Could not open settings URL automatically: $Url"
  }
}

$projectRoot = Get-ProjectRoot
$script:DefaultsFile = Join-Path $projectRoot "settings.defaults.json"
$settingsHtml = Join-Path $projectRoot "settings\index.html"
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
  $SettingsPath = Join-Path $projectRoot "settings.json"
}
$script:SettingsFile = [System.IO.Path]::GetFullPath($SettingsPath)

if (-not (Test-Path -LiteralPath $settingsHtml)) {
  throw "Missing settings page: $settingsHtml"
}

Ensure-SettingsFile
$server = Start-SettingsListener -StartPort $Port
$script:SessionToken = New-UrlSafeToken
$url = "$($server.Url)?token=$script:SessionToken&v=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Write-Output "Settings UI: $url"
Write-Output "Settings file: $script:SettingsFile"
Write-Output "The server will stop after $TimeoutMinutes minute(s) of inactivity."

if (-not $NoOpen) {
  Open-SettingsUrl -Url $url
}

$deadline = (Get-Date).AddMinutes([Math]::Max(1, $TimeoutMinutes))
try {
  while ((Get-Date) -lt $deadline) {
    $async = $server.Listener.BeginGetContext($null, $null)
    while (-not $async.AsyncWaitHandle.WaitOne(500)) {
      if ((Get-Date) -ge $deadline) { break }
    }
    if ((Get-Date) -ge $deadline -and -not $async.IsCompleted) { break }
    $context = $server.Listener.EndGetContext($async)
    $deadline = (Get-Date).AddMinutes([Math]::Max(1, $TimeoutMinutes))
    try {
      $path = $context.Request.Url.AbsolutePath.TrimEnd("/")
      if ([string]::IsNullOrWhiteSpace($path)) { $path = "/" }
      if (($path -like "/api/*") -and -not (Test-RequestToken -Request $context.Request)) {
        Write-TextResponse -Context $context -Text "Forbidden: invalid settings session token." -StatusCode 403
      } elseif ($context.Request.HttpMethod -eq "OPTIONS") {
        $context.Response.StatusCode = 204
      } elseif ($context.Request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
        Write-TextResponse -Context $context -Text (Read-Utf8Text -Path $settingsHtml) -ContentType "text/html; charset=utf-8"
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/settings") {
        Write-JsonResponse -Context $context -Value @{
          settings = Read-Settings
          settingsPath = $script:SettingsFile
          systemLanguage = Get-SystemLanguage
          gamificationState = Read-GamificationStateSummary
        }
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/defaults") {
        Write-JsonResponse -Context $context -Value (Read-Defaults)
      } elseif ($context.Request.HttpMethod -eq "POST" -and $path -eq "/api/settings") {
        $body = Get-RequestBody -Request $context.Request
        $settings = Get-NormalizedSettings ($body | ConvertFrom-Json)
        Write-Utf8Text -Path $script:SettingsFile -Text (($settings | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
        Write-JsonResponse -Context $context -Value @{
          ok = $true
          settings = $settings
          settingsPath = $script:SettingsFile
          systemLanguage = Get-SystemLanguage
        }
      } else {
        Write-TextResponse -Context $context -Text "Not found" -StatusCode 404
      }
    } catch {
      try {
        Write-TextResponse -Context $context -Text $_.Exception.Message -StatusCode 500
      } catch {
        try { $context.Response.Close() } catch {}
      }
    } finally {
      try { $context.Response.OutputStream.Close() } catch {}
    }
  }
} finally {
  $server.Listener.Stop()
  $server.Listener.Close()
}
