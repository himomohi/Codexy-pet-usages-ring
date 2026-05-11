param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexyPetUsagesRing",
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
  if (Test-ProjectPathExcluded -Path $source) { return }
  $destination = Join-Path $targetRoot $Name
  if ((Get-Item -LiteralPath $source).PSIsContainer) {
    Get-ChildItem -LiteralPath $source -Recurse -File -Force |
      Where-Object { -not (Test-ProjectPathExcluded -Path $_.FullName) } |
      ForEach-Object {
        $relativePath = Get-ProjectRelativePath -Path $_.FullName
        $fileDestination = Join-Path $targetRoot ($relativePath -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fileDestination) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $fileDestination -Force
      }
  } else {
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }
}

function Get-ProjectRelativePath {
  param([string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootWithSeparator = $sourceRoot.TrimEnd("\") + "\"
  if ($fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
    return (($fullPath.Substring($rootWithSeparator.Length)) -replace '\\', '/')
  }
  return ((Split-Path -Leaf $fullPath) -replace '\\', '/')
}

function Test-ProjectPathExcluded {
  param([string]$Path)
  $relativePath = Get-ProjectRelativePath -Path $Path
  $leaf = Split-Path -Leaf $relativePath
  if ($relativePath -in @(
    ".gitignore",
    "gamification.json",
    "settings.json",
    "docs/assets/current-pet-usage-capture.png",
    "docs/assets/imagegen-hero-background.png"
  )) { return $true }
  if ($relativePath -like "dist/*" -or $relativePath -eq "dist") { return $true }
  if ($relativePath -like "logs/*" -or $relativePath -eq "logs") { return $true }
  if ($relativePath -like "qa/*" -or $relativePath -eq "qa") { return $true }
  if ($relativePath -like "*.log" -or $relativePath -like "*.tmp" -or $relativePath -like "*.bak" -or $relativePath -like "*.zip") { return $true }
  if ($leaf -eq ".DS_Store" -or $leaf -eq "Thumbs.db") { return $true }
  return $false
}

function Remove-ObsoleteEntryPoints {
  foreach ($name in @(
    "scripts",
    ".codex-pet-limit-rings.pid",
    ".codex-pet-limit-rings-win.install.json",
    ".gitignore",
    "src\CodexPetLimitRings.ps1",
    "src\codex-pet-limit-rings-windows.ps1",
    "docs\assets\current-pet-usage-capture.png",
    "docs\assets\imagegen-hero-background.png",
    "dist",
    "qa",
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
  $arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$StartScript`" -CodexHome `"$CodexHome`""
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

$runtimeStateScript = Join-Path $PSScriptRoot "RuntimeState.ps1"
if (-not (Test-Path -LiteralPath $runtimeStateScript)) {
  throw "Missing runtime state helper: $runtimeStateScript"
}
. $runtimeStateScript

$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  $InstallDir = Get-CodexPetDefaultInstallDir
}
$targetRoot = [System.IO.Path]::GetFullPath($InstallDir)
$versionFile = Join-Path $sourceRoot "VERSION"
$version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -Raw -LiteralPath $versionFile).Trim() } else { "" }

if ((Test-Path -LiteralPath $targetRoot) -and -not $Force) {
  Write-Output "Updating existing install: $targetRoot"
}

if ($sourceRoot -ne $targetRoot) {
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  foreach ($name in @("Install.bat", "Start.bat", "Stop.bat", "Status.bat", "Settings.bat", "Uninstall.bat", "bin", "src", "docs", "tools", "settings", "settings.defaults.json", "README.md", "README.ko.md", "LICENSE", "NOTICE.md", "CHANGELOG.md", "SECURITY.md", "VERSION")) {
    Copy-ProjectFile -Name $name
  }
} else {
  Write-Output "Source and install directory are the same; skipping file copy."
}
if ($sourceRoot -ne $targetRoot) {
  Remove-ObsoleteEntryPoints
}
Write-CodexPetInstallMarker -ProjectRoot $targetRoot -SourceRoot $sourceRoot -Version $version

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
  $legacyStartupShortcut = Join-Path $startup "Codex Pet Limit Rings.lnk"
  if (Test-Path -LiteralPath $legacyStartupShortcut) {
    Remove-Item -LiteralPath $legacyStartupShortcut -Force
  }
  $shortcutPath = Join-Path $startup "Codexy pet usages ring.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powerShell
  $shortcut.Arguments = Get-StartScriptShortcutArguments -StartScript $startScript
  $shortcut.WorkingDirectory = $targetRoot
  $shortcut.WindowStyle = 7
  $shortcut.Description = "Start Codexy pet usages ring"
  $shortcut.Save()
  Write-Output "Startup shortcut: $shortcutPath"
}

if (-not $NoStartMenu) {
  $programs = [Environment]::GetFolderPath("Programs")
  $legacyProgramFolder = Join-Path $programs "Codex Pet Limit Rings"
  if (Test-Path -LiteralPath $legacyProgramFolder) {
    Remove-Item -LiteralPath $legacyProgramFolder -Recurse -Force
  }
  $programFolder = Join-Path $programs "Codexy pet usages ring"
  New-Item -ItemType Directory -Force -Path $programFolder | Out-Null
  $programShortcut = Join-Path $programFolder "Start Codexy pet usages ring.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($programShortcut)
  $shortcut.TargetPath = $powerShell
  $shortcut.Arguments = Get-StartScriptShortcutArguments -StartScript $startScript
  $shortcut.WorkingDirectory = $targetRoot
  $shortcut.WindowStyle = 7
  $shortcut.Description = "Start Codexy pet usages ring"
  $shortcut.Save()
  Write-Output "Start Menu shortcut: $programShortcut"

  $settingsScript = Join-Path $targetRoot "bin\powershell\Settings.ps1"
  if (Test-Path -LiteralPath $settingsScript) {
    $settingsShortcut = Join-Path $programFolder "Settings Codexy pet usages ring.lnk"
    $shortcut = $shell.CreateShortcut($settingsShortcut)
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$settingsScript`""
    $shortcut.WorkingDirectory = $targetRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = "Open Codexy pet usages ring settings"
    $shortcut.Save()
    Write-Output "Settings shortcut: $settingsShortcut"
  }
}

if (-not $NoStart) {
  $stopScript = Join-Path $targetRoot "bin\powershell\Stop.ps1"
  if (Test-Path -LiteralPath $stopScript) {
    & $stopScript -Quiet
  }
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

Write-Output "Installed Codexy pet usages ring."
Write-Output "Install directory: $targetRoot"
