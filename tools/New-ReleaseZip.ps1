param(
  [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist")
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$versionFile = Join-Path $root "VERSION"
$version = if (Test-Path -LiteralPath $versionFile) {
  (Get-Content -Raw -LiteralPath $versionFile).Trim()
} else {
  "0.1.0"
}
$name = "codex-pet-limit-rings-Win-$version"
$staging = Join-Path $env:TEMP "$name-$([Guid]::NewGuid().ToString('N'))"
$zipPath = Join-Path $OutputDirectory "$name.zip"

function Get-ProjectRelativePath {
  param([string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootWithSeparator = $root.TrimEnd("\") + "\"
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
    ".codex-pet-language-cache.json",
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

function Copy-ReleaseItem {
  param([string]$Name)
  $source = Join-Path $root $Name
  if (-not (Test-Path -LiteralPath $source)) { return }
  if (Test-ProjectPathExcluded -Path $source) { return }
  if ((Get-Item -LiteralPath $source).PSIsContainer) {
    Get-ChildItem -LiteralPath $source -Recurse -File -Force |
      Where-Object { -not (Test-ProjectPathExcluded -Path $_.FullName) } |
      ForEach-Object {
        $relativePath = Get-ProjectRelativePath -Path $_.FullName
        $destination = Join-Path $staging ($relativePath -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
      }
  } else {
    Copy-Item -LiteralPath $source -Destination (Join-Path $staging $Name) -Force
  }
}

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

foreach ($item in @("Manage.bat", "Install.bat", "Install-AutoStart.bat", "Apply-Installed.bat", "Start.bat", "Stop.bat", "Status.bat", "Settings.bat", "Diagnose.bat", "Uninstall.bat", "assets", "bin", "src", "docs", "tools", "settings", "settings.defaults.json", "README.md", "README.ko.md", "LICENSE", "NOTICE.md", "CHANGELOG.md", "SECURITY.md", "VERSION")) {
  Copy-ReleaseItem -Name $item
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Output "Release zip: $zipPath"
