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

function Normalize-Language {
  param($Value)
  $language = if ($null -eq $Value) { "auto" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($language -in @("auto", "ko", "en")) { return $language }
  return "auto"
}

function Normalize-VisibilityMode {
  param($Value)
  $mode = if ($null -eq $Value) { "always" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($mode -in @("always", "hover")) { return $mode }
  return "always"
}

function Normalize-AppearanceMode {
  param($Value)
  $mode = if ($null -eq $Value) { "rings" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($mode -in @("rings", "bars", "wings", "corners", "potions")) { return $mode }
  return "rings"
}

function Get-SystemLanguage {
  try {
    if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like "ko*") { return "ko" }
  } catch {}
  return "en"
}

function Resolve-SettingsAutomaticLanguage {
  param($Settings)

  $configured = Normalize-Language (Get-PropertyValue $Settings "language" "auto")
  if ($configured -ne "auto") {
    return [PSCustomObject]@{
      Language = ""
      CountryCode = ""
      Source = "manual"
    }
  }
  return (Get-AutomaticLanguageResult `
    -CachePath $script:LanguageCachePath `
    -TimeoutSeconds 2 `
    -CacheHours 24)
}

function Get-NormalizedSettings {
  param($InputObject)
  $colors = Get-PropertyValue $InputObject "colors" $null
  $appearance = Get-PropertyValue $InputObject "appearance" $null
  $opacity = Get-PropertyValue $InputObject "opacity" $null
  $text = Get-PropertyValue $InputObject "text" $null
  $layout = Get-PropertyValue $InputObject "layout" $null
  $behavior = Get-PropertyValue $InputObject "behavior" $null

  return [ordered]@{
    version = 1
    language = Normalize-Language (Get-PropertyValue $InputObject "language" $null)
    appearance = [ordered]@{
      mode = Normalize-AppearanceMode (Get-PropertyValue $appearance "mode" $null)
      potionScale = Normalize-Number (Get-PropertyValue $appearance "potionScale" $null) 100 70 140
    }
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
      offsetX = Normalize-Number (Get-PropertyValue $layout "offsetX" $null) 0 -240 240
      offsetY = Normalize-Number (Get-PropertyValue $layout "offsetY" $null) 0 -240 240
    }
    behavior = [ordered]@{
      visibilityMode = Normalize-VisibilityMode (Get-PropertyValue $behavior "visibilityMode" $null)
      hoverRange = Normalize-Number (Get-PropertyValue $behavior "hoverRange" $null) 24 0 96
      fadeInMs = Normalize-Number (Get-PropertyValue $behavior "fadeInMs" $null) 120 0 1000
      fadeOutMs = Normalize-Number (Get-PropertyValue $behavior "fadeOutMs" $null) 180 0 1000
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

function Write-JsonResponse {
  param($Context, $Value, [int]$StatusCode = 200)
  $json = $Value | ConvertTo-Json -Depth 12
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "application/json; charset=utf-8"
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-TextResponse {
  param($Context, [string]$Text, [string]$ContentType = "text/plain; charset=utf-8", [int]$StatusCode = 200)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = $ContentType
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-BinaryResponse {
  param($Context, [byte[]]$Bytes, [string]$ContentType)
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = $ContentType
  $Context.Response.ContentLength64 = $Bytes.Length
  $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
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

function Get-PreferredPetDirectory {
  $petsRoot = Join-Path $env:USERPROFILE ".codex\pets"
  if (-not (Test-Path -LiteralPath $petsRoot)) { return $null }
  $preferredId = $null
  $statePath = Join-Path $env:USERPROFILE ".codex\.codex-global-state.json"
  if (Test-Path -LiteralPath $statePath) {
    try {
      $state = Read-Utf8Text -Path $statePath | ConvertFrom-Json
      $candidateValues = @(
        Get-PropertyValue $state "selected-avatar-id" $null
        Get-PropertyValue $state "selectedAvatarId" $null
        Get-PropertyValue $state "avatarId" $null
        Get-PropertyValue $state "petId" $null
      )
      $persisted = Get-PropertyValue $state "electron-persisted-atom-state" $null
      if ($null -ne $persisted) {
        $candidateValues += @(
          Get-PropertyValue $persisted "selected-avatar-id" $null
          Get-PropertyValue $persisted "selectedAvatarId" $null
          Get-PropertyValue $persisted "avatarId" $null
          Get-PropertyValue $persisted "petId" $null
        )
      }
      foreach ($candidateValue in $candidateValues) {
        $match = [regex]::Match([string]$candidateValue, '^(?:custom:)?([A-Za-z0-9_-]+)$')
        if (-not $match.Success) { continue }
        $candidateId = $match.Groups[1].Value
        if (Test-Path -LiteralPath (Join-Path $petsRoot "$candidateId\pet.json")) {
          $preferredId = $candidateId
          break
        }
      }
    } catch {}
  }
  if (-not [string]::IsNullOrWhiteSpace($preferredId)) {
    $preferredPath = Join-Path $petsRoot $preferredId
    if (Test-Path -LiteralPath (Join-Path $preferredPath "pet.json")) { return $preferredPath }
  }
  return Get-ChildItem -LiteralPath $petsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "pet.json") } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}

function Get-PetSpritesheetPath {
  $petDirectory = Get-PreferredPetDirectory
  if ([string]::IsNullOrWhiteSpace($petDirectory)) { return $null }
  try {
    $manifest = Read-Utf8Text -Path (Join-Path $petDirectory "pet.json") | ConvertFrom-Json
    $relativePath = [string](Get-PropertyValue $manifest "spritesheetPath" "spritesheet.png")
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $petDirectory $relativePath))
    $root = [System.IO.Path]::GetFullPath($petDirectory).TrimEnd("\") + "\"
    if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  } catch {}
  return $null
}

function Get-PetPreviewInfo {
  $width = 113.0
  $height = 122.0
  $statePath = Join-Path $env:USERPROFILE ".codex\.codex-global-state.json"
  if (Test-Path -LiteralPath $statePath) {
    try {
      $state = Read-Utf8Text -Path $statePath | ConvertFrom-Json
      $mascot = (Get-PropertyValue $state "electron-avatar-overlay-bounds" $null).mascot
      $width = Normalize-Number (Get-PropertyValue $mascot "width" $null) $width 32 512
      $height = Normalize-Number (Get-PropertyValue $mascot "height" $null) $height 32 512
    } catch {}
  }
  $rows = 9
  $petDirectory = Get-PreferredPetDirectory
  $petId = ""
  $spriteVersion = "none"
  if (-not [string]::IsNullOrWhiteSpace($petDirectory)) {
    try {
      $manifest = Read-Utf8Text -Path (Join-Path $petDirectory "pet.json") | ConvertFrom-Json
      $petId = [string](Get-PropertyValue $manifest "id" (Split-Path -Leaf $petDirectory))
      if ([int](Get-PropertyValue $manifest "spriteVersionNumber" 1) -eq 2) { $rows = 11 }
      $spritesheetPath = Get-PetSpritesheetPath
      if (-not [string]::IsNullOrWhiteSpace($spritesheetPath)) {
        $spriteVersion = [string](Get-Item -LiteralPath $spritesheetPath).LastWriteTimeUtc.Ticks
      }
    } catch {}
  }
  return [ordered]@{
    petId = $petId
    spriteVersion = $spriteVersion
    width = $width
    height = $height
    columns = 8
    rows = $rows
    spriteAvailable = -not [string]::IsNullOrWhiteSpace((Get-PetSpritesheetPath))
  }
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

$projectRoot = Get-ProjectRoot
$script:DefaultsFile = Join-Path $projectRoot "settings.defaults.json"
$settingsHtml = Join-Path $projectRoot "settings\index.html"
$ambientBackground = Join-Path $projectRoot "settings\assets\codex-pet-ambient.webp"
$potionPixelFrame = Join-Path $projectRoot "assets\runtime\potion-pixel-frame.png"
$potionPixelMask = Join-Path $projectRoot "assets\runtime\potion-pixel-mask.png"
$languageDetectionScript = Join-Path $projectRoot "src\LanguageDetection.ps1"
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
  $SettingsPath = Join-Path $projectRoot "settings.json"
}
$script:SettingsFile = [System.IO.Path]::GetFullPath($SettingsPath)

if (-not (Test-Path -LiteralPath $settingsHtml)) {
  throw "Missing settings page: $settingsHtml"
}
if (-not (Test-Path -LiteralPath $languageDetectionScript)) {
  throw "Missing language detection module: $languageDetectionScript"
}
. $languageDetectionScript
$script:LanguageCachePath = Get-LanguageCachePath -SettingsPath $script:SettingsFile

Ensure-SettingsFile
$script:AutomaticLanguageResult = Resolve-SettingsAutomaticLanguage -Settings (Read-Settings)
$server = Start-SettingsListener -StartPort $Port
$script:SessionToken = New-UrlSafeToken
$url = "$($server.Url)?token=$script:SessionToken&v=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Write-Output "Settings UI: $url"
Write-Output "Settings file: $script:SettingsFile"
Write-Output "The server will stop after $TimeoutMinutes minute(s) of inactivity."

if (-not $NoOpen) {
  Start-Process $url | Out-Null
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
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/assets/codex-pet-ambient.webp") {
        if (-not (Test-Path -LiteralPath $ambientBackground)) {
          Write-TextResponse -Context $context -Text "Background illustration not found." -StatusCode 404
        } else {
          Write-BinaryResponse -Context $context -Bytes ([System.IO.File]::ReadAllBytes($ambientBackground)) -ContentType "image/webp"
        }
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/assets/potion-pixel-frame.png") {
        if (-not (Test-Path -LiteralPath $potionPixelFrame)) {
          Write-TextResponse -Context $context -Text "Pixel potion frame not found." -StatusCode 404
        } else {
          Write-BinaryResponse -Context $context -Bytes ([System.IO.File]::ReadAllBytes($potionPixelFrame)) -ContentType "image/png"
        }
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/assets/potion-pixel-mask.png") {
        if (-not (Test-Path -LiteralPath $potionPixelMask)) {
          Write-TextResponse -Context $context -Text "Pixel potion mask not found." -StatusCode 404
        } else {
          Write-BinaryResponse -Context $context -Bytes ([System.IO.File]::ReadAllBytes($potionPixelMask)) -ContentType "image/png"
        }
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/settings") {
        Write-JsonResponse -Context $context -Value @{
          settings = Read-Settings
          settingsPath = $script:SettingsFile
          automaticLanguage = $script:AutomaticLanguageResult.Language
          languageCountry = $script:AutomaticLanguageResult.CountryCode
          languageSource = $script:AutomaticLanguageResult.Source
          systemLanguage = $script:AutomaticLanguageResult.Language
        }
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/defaults") {
        Write-JsonResponse -Context $context -Value (Read-Defaults)
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/pet-preview") {
        Write-JsonResponse -Context $context -Value (Get-PetPreviewInfo)
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/pet-spritesheet") {
        $spritesheetPath = Get-PetSpritesheetPath
        if ([string]::IsNullOrWhiteSpace($spritesheetPath)) {
          Write-TextResponse -Context $context -Text "Pet spritesheet not found." -StatusCode 404
        } else {
          $extension = [System.IO.Path]::GetExtension($spritesheetPath).ToLowerInvariant()
          $contentType = if ($extension -eq ".webp") { "image/webp" } else { "image/png" }
          Write-BinaryResponse -Context $context -Bytes ([System.IO.File]::ReadAllBytes($spritesheetPath)) -ContentType $contentType
        }
      } elseif ($context.Request.HttpMethod -eq "POST" -and $path -eq "/api/settings") {
        $body = Get-RequestBody -Request $context.Request
        $settings = Get-NormalizedSettings ($body | ConvertFrom-Json)
        Write-Utf8Text -Path $script:SettingsFile -Text (($settings | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
        $script:AutomaticLanguageResult = Resolve-SettingsAutomaticLanguage -Settings $settings
        Write-JsonResponse -Context $context -Value @{
          ok = $true
          settings = $settings
          settingsPath = $script:SettingsFile
          automaticLanguage = $script:AutomaticLanguageResult.Language
          languageCountry = $script:AutomaticLanguageResult.CountryCode
          languageSource = $script:AutomaticLanguageResult.Source
          systemLanguage = $script:AutomaticLanguageResult.Language
        }
      } else {
        Write-TextResponse -Context $context -Text "Not found" -StatusCode 404
      }
    } catch {
      Write-TextResponse -Context $context -Text $_.Exception.Message -StatusCode 500
    } finally {
      $context.Response.OutputStream.Close()
    }
  }
} finally {
  $server.Listener.Stop()
  $server.Listener.Close()
}
