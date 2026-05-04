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
$staging = Join-Path $env:TEMP $name
$zipPath = Join-Path $OutputDirectory "$name.zip"

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

foreach ($item in @("Install.bat", "Start.bat", "Stop.bat", "Status.bat", "Settings.bat", "Uninstall.bat", "bin", "src", "docs", "tools", "settings", "settings.defaults.json", "README.md", "README.ko.md", "LICENSE", "NOTICE.md", "CHANGELOG.md", "SECURITY.md", "VERSION", ".gitignore")) {
  $source = Join-Path $root $item
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $staging $item) -Recurse -Force
  }
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Output "Release zip: $zipPath"
