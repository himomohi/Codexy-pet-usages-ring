param(
  [string]$InstallDir = "",
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

$runtimeStateScript = Join-Path $PSScriptRoot "RuntimeState.ps1"
if (-not (Test-Path -LiteralPath $runtimeStateScript)) {
  throw "Missing runtime state helper: $runtimeStateScript"
}
. $runtimeStateScript

$scriptProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$projectRoots = Get-CodexPetRuntimeRoots -ScriptProjectRoot $scriptProjectRoot -InstallDir $InstallDir
$processes = Get-CodexPetRuntimeProcesses -ProjectRoots $projectRoots

if (-not $processes) {
  foreach ($root in $projectRoots) { Clear-CodexPetPidFile -ProjectRoot $root }
  if (-not $Quiet) { Write-Output "Codex Pet Limit Rings for Windows is not running." }
  exit 0
}

foreach ($process in $processes) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  if (-not $Quiet) { Write-Output "Stopped PID $($process.ProcessId)." }
}

foreach ($root in $projectRoots) { Clear-CodexPetPidFile -ProjectRoot $root }
