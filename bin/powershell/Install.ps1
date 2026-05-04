param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexPetLimitRingsWin",
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$NoStartup,
  [switch]$NoStartMenu,
  [switch]$NoStart,
  [switch]$NoLiveUsage,
  [string]$CodexAppPath = "",
  [string]$CodexAppId = "",
  [switch]$NoStartCodex,
  [int]$CodexStartWaitSeconds = 8,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-WindowsPowerShell {
  $winPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($winPs) { return $winPs.Source }
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh.Source }
  throw "PowerShell was not found."
}

function Copy-ProjectFile {
  param([string]$Name)
  $source = Join-Path $sourceRoot $Name
  if (-not (Test-Path -LiteralPath $source)) { return }
  $destination = Join-Path $targetRoot $Name
  if ((Get-Item -LiteralPath $source).PSIsContainer) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $destination -Recurse -Force
  } else {
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }
}

function Remove-ObsoleteEntryPoints {
  foreach ($name in @(
    "scripts",
    "install.cmd", "start.cmd", "stop.cmd", "status.cmd", "diagnose.cmd", "uninstall.cmd", "settings.cmd",
    "install.sh", "start.sh", "stop.sh", "status.sh", "diagnose.sh", "uninstall.sh", "settings.sh"
  )) {
    $path = Join-Path $targetRoot $name
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

function Get-StartScriptShortcutArguments {
  param([string]$StartScript)
  $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$StartScript`" -CodexHome `"$CodexHome`""
  if ($NoLiveUsage) { $arguments += " -NoLiveUsage" }
  if ($NoStartCodex) { $arguments += " -NoStartCodex" }
  if (-not [string]::IsNullOrWhiteSpace($CodexAppPath)) {
    $arguments += " -CodexAppPath `"$CodexAppPath`""
  }
  if (-not [string]::IsNullOrWhiteSpace($CodexAppId)) {
    $arguments += " -CodexAppId `"$CodexAppId`""
  }
  if ($CodexStartWaitSeconds -ne 8) {
    $arguments += " -CodexStartWaitSeconds $CodexStartWaitSeconds"
  }
  return $arguments
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "This installer only supports Windows."
}

$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  $InstallDir = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "CodexPetLimitRingsWin"
}
$targetRoot = [System.IO.Path]::GetFullPath($InstallDir)

if ((Test-Path -LiteralPath $targetRoot) -and -not $Force) {
  Write-Output "Updating existing install: $targetRoot"
}

if ($sourceRoot -ne $targetRoot) {
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  foreach ($name in @("bin", "src", "docs", "tools", "settings", "settings.defaults.json", "README.md", "README.ko.md", "LICENSE", "NOTICE.md", "CHANGELOG.md", "SECURITY.md", "VERSION", ".gitignore")) {
    Copy-ProjectFile -Name $name
  }
} else {
  Write-Output "Source and install directory are the same; skipping file copy."
}
Remove-ObsoleteEntryPoints

$powerShell = Get-WindowsPowerShell
$startScript = Join-Path $targetRoot "bin\powershell\Start.ps1"
if (-not (Test-Path -LiteralPath $startScript)) {
  throw "Missing installed start script: $startScript"
}

$codexDiscoveryScript = Join-Path $targetRoot "src\CodexAppDiscovery.ps1"
if (Test-Path -LiteralPath $codexDiscoveryScript) {
  . $codexDiscoveryScript
  $codexApp = Resolve-CodexDesktopApp -CodexAppPath $CodexAppPath -CodexAppId $CodexAppId
  if ($codexApp.Found) {
    Write-Output "Codex Desktop detected: $($codexApp.Source)"
    if (-not [string]::IsNullOrWhiteSpace($codexApp.ExecutablePath)) {
      Write-Output "Codex Desktop path: $($codexApp.ExecutablePath)"
    } elseif (-not [string]::IsNullOrWhiteSpace($codexApp.AppId)) {
      Write-Output "Codex Desktop AppID: $($codexApp.AppId)"
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($codexApp.Error)) {
    Write-Output "Codex Desktop not detected: $($codexApp.Error)"
  } else {
    Write-Output "Codex Desktop not detected."
  }
}

if (-not $NoStartup) {
  $startup = [Environment]::GetFolderPath("Startup")
  $shortcutPath = Join-Path $startup "Codex Pet Limit Rings.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powerShell
  $shortcut.Arguments = Get-StartScriptShortcutArguments -StartScript $startScript
  $shortcut.WorkingDirectory = $targetRoot
  $shortcut.WindowStyle = 7
  $shortcut.Description = "Start Codex Pet Limit Rings for Windows"
  $shortcut.Save()
  Write-Output "Startup shortcut: $shortcutPath"
}

if (-not $NoStartMenu) {
  $programs = [Environment]::GetFolderPath("Programs")
  $programFolder = Join-Path $programs "Codex Pet Limit Rings"
  New-Item -ItemType Directory -Force -Path $programFolder | Out-Null
  $programShortcut = Join-Path $programFolder "Start Codex Pet Limit Rings.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($programShortcut)
  $shortcut.TargetPath = $powerShell
  $shortcut.Arguments = Get-StartScriptShortcutArguments -StartScript $startScript
  $shortcut.WorkingDirectory = $targetRoot
  $shortcut.WindowStyle = 7
  $shortcut.Description = "Start Codex Pet Limit Rings for Windows"
  $shortcut.Save()
  Write-Output "Start Menu shortcut: $programShortcut"

  $settingsScript = Join-Path $targetRoot "bin\powershell\Settings.ps1"
  if (Test-Path -LiteralPath $settingsScript) {
    $settingsShortcut = Join-Path $programFolder "Settings Codex Pet Limit Rings.lnk"
    $shortcut = $shell.CreateShortcut($settingsShortcut)
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$settingsScript`""
    $shortcut.WorkingDirectory = $targetRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = "Open Codex Pet Limit Rings settings"
    $shortcut.Save()
    Write-Output "Settings shortcut: $settingsShortcut"
  }
}

if (-not $NoStart) {
  $startParams = @{
    CodexHome = $CodexHome
    CodexStartWaitSeconds = $CodexStartWaitSeconds
  }
  if ($NoLiveUsage) { $startParams.NoLiveUsage = $true }
  if ($NoStartCodex) { $startParams.NoStartCodex = $true }
  if (-not [string]::IsNullOrWhiteSpace($CodexAppPath)) { $startParams.CodexAppPath = $CodexAppPath }
  if (-not [string]::IsNullOrWhiteSpace($CodexAppId)) { $startParams.CodexAppId = $CodexAppId }
  & $startScript @startParams
}

Write-Output "Installed Codex Pet Limit Rings for Windows."
Write-Output "Install directory: $targetRoot"
