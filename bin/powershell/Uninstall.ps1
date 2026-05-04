param(
  [string]$InstallDir = "$env:LOCALAPPDATA\CodexPetLimitRingsWin",
  [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$stopScript = Join-Path $projectRoot "bin\powershell\Stop.ps1"
if (Test-Path -LiteralPath $stopScript) {
  & $stopScript -Quiet
} else {
  Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match '(CodexPetLimitRings\.ps1|codex-pet-limit-rings-windows\.ps1)' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

$startup = [Environment]::GetFolderPath("Startup")
$startupShortcut = Join-Path $startup "Codex Pet Limit Rings.lnk"
if (Test-Path -LiteralPath $startupShortcut) {
  Remove-Item -LiteralPath $startupShortcut -Force
  Write-Output "Removed startup shortcut: $startupShortcut"
}

$programShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Codex Pet Limit Rings\Start Codex Pet Limit Rings.lnk"
if (Test-Path -LiteralPath $programShortcut) {
  Remove-Item -LiteralPath $programShortcut -Force
  Write-Output "Removed Start Menu shortcut: $programShortcut"
}
$settingsShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Codex Pet Limit Rings\Settings Codex Pet Limit Rings.lnk"
if (Test-Path -LiteralPath $settingsShortcut) {
  Remove-Item -LiteralPath $settingsShortcut -Force
  Write-Output "Removed settings shortcut: $settingsShortcut"
}
$programFolder = Split-Path -Parent $programShortcut
if ((Test-Path -LiteralPath $programFolder) -and -not (Get-ChildItem -LiteralPath $programFolder -Force)) {
  Remove-Item -LiteralPath $programFolder -Force
}

if ($RemoveFiles) {
  $targetRoot = [System.IO.Path]::GetFullPath($InstallDir)
  if (Test-Path -LiteralPath $targetRoot) {
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
    Write-Output "Removed install directory: $targetRoot"
  }
}

Write-Output "Uninstalled Codex Pet Limit Rings for Windows."
