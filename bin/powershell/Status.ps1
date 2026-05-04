param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexPetLimitRingsWin",
  [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

function Read-Utf8Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$runtimeStateScript = Join-Path $PSScriptRoot "RuntimeState.ps1"
if (-not (Test-Path -LiteralPath $runtimeStateScript)) {
  throw "Missing runtime state helper: $runtimeStateScript"
}
. $runtimeStateScript

$codexDiscoveryScript = Join-Path $projectRoot "src\CodexAppDiscovery.ps1"
if (Test-Path -LiteralPath $codexDiscoveryScript) {
  . $codexDiscoveryScript
}

$processRoots = Get-CodexPetRuntimeRoots -ScriptProjectRoot $projectRoot -InstallDir $InstallDir
$processes = Get-CodexPetRuntimeProcesses -ProjectRoots $processRoots
$pidFiles = @($processRoots | ForEach-Object {
  $paths = Get-CodexPetRuntimePaths -ProjectRoot $_
  if (Test-Path -LiteralPath $paths.PidFile) { $paths.PidFile }
})

$codexApp = $null
$codexDesktopProcess = $null
if (Get-Command Resolve-CodexDesktopApp -ErrorAction SilentlyContinue) {
  $codexApp = Resolve-CodexDesktopApp
  $codexDesktopProcess = Get-CodexDesktopProcess
}

$statePath = Join-Path $CodexHome ".codex-global-state.json"
$state = $null
if (Test-Path -LiteralPath $statePath) {
  try { $state = Read-Utf8Text -Path $statePath | ConvertFrom-Json } catch { $state = $null }
}

$startupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Codex Pet Limit Rings.lnk"

[PSCustomObject]@{
  Installed = Test-Path -LiteralPath $InstallDir
  InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
  InstallMarker = Test-CodexPetInstallMarker -ProjectRoot $InstallDir
  Running = [bool]$processes
  ProcessIds = @($processes | ForEach-Object { $_.ProcessId })
  ProcessRoots = @($processes | ForEach-Object { $_.ProjectRoot } | Sort-Object -Unique)
  PidFiles = $pidFiles
  StartupShortcut = Test-Path -LiteralPath $startupShortcut
  CodexDesktopFound = if ($codexApp) { $codexApp.Found } else { $null }
  CodexDesktopRunning = [bool]$codexDesktopProcess
  CodexDesktopPath = if ($codexApp) { $codexApp.ExecutablePath } else { $null }
  CodexDesktopAppId = if ($codexApp) { $codexApp.AppId } else { $null }
  CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
  CodexStateFile = Test-Path -LiteralPath $statePath
  PetOverlayOpen = if ($state) { $state.'electron-avatar-overlay-open' } else { $null }
  SelectedAvatar = if ($state) { $state.'electron-persisted-atom-state'.'selected-avatar-id' } else { $null }
} | Format-List
