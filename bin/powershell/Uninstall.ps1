param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexPetLimitRingsWin",
  [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$targetRoot = [System.IO.Path]::GetFullPath($InstallDir)
$runtimeStateScript = Join-Path $projectRoot "bin\powershell\RuntimeState.ps1"
if (-not (Test-Path -LiteralPath $runtimeStateScript)) {
  throw "Missing runtime state helper: $runtimeStateScript"
}
. $runtimeStateScript

function Test-FolderLinkTargetsPath {
  param([string]$ShortcutPath, [string]$ExpectedPath)
  if (-not (Test-Path -LiteralPath $ShortcutPath)) { return $false }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $expected = [System.IO.Path]::GetFullPath($ExpectedPath).TrimEnd("\")
    $argumentPath = ([string]$shortcut.Arguments).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($argumentPath)) { return $false }
    return ([System.IO.Path]::GetFullPath($argumentPath).TrimEnd("\") -eq $expected)
  } catch {
    return $false
  }
}

function Test-ShortcutTargetsInstallDir {
  param(
    [string]$ShortcutPath,
    [string]$InstallRoot
  )
  if (-not (Test-Path -LiteralPath $ShortcutPath)) { return $false }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $root = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
    if (-not [string]::IsNullOrWhiteSpace($shortcut.WorkingDirectory)) {
      $workingDirectory = [System.IO.Path]::GetFullPath($shortcut.WorkingDirectory).TrimEnd("\")
      if ($workingDirectory -eq $root) { return $true }
    }
    foreach ($scriptName in @("Start.ps1", "Settings.ps1")) {
      $scriptPath = Join-Path $root "bin\powershell\$scriptName"
      if (Test-CodexPetPathInCommandLine -CommandLine $shortcut.Arguments -Path $scriptPath) {
        return $true
      }
    }
  } catch {
    return $false
  }
  return $false
}

$stopScript = Join-Path $projectRoot "bin\powershell\Stop.ps1"
if (Test-Path -LiteralPath $stopScript) {
  & $stopScript -InstallDir $targetRoot -Quiet
} else {
  Get-CodexPetRuntimeProcesses -ProjectRoots @($targetRoot) |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

$startup = [Environment]::GetFolderPath("Startup")
$startupShortcut = Join-Path $startup "Codex Pet Limit Rings.lnk"
if (Test-ShortcutTargetsInstallDir -ShortcutPath $startupShortcut -InstallRoot $targetRoot) {
  Remove-Item -LiteralPath $startupShortcut -Force
  Write-Output "Removed startup shortcut: $startupShortcut"
}

$programShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Codex Pet Limit Rings\Start Codex Pet Limit Rings.lnk"
if (Test-ShortcutTargetsInstallDir -ShortcutPath $programShortcut -InstallRoot $targetRoot) {
  Remove-Item -LiteralPath $programShortcut -Force
  Write-Output "Removed Start Menu shortcut: $programShortcut"
}
$settingsShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Codex Pet Limit Rings\Settings Codex Pet Limit Rings.lnk"
if (Test-ShortcutTargetsInstallDir -ShortcutPath $settingsShortcut -InstallRoot $targetRoot) {
  Remove-Item -LiteralPath $settingsShortcut -Force
  Write-Output "Removed settings shortcut: $settingsShortcut"
}
$programFolder = Split-Path -Parent $programShortcut
if ((Test-Path -LiteralPath $programFolder) -and -not (Get-ChildItem -LiteralPath $programFolder -Force)) {
  Remove-Item -LiteralPath $programFolder -Force
}

if ($RemoveFiles) {
  if (Test-Path -LiteralPath $targetRoot) {
    if (-not (Test-CodexPetInstallMarker -ProjectRoot $targetRoot)) {
      throw "Refusing to remove '$targetRoot' because the install marker is missing or invalid. Run Install.ps1 once to mark this install, or remove the directory manually after verifying the path."
    }
    foreach ($requiredInstallFile in @("VERSION", "bin\powershell\Uninstall.ps1", "src\CodexPetLimitRings.ps1")) {
      if (-not (Test-Path -LiteralPath (Join-Path $targetRoot $requiredInstallFile))) {
        throw "Refusing to remove '$targetRoot' because required installed file is missing: $requiredInstallFile"
      }
    }
    $installMarker = Get-CodexPetInstallMarker -ProjectRoot $targetRoot
    if ($null -ne $installMarker -and -not [string]::IsNullOrWhiteSpace([string]$installMarker.sourceRoot)) {
      $sourceLink = Join-Path ([System.IO.Path]::GetFullPath([string]$installMarker.sourceRoot)) "설치본 열기.lnk"
      if (Test-FolderLinkTargetsPath -ShortcutPath $sourceLink -ExpectedPath $targetRoot) {
        Remove-Item -LiteralPath $sourceLink -Force
        Write-Output "Removed source/install link: $sourceLink"
      }
    }
    $driveRoot = [System.IO.Path]::GetPathRoot($targetRoot).TrimEnd("\")
    if ($targetRoot.TrimEnd("\") -eq $driveRoot) {
      throw "Refusing to remove a drive root: $targetRoot"
    }
    $originalLocation = (Get-Location).Path
    try {
      Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())
      Remove-Item -LiteralPath $targetRoot -Recurse -Force
    } finally {
      if (Test-Path -LiteralPath $originalLocation) {
        Set-Location -LiteralPath $originalLocation
      }
    }
    Write-Output "Removed install directory: $targetRoot"
  }
}

Write-Output "Uninstalled Codex Pet Limit Rings for Windows."
