param(
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

$processes = Get-CimInstance Win32_Process |
  Where-Object {
    $_.ProcessId -ne $PID -and
    $_.CommandLine -match '(CodexPetLimitRings\.ps1|codex-pet-limit-rings-windows\.ps1)'
  }

if (-not $processes) {
  if (-not $Quiet) { Write-Output "Codex Pet Limit Rings for Windows is not running." }
  exit 0
}

foreach ($process in $processes) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  if (-not $Quiet) { Write-Output "Stopped PID $($process.ProcessId)." }
}
