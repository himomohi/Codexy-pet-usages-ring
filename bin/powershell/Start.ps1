param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [string]$InstallDir = "",
  [switch]$NoLiveUsage,
  [int]$UsagePollSeconds = 10,
  [int]$FramePollMs = 120,
  [int]$IdleFramePollMs = 300,
  [int]$PetPollMs = 300,
  [double]$ReadoutPadding = 160.0,
  [string]$SettingsPath = "",
  [switch]$NoTrayIcon,
  [string]$CodexAppPath = "",
  [string]$CodexAppId = "",
  [switch]$NoStartCodex,
  [int]$CodexStartWaitSeconds = 8
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

function Get-ProjectRoot {
  if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    return [System.IO.Path]::GetFullPath($InstallDir)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Get-WindowsPowerShell {
  $winPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($winPs) { return $winPs.Source }
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh.Source }
  throw "PowerShell was not found."
}

function Quote-Argument {
  param([string]$Value)
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

$projectRoot = Get-ProjectRoot
$appScript = Join-Path $projectRoot "src\CodexPetLimitRings.ps1"
if (-not (Test-Path -LiteralPath $appScript)) {
  throw "Missing app script: $appScript"
}

$codexDiscoveryScript = Join-Path $projectRoot "src\CodexAppDiscovery.ps1"
if (Test-Path -LiteralPath $codexDiscoveryScript) {
  . $codexDiscoveryScript
}

& (Join-Path $PSScriptRoot "Stop.ps1") -Quiet

$codexStartResult = $null
if (-not $NoStartCodex -and (Get-Command Start-CodexDesktopApp -ErrorAction SilentlyContinue)) {
  $codexStartResult = Start-CodexDesktopApp `
    -CodexAppPath $CodexAppPath `
    -CodexAppId $CodexAppId `
    -WaitSeconds $CodexStartWaitSeconds
  if ($codexStartResult.Running) {
    if ($codexStartResult.Started) {
      Write-Output "Started Codex Desktop."
    } else {
      Write-Output "Codex Desktop is already running."
    }
    if (-not [string]::IsNullOrWhiteSpace($codexStartResult.ExecutablePath)) {
      Write-Output "Codex Desktop path: $($codexStartResult.ExecutablePath)"
    } elseif (-not [string]::IsNullOrWhiteSpace($codexStartResult.AppId)) {
      Write-Output "Codex Desktop AppID: $($codexStartResult.AppId)"
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($codexStartResult.Error)) {
    Write-Output "Codex Desktop auto-start skipped: $($codexStartResult.Error)"
  } else {
    Write-Output "Codex Desktop auto-start skipped."
  }
} elseif ($NoStartCodex) {
  Write-Output "Codex Desktop auto-start disabled."
}

$powerShell = Get-WindowsPowerShell
$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:TEMP }
$logDir = Join-Path $localAppData "CodexPetLimitRingsWin\logs"
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
  $SettingsPath = Join-Path $projectRoot "settings.json"
}
$args = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-STA",
  "-File", $appScript,
  "-CodexHome", $CodexHome,
  "-UsagePollSeconds", $UsagePollSeconds,
  "-FramePollMs", $FramePollMs,
  "-IdleFramePollMs", $IdleFramePollMs,
  "-PetPollMs", $PetPollMs,
  "-ReadoutPadding", $ReadoutPadding,
  "-SettingsPath", $SettingsPath,
  "-LogDirectory", $logDir
)
if ($NoLiveUsage) { $args += "-NoLiveUsage" }
if ($NoTrayIcon) { $args += "-NoTrayIcon" }

$argumentLine = ($args | ForEach-Object { Quote-Argument ([string]$_) }) -join " "
$process = Start-Process -FilePath $powerShell -ArgumentList $argumentLine -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
Write-Output "Started Codex Pet Limit Rings for Windows."
Write-Output "PID: $($process.Id)"
Write-Output "Project: $projectRoot"
