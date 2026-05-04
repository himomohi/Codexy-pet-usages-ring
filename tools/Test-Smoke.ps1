param(
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-pet-limit-rings-smoke-" + [Guid]::NewGuid().ToString("N"))
$releaseOut = Join-Path $tempRoot "release"
$installRoot = Join-Path $tempRoot "install"
$fixtures = @()

function Add-Fixture {
  param([string]$RelativePath, [string]$Content = "smoke")
  $path = Join-Path $root ($RelativePath -replace '/', '\')
  if (Test-Path -LiteralPath $path) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
  $script:fixtures += $path
}

function Test-ForbiddenPath {
  param([string]$Path)
  $normalized = $Path -replace '\\', '/'
  $leaf = Split-Path -Leaf $normalized
  if ($normalized -in @(
    ".gitignore",
    "settings.json",
    "docs/assets/current-pet-usage-capture.png",
    "docs/assets/imagegen-hero-background.png"
  )) { return $true }
  if ($normalized -like "dist/*" -or $normalized -eq "dist") { return $true }
  if ($normalized -like "logs/*" -or $normalized -eq "logs") { return $true }
  if ($normalized -like "qa/*" -or $normalized -eq "qa") { return $true }
  if ($normalized -like "*.log" -or $normalized -like "*.tmp" -or $normalized -like "*.bak" -or $normalized -like "*.zip") { return $true }
  if ($leaf -eq ".DS_Store" -or $leaf -eq "Thumbs.db") { return $true }
  return $false
}

function Assert-NoForbiddenPaths {
  param([string[]]$Paths, [string]$Scope)
  $bad = @($Paths | Where-Object { Test-ForbiddenPath -Path $_ })
  if ($bad.Count -gt 0) {
    throw "$Scope contains forbidden paths: $($bad -join ', ')"
  }
}

try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

  Add-Fixture -RelativePath "logs/smoke.log"
  Add-Fixture -RelativePath "qa/smoke.tmp"
  Add-Fixture -RelativePath ".gitignore"
  Add-Fixture -RelativePath "settings.json" -Content "{`"theme`":`"smoke`"}"
  Add-Fixture -RelativePath "docs/assets/current-pet-usage-capture.png"
  Add-Fixture -RelativePath "docs/assets/imagegen-hero-background.png"
  Add-Fixture -RelativePath "smoke.tmp"

  $parseErrorsText = @()
  Get-ChildItem -LiteralPath $root -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch '\\.git\\' } | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors) {
      $parseErrorsText += $parseErrors | ForEach-Object { "$($_.Extent.File):$($_.Extent.StartLineNumber):$($_.Message)" }
    }
  }
  if ($parseErrorsText.Count -gt 0) { throw "PowerShell parser check failed: $($parseErrorsText -join '; ')" }

  $trackedFiles = @(git -C $root ls-files)
  Assert-NoForbiddenPaths -Paths $trackedFiles -Scope "Git tracked files"

  & (Join-Path $root "tools\New-ReleaseZip.ps1") -OutputDirectory $releaseOut | Out-Host
  $zip = Get-ChildItem -LiteralPath $releaseOut -Filter "*.zip" | Select-Object -First 1
  if (-not $zip) { throw "Release zip was not created." }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
  try {
    $zipEntries = @($archive.Entries | ForEach-Object { $_.FullName.TrimEnd("/") })
  } finally {
    $archive.Dispose()
  }
  Assert-NoForbiddenPaths -Paths $zipEntries -Scope "Release zip"

  & (Join-Path $root "bin\powershell\Install.ps1") -InstallDir $installRoot -NoStartup -NoStartMenu -NoStart | Out-Host
  $installedFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Force | ForEach-Object {
    $_.FullName.Substring($installRoot.TrimEnd("\").Length + 1) -replace '\\', '/'
  })
  Assert-NoForbiddenPaths -Paths $installedFiles -Scope "Temp install"
  & (Join-Path $root "bin\powershell\Uninstall.ps1") -InstallDir $installRoot -RemoveFiles | Out-Host

  Write-Output "Smoke checks passed."
} finally {
  foreach ($fixture in $fixtures) {
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
  }
  if (-not $KeepArtifacts) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Output "Kept smoke artifacts: $tempRoot"
  }
}
