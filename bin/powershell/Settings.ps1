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
  if ($language -in @("auto", "ko", "en", "ja", "zh")) { return $language }
  return "auto"
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

  return [ordered]@{
    version = 1
    language = Normalize-Language (Get-PropertyValue $InputObject "language" $null)
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
      } elseif ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/settings") {
        Write-JsonResponse -Context $context -Value @{
          settings = Read-Settings
          settingsPath = $script:SettingsFile
          systemLanguage = Get-SystemLanguage
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
      Write-TextResponse -Context $context -Text $_.Exception.Message -StatusCode 500
    } finally {
      $context.Response.OutputStream.Close()
    }
  }
} finally {
  $server.Listener.Stop()
  $server.Listener.Close()
}
