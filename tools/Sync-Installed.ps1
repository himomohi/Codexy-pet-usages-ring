param(
  [string]$InstallDir = "",
  [switch]$StartIfStopped,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Installed-copy sync only supports Windows."
}

$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$runtimeStateScript = Join-Path $sourceRoot "bin\powershell\RuntimeState.ps1"
if (-not (Test-Path -LiteralPath $runtimeStateScript)) {
  throw "Missing runtime state helper: $runtimeStateScript"
}
. $runtimeStateScript

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  $InstallDir = Get-CodexPetDefaultInstallDir
}
$targetRoot = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd("\")
$sourceFull = $sourceRoot.TrimEnd("\")
if ($targetRoot -eq $sourceFull) {
  throw "The source folder is already the selected install directory."
}

$marker = Get-CodexPetInstallMarker -ProjectRoot $targetRoot
if ($null -eq $marker) {
  throw "No trusted installed copy was found at '$targetRoot'. Run Install.bat first."
}
$markedSource = [System.IO.Path]::GetFullPath([string]$marker.sourceRoot).TrimEnd("\")
if (-not $Force -and $markedSource -ne $sourceFull) {
  throw "The installed copy belongs to '$markedSource', not '$sourceFull'. Pass -Force only after verifying the target."
}

$settingsPath = Join-Path $targetRoot "settings.json"
$settingsHashBefore = if (Test-Path -LiteralPath $settingsPath) {
  (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
} else {
  ""
}

$runtimeRoots = Get-CodexPetRuntimeRoots -ScriptProjectRoot $sourceRoot -InstallDir $targetRoot
$runtimeProcesses = @(Get-CodexPetRuntimeProcesses -ProjectRoots $runtimeRoots)
$wasRunning = $runtimeProcesses.Count -gt 0

$settingsScriptPath = Join-Path $targetRoot "bin\powershell\Settings.ps1"
$settingsServers = @(Get-CimInstance Win32_Process | Where-Object {
  $_.ProcessId -ne $PID -and
  $_.Name -match '^(powershell|pwsh)(\.exe)?$' -and
  (Test-CodexPetPathInCommandLine -CommandLine $_.CommandLine -Path $settingsScriptPath)
})
foreach ($process in $settingsServers) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  Write-Output "Stopped installed settings server PID $($process.ProcessId)."
}

if ($wasRunning) {
  & (Join-Path $sourceRoot "bin\powershell\Stop.ps1") -InstallDir $targetRoot -Quiet
}

$installParams = @{
  InstallDir = $targetRoot
  NoStartup = $true
  NoStartMenu = $true
  NoStart = $true
  NoStartCodex = $true
}
if ($Force) { $installParams.Force = $true }
& (Join-Path $sourceRoot "bin\powershell\Install.ps1") @installParams

$settingsHashAfter = if (Test-Path -LiteralPath $settingsPath) {
  (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
} else {
  ""
}
if ($settingsHashBefore -ne $settingsHashAfter) {
  throw "Installed settings.json changed during sync."
}

$sourceVersion = (Get-Content -Raw -LiteralPath (Join-Path $sourceRoot "VERSION")).Trim()
$installedVersion = (Get-Content -Raw -LiteralPath (Join-Path $targetRoot "VERSION")).Trim()
if ($installedVersion -ne $sourceVersion) {
  throw "Installed version mismatch: source=$sourceVersion installed=$installedVersion"
}

$verificationFiles = @(
  "src\CodexPetLimitRings.ps1",
  "settings\index.html",
  "assets\runtime\potion-pixel-frame.png",
  "assets\runtime\potion-pixel-mask.png",
  "assets\runtime\heart-potion-pixel-frame.png",
  "assets\runtime\heart-potion-pixel-mask.png",
  "assets\runtime\tray-cat-icon.ico"
)
foreach ($relativePath in $verificationFiles) {
  $sourcePath = Join-Path $sourceRoot $relativePath
  if (-not (Test-Path -LiteralPath $sourcePath)) { continue }
  $installedPath = Join-Path $targetRoot $relativePath
  if (-not (Test-Path -LiteralPath $installedPath)) {
    throw "Installed copy is missing: $relativePath"
  }
  $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
  $installedHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
  if ($sourceHash -ne $installedHash) {
    throw "Installed file hash mismatch: $relativePath"
  }
}

if ($wasRunning -or $StartIfStopped) {
  & (Join-Path $targetRoot "bin\powershell\Start.ps1") -NoStartCodex
}

$status = & (Join-Path $targetRoot "bin\powershell\Status.ps1")
$status | Out-Host
Write-Output "Installed copy synchronized to version $installedVersion."
Write-Output "Settings preserved: $settingsPath"
if ($settingsServers.Count -gt 0) {
  Write-Output "The previous settings server was closed; reopen Settings.bat when needed."
}
