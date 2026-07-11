param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$TestLiveUsage
)

$ErrorActionPreference = "Continue"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  Write-Output "This project only supports Windows."
  exit 1
}

function Read-Utf8Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$codexDiscoveryScript = Join-Path $projectRoot "src\CodexAppDiscovery.ps1"
if (Test-Path -LiteralPath $codexDiscoveryScript) {
  . $codexDiscoveryScript
}

Write-Output "Codex Pet Limit Rings for Windows diagnostics"
Write-Output "PowerShell: $($PSVersionTable.PSVersion)"
Write-Output "OS: $([Environment]::OSVersion.VersionString)"
Write-Output "CodexHome: $CodexHome"

$statePath = Join-Path $CodexHome ".codex-global-state.json"
$authPath = Join-Path $CodexHome "auth.json"
$logs2Path = Join-Path $CodexHome "logs_2.sqlite"
$logs1Path = Join-Path $CodexHome "logs_1.sqlite"

Write-Output "State file: $(Test-Path -LiteralPath $statePath) $statePath"
Write-Output "Auth file: $(Test-Path -LiteralPath $authPath) $authPath"
Write-Output "logs_2.sqlite: $(Test-Path -LiteralPath $logs2Path)"
Write-Output "logs_1.sqlite: $(Test-Path -LiteralPath $logs1Path)"

try {
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName System.Windows.Forms
  Write-Output "WPF/WinForms: available"
} catch {
  Write-Output "WPF/WinForms: unavailable - $($_.Exception.Message)"
}

if (Get-Command Resolve-CodexDesktopApp -ErrorAction SilentlyContinue) {
  $codexDesktopProcess = Get-CodexDesktopProcess
  $codexApp = Resolve-CodexDesktopApp
  Write-Output "Codex desktop process count: $(@($codexDesktopProcess).Count)"
  Write-Output "Codex desktop running: $([bool]$codexDesktopProcess)"
  Write-Output "Codex desktop detected: $($codexApp.Found) ($($codexApp.Source))"
  if (-not [string]::IsNullOrWhiteSpace($codexApp.ExecutablePath)) {
    Write-Output "Codex desktop path: $($codexApp.ExecutablePath)"
  }
  if (-not [string]::IsNullOrWhiteSpace($codexApp.AppId)) {
    Write-Output "Codex desktop AppID: $($codexApp.AppId)"
  }
  if (-not [string]::IsNullOrWhiteSpace($codexApp.Error)) {
    Write-Output "Codex desktop detection note: $($codexApp.Error)"
  }
}

if (Test-Path -LiteralPath $statePath) {
  try {
    $state = Read-Utf8Text -Path $statePath | ConvertFrom-Json
    $bounds = $state.'electron-avatar-overlay-bounds'
    Write-Output "Pet overlay open: $($state.'electron-avatar-overlay-open')"
    Write-Output "Pet bounds present: $([bool]$bounds)"
    if ($bounds) {
      Write-Output "Pet bounds: x=$($bounds.x), y=$($bounds.y), width=$($bounds.width), height=$($bounds.height)"
    }
  } catch {
    Write-Output "State parse failed: $($_.Exception.Message)"
  }
}

if ($TestLiveUsage) {
  try {
    $auth = Read-Utf8Text -Path $authPath | ConvertFrom-Json
    $token = $auth.tokens.access_token
    if ([string]::IsNullOrWhiteSpace($token)) {
      Write-Output "Live usage: no access token"
    } else {
      $payload = Invoke-RestMethod `
        -Uri "https://chatgpt.com/backend-api/wham/usage" `
        -Headers @{ Authorization = "Bearer $token"; Accept = "application/json" } `
        -TimeoutSec 8
      Write-Output "Live usage: ok, plan=$($payload.plan_type), hasRateLimit=$([bool]$payload.rate_limit)"
    }
  } catch {
    Write-Output "Live usage: failed - $($_.Exception.Message)"
  }
}

& (Join-Path $PSScriptRoot "Status.ps1") -CodexHome $CodexHome
