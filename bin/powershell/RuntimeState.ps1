$script:CodexPetProductName = "codex-pet-limit-rings-Win"
$script:CodexPetInstallMarkerName = ".codex-pet-limit-rings-win.install.json"
$script:CodexPetPidFileName = ".codex-pet-limit-rings.pid"

function Get-CodexPetDefaultInstallDir {
  $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
  if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
  if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LOCALAPPDATA was not found." }
  return (Join-Path $localAppData "CodexPetLimitRingsWin")
}

function Get-CodexPetRuntimePaths {
  param([string]$ProjectRoot)
  $root = [System.IO.Path]::GetFullPath($ProjectRoot)
  $src = Join-Path $root "src"
  return [PSCustomObject]@{
    ProjectRoot = $root
    AppScript = Join-Path $src "CodexPetLimitRings.ps1"
    LegacyScript = Join-Path $src "codex-pet-limit-rings-windows.ps1"
    PidFile = Join-Path $root $script:CodexPetPidFileName
    InstallMarker = Join-Path $root $script:CodexPetInstallMarkerName
  }
}

function Get-CodexPetRuntimeRoots {
  param(
    [string]$ScriptProjectRoot,
    [string]$InstallDir = ""
  )
  $roots = @()
  if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    $roots += $InstallDir
  } else {
    $roots += $ScriptProjectRoot
    try { $roots += (Get-CodexPetDefaultInstallDir) } catch {}
  }

  $seen = @{}
  $result = @()
  foreach ($root in $roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $full = [System.IO.Path]::GetFullPath($root).TrimEnd("\")
    $key = $full.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $result += $full
  }
  return $result
}

function Test-CodexPetPathInCommandLine {
  param(
    [string]$CommandLine,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($CommandLine) -or [string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }
  $fullPath = [System.IO.Path]::GetFullPath($Path) -replace '/', '\'
  $normalizedCommandLine = $CommandLine -replace '/', '\'
  return ($normalizedCommandLine -match [Regex]::Escape($fullPath))
}

function Test-CodexPetRuntimeCommandLine {
  param(
    [string]$CommandLine,
    $RuntimePaths
  )
  return (
    (Test-CodexPetPathInCommandLine -CommandLine $CommandLine -Path $RuntimePaths.AppScript) -or
    (Test-CodexPetPathInCommandLine -CommandLine $CommandLine -Path $RuntimePaths.LegacyScript)
  )
}

function Get-CodexPetRuntimeProcesses {
  param([string[]]$ProjectRoots)

  $allProcesses = @(Get-CimInstance Win32_Process)
  $matches = @{}

  foreach ($root in $ProjectRoots) {
    $paths = Get-CodexPetRuntimePaths -ProjectRoot $root
    $pidCandidates = @()
    if (Test-Path -LiteralPath $paths.PidFile) {
      try {
        $pidCandidates = @(Get-Content -LiteralPath $paths.PidFile -ErrorAction Stop | ForEach-Object {
          $candidate = 0
          if ([int]::TryParse(([string]$_).Trim(), [ref]$candidate)) { $candidate }
        })
      } catch {
        $pidCandidates = @()
      }
    }

    foreach ($process in $allProcesses) {
      if ($process.ProcessId -eq $PID) { continue }
      $fromPidFile = $pidCandidates -contains ([int]$process.ProcessId)
      $fromCommandLine = Test-CodexPetRuntimeCommandLine -CommandLine $process.CommandLine -RuntimePaths $paths
      if (-not ($fromPidFile -or $fromCommandLine)) { continue }
      if (-not (Test-CodexPetRuntimeCommandLine -CommandLine $process.CommandLine -RuntimePaths $paths)) { continue }
      if ($matches.ContainsKey([int]$process.ProcessId)) { continue }
      $matches[[int]$process.ProcessId] = [PSCustomObject]@{
        ProcessId = [int]$process.ProcessId
        CommandLine = $process.CommandLine
        ProjectRoot = $paths.ProjectRoot
        PidFile = $paths.PidFile
      }
    }
  }

  return @($matches.Values | Sort-Object ProcessId)
}

function Set-CodexPetPidFile {
  param(
    [string]$ProjectRoot,
    [int]$ProcessId
  )
  $paths = Get-CodexPetRuntimePaths -ProjectRoot $ProjectRoot
  [System.IO.File]::WriteAllText($paths.PidFile, ([string]$ProcessId + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
}

function Clear-CodexPetPidFile {
  param([string]$ProjectRoot)
  $paths = Get-CodexPetRuntimePaths -ProjectRoot $ProjectRoot
  if (Test-Path -LiteralPath $paths.PidFile) {
    Remove-Item -LiteralPath $paths.PidFile -Force -ErrorAction SilentlyContinue
  }
}

function Write-CodexPetInstallMarker {
  param(
    [string]$ProjectRoot,
    [string]$SourceRoot,
    [string]$Version = ""
  )
  $paths = Get-CodexPetRuntimePaths -ProjectRoot $ProjectRoot
  $marker = [ordered]@{
    name = $script:CodexPetProductName
    markerVersion = 1
    version = $Version
    installedAt = [DateTimeOffset]::UtcNow.ToString("o")
    installDir = $paths.ProjectRoot
    sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
  }
  [System.IO.File]::WriteAllText(
    $paths.InstallMarker,
    (($marker | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
    [System.Text.Encoding]::UTF8
  )
}

function Get-CodexPetInstallMarker {
  param([string]$ProjectRoot)
  $paths = Get-CodexPetRuntimePaths -ProjectRoot $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.InstallMarker)) { return $null }
  try {
    $marker = [System.IO.File]::ReadAllText($paths.InstallMarker, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    return $null
  }
  if ($marker.name -ne $script:CodexPetProductName) { return $null }
  if ([int]$marker.markerVersion -lt 1) { return $null }
  return $marker
}

function Test-CodexPetInstallMarker {
  param([string]$ProjectRoot)
  return ($null -ne (Get-CodexPetInstallMarker -ProjectRoot $ProjectRoot))
}
