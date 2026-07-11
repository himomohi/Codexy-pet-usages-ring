param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexPetLimitRingsWin",
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$Startup,
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
    ".gitignore",
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
  $InstallDir = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "CodexPetLimitRingsWin"
}
$targetRoot = [System.IO.Path]::GetFullPath($InstallDir)
$versionFile = Join-Path $sourceRoot "VERSION"
$version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -Raw -LiteralPath $versionFile).Trim() } else { "" }

if ((Test-Path -LiteralPath $targetRoot) -and $sourceRoot -ne $targetRoot) {
  $existingEntries = @(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction Stop)
  if ($existingEntries.Count -gt 0 -and -not (Test-CodexPetInstallMarker -ProjectRoot $targetRoot)) {
    if (-not $Force) {
      throw "Refusing to install into non-empty unmarked directory '$targetRoot'. Choose an empty directory or pass -Force after verifying the target."
    }
    Write-Output "Force-installing into unmarked directory: $targetRoot"
  } else {
    Write-Output "Updating existing install: $targetRoot"
  }
}

function New-FolderLinkShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$ShortcutPath,
    [Parameter(Mandatory = $true)][string]$FolderPath,
    [Parameter(Mandatory = $true)][string]$Description
  )
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($ShortcutPath)
  $shortcut.TargetPath = "$env:SystemRoot\explorer.exe"
  $shortcut.Arguments = '"{0}"' -f ([System.IO.Path]::GetFullPath($FolderPath))
  $shortcut.WorkingDirectory = [System.IO.Path]::GetFullPath($FolderPath)
  $shortcut.Description = $Description
  $shortcut.Save()
}

if ($sourceRoot -ne $targetRoot) {
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  foreach ($name in @("Manage.bat", "Install.bat", "Install-AutoStart.bat", "Apply-Installed.bat", "Start.bat", "Stop.bat", "Status.bat", "Settings.bat", "Diagnose.bat", "Uninstall.bat", "assets", "bin", "src", "docs", "tools", "settings", "settings.defaults.json", "README.md", "README.ko.md", "LICENSE", "NOTICE.md", "CHANGELOG.md", "SECURITY.md", "VERSION")) {
    Copy-ProjectFile -Name $name
  }
} else {
  Write-Output "Source and install directory are the same; skipping file copy."
}
if ($sourceRoot -ne $targetRoot) {
  Remove-ObsoleteEntryPoints
}
if ($sourceRoot -ne $targetRoot) {
  Write-CodexPetInstallMarker -ProjectRoot $targetRoot -SourceRoot $sourceRoot -Version $version
} elseif (-not (Test-CodexPetInstallMarker -ProjectRoot $targetRoot)) {
  Write-Output "Source and install directory are the same; no install marker was created."
}

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

if ($Startup -and -not $NoStartup) {
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

# Keep a visible, bidirectional link between the editable source and installed copy.
if ($targetRoot.TrimEnd("\") -ne $sourceRoot.TrimEnd("\")) {
  $installedCopyShortcut = Join-Path $sourceRoot "설치본 열기.lnk"
  New-FolderLinkShortcut `
    -ShortcutPath $installedCopyShortcut `
    -FolderPath $targetRoot `
    -Description "Open the installed Codex Pet Limit Rings copy"
  $sourceProjectShortcut = Join-Path $targetRoot "원본 프로젝트 열기.lnk"
  New-FolderLinkShortcut `
    -ShortcutPath $sourceProjectShortcut `
    -FolderPath $sourceRoot `
    -Description "Open the Codex Pet Limit Rings source project"
  Write-Output "Source/install links: $installedCopyShortcut <-> $sourceProjectShortcut"
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
    $shortcut.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$settingsScript`""
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
