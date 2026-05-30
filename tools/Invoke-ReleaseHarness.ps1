param(
  [string]$Version = "",
  [string]$DeployDirectory = "",
  [string]$GitHubRepo = "himomohi/Codexy-pet-usages-ring",
  [string]$Remote = "codexy",
  [string]$Branch = "main",
  [switch]$SkipSmoke,
  [switch]$SkipInstallRefresh,
  [switch]$PublishGitHub,
  [switch]$Draft,
  [switch]$Prerelease,
  [switch]$ClobberAsset,
  [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot "ReleaseManifest.ps1")

if ([string]::IsNullOrWhiteSpace($DeployDirectory)) {
  $DeployDirectory = Join-Path $root "배포용"
}

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Get-ReleaseVersion {
  $versionFile = Join-Path $root "VERSION"
  if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "VERSION file is missing."
  }
  return (Get-Content -Raw -LiteralPath $versionFile).Trim()
}

function Assert-Semver {
  param([string]$Value)
  if ($Value -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must use MAJOR.MINOR.PATCH format. Found: $Value"
  }
}

function Set-ReleaseVersionMetadata {
  param([string]$TargetVersion)

  $currentVersion = Get-ReleaseVersion
  if ($TargetVersion -eq $currentVersion) { return }

  Write-Step "Updating VERSION and README badges to $TargetVersion"
  Set-Content -LiteralPath (Join-Path $root "VERSION") -Value $TargetVersion -Encoding ASCII

  foreach ($readmeName in @("README.md", "README.ko.md", "README.ja.md", "README.zh.md")) {
    $path = Join-Path $root $readmeName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $content = Get-Content -Raw -LiteralPath $path
    $content = $content -replace 'Download_latest_release-v\d+\.\d+\.\d+-', "Download_latest_release-v$TargetVersion-"
    $content = $content -replace 'CHANGELOG\.md#\d+', ("CHANGELOG.md#" + ($TargetVersion -replace '\.', ''))
    $content = $content -replace 'Version \d+\.\d+\.\d+', "Version $TargetVersion"
    $content = $content -replace 'version-\d+\.\d+\.\d+-', "version-$TargetVersion-"
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
  }
}

function Assert-ReleaseMetadata {
  param([string]$ExpectedVersion)

  Write-Step "Checking release metadata"
  Assert-Semver -Value $ExpectedVersion

  $actualVersion = Get-ReleaseVersion
  if ($actualVersion -ne $ExpectedVersion) {
    throw "VERSION is $actualVersion, expected $ExpectedVersion."
  }

  $changelog = Get-Content -LiteralPath (Join-Path $root "CHANGELOG.md")
  $top = $changelog | Where-Object { $_ -match '^##\s+(\d+\.\d+\.\d+)\s*$' } | Select-Object -First 1
  if (-not $top -or $top -notmatch "^##\s+$([regex]::Escape($ExpectedVersion))\s*$") {
    throw "Top CHANGELOG.md entry must be ## $ExpectedVersion before release."
  }

  foreach ($readmeName in @("README.md", "README.ko.md", "README.ja.md", "README.zh.md")) {
    $readme = Get-Content -Raw -LiteralPath (Join-Path $root $readmeName)
    $anchor = "CHANGELOG.md#" + ($ExpectedVersion -replace '\.', '')
    if ($readme -notmatch [regex]::Escape("Download_latest_release-v$ExpectedVersion-")) {
      throw "$readmeName download badge must point at v$ExpectedVersion."
    }
    if ($readme -notmatch [regex]::Escape($anchor)) {
      throw "$readmeName changelog badge anchor must point at $anchor."
    }
    if ($readme -notmatch [regex]::Escape("version-$ExpectedVersion-")) {
      throw "$readmeName version badge must match $ExpectedVersion."
    }
  }
}

function Assert-WorktreeReady {
  if ($AllowDirty) { return }
  $status = @(git -C $root status --porcelain)
  if ($status.Count -gt 0) {
    throw "Working tree has uncommitted changes. Commit them first or rerun with -AllowDirty."
  }
}

function Clear-DeployDirectory {
  param([string]$Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
  $resolvedDeploy = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolvedDeploy.StartsWith($resolvedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean deployment directory outside workspace: $resolvedDeploy"
  }
  if (Test-Path -LiteralPath $resolvedDeploy) {
    Remove-Item -LiteralPath $resolvedDeploy -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $resolvedDeploy | Out-Null
  return $resolvedDeploy
}

function New-VerifiedDeployZip {
  param([string]$TargetVersion, [string]$OutputDirectory)

  Write-Step "Creating deployment zip"
  $resolvedDeploy = Clear-DeployDirectory -Path $OutputDirectory
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "New-ReleaseZip.ps1") -OutputDirectory $resolvedDeploy

  $zipPath = Join-Path $resolvedDeploy "Codexy-pet-usages-ring-$TargetVersion.zip"
  if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Release zip was not created: $zipPath"
  }

  $extractPath = Join-Path $resolvedDeploy "Codexy-pet-usages-ring-$TargetVersion"
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

  Write-Step "Verifying deployment zip contents"
  $missing = @()
  $mismatch = @()
  foreach ($relative in $script:CodexPetRequiredFreshFiles) {
    $source = Join-Path $root ($relative -replace '/', '\')
    $deployed = Join-Path $extractPath ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $deployed -PathType Leaf)) {
      $missing += $relative
      continue
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $deployedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $deployed).Hash
    if ($sourceHash -ne $deployedHash) {
      $mismatch += $relative
    }
  }

  $forbidden = @(
    "gamification.json",
    "settings.json",
    "assets/runtime/inventory-items-source.png",
    "assets/runtime/cosmetic-unlocks-source.png",
    "assets/runtime/theme-forest-border-source.png",
    "assets/runtime/theme-arcane-border-source.png",
    "assets/runtime/theme-royal-border-source.png",
    "assets/runtime/theme-cyber-border-source.png",
    "assets/runtime/theme-celestial-border-source.png"
  ) | Where-Object { Test-Path -LiteralPath (Join-Path $extractPath ($_ -replace '/', '\')) }

  if ($missing.Count -gt 0 -or $mismatch.Count -gt 0 -or $forbidden.Count -gt 0) {
    throw "Deployment verification failed. Missing=$($missing -join ',') Mismatch=$($mismatch -join ',') Forbidden=$($forbidden -join ',')"
  }

  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
  return [PSCustomObject]@{
    ZipPath = $zipPath
    ExtractPath = $extractPath
    Sha256 = $hash
    FileCount = (Get-ChildItem -LiteralPath $extractPath -Recurse -File | Measure-Object).Count
  }
}

function Invoke-Smoke {
  if ($SkipSmoke) { return }
  Write-Step "Running smoke checks"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-Smoke.ps1")
}

function Invoke-InstallRefresh {
  param([string]$ExpectedVersion)
  if ($SkipInstallRefresh) { return }

  Write-Step "Refreshing installed helper"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bin\powershell\Install.ps1") -NoStartCodex

  $installedRoot = Join-Path $env:LOCALAPPDATA "CodexyPetUsagesRing"
  $installedVersion = (Get-Content -Raw -LiteralPath (Join-Path $installedRoot "VERSION")).Trim()
  if ($installedVersion -ne $ExpectedVersion) {
    throw "Installed VERSION is $installedVersion, expected $ExpectedVersion."
  }

  $sourceSettings = Join-Path $root "settings\index.html"
  $installedSettings = Join-Path $installedRoot "settings\index.html"
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourceSettings).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $installedSettings).Hash) {
    throw "Installed settings/index.html does not match source."
  }
}

function Get-ReleaseNotes {
  param([string]$TargetVersion, [string]$Sha256)
  $text = Get-Content -Raw -LiteralPath (Join-Path $root "CHANGELOG.md")
  $pattern = "(?ms)^##\s+$([regex]::Escape($TargetVersion))\s*(.*?)(?=^##\s+\d+\.\d+\.\d+\s*$|\z)"
  $match = [regex]::Match($text, $pattern)
  if (-not $match.Success) {
    throw "Could not extract CHANGELOG.md notes for $TargetVersion."
  }
  $body = $match.Groups[1].Value.Trim()
  return "## $TargetVersion`r`n`r`n$body`r`n`r`nSHA256: ``$Sha256``"
}

function Publish-GitHubRelease {
  param([string]$TargetVersion, [string]$ZipPath, [string]$Sha256)

  Write-Step "Publishing GitHub release"
  $tag = "v$TargetVersion"
  $currentBranch = (git -C $root branch --show-current).Trim()
  if ($currentBranch -ne $Branch) {
    throw "Current branch is $currentBranch, expected $Branch."
  }

  git -C $root push $Remote $Branch
  if (-not (git -C $root tag --list $tag)) {
    git -C $root tag $tag
  }
  git -C $root push $Remote $tag

  $notesPath = Join-Path ([System.IO.Path]::GetTempPath()) "codexy-release-$tag.md"
  Set-Content -LiteralPath $notesPath -Value (Get-ReleaseNotes -TargetVersion $TargetVersion -Sha256 $Sha256) -Encoding UTF8

  $existing = $null
  try {
    $existing = gh release view $tag --repo $GitHubRepo --json tagName 2>$null
  } catch {
    $existing = $null
  }

  if ($existing) {
    gh release edit $tag --repo $GitHubRepo --title "Codexy pet usages ring $tag" --notes-file $notesPath
    $uploadArgs = @("release", "upload", $tag, $ZipPath, "--repo", $GitHubRepo)
    if ($ClobberAsset) { $uploadArgs += "--clobber" }
    gh @uploadArgs
  } else {
    $createArgs = @("release", "create", $tag, $ZipPath, "--repo", $GitHubRepo, "--title", "Codexy pet usages ring $tag", "--notes-file", $notesPath)
    if ($Draft) { $createArgs += "--draft" }
    if ($Prerelease) { $createArgs += "--prerelease" }
    gh @createArgs
  }

  gh api "repos/$GitHubRepo/releases/tags/$tag" --jq '{html_url,tag_name,target_commitish,assets:[.assets[]|{name,size,browser_download_url}]}'
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Get-ReleaseVersion
}
Assert-Semver -Value $Version
Set-ReleaseVersionMetadata -TargetVersion $Version
Assert-ReleaseMetadata -ExpectedVersion $Version
Assert-WorktreeReady
Invoke-Smoke
$deploy = New-VerifiedDeployZip -TargetVersion $Version -OutputDirectory $DeployDirectory
Invoke-InstallRefresh -ExpectedVersion $Version

if ($PublishGitHub) {
  Publish-GitHubRelease -TargetVersion $Version -ZipPath $deploy.ZipPath -Sha256 $deploy.Sha256
}

Write-Step "Release harness completed"
[PSCustomObject]@{
  Version = $Version
  ZipPath = $deploy.ZipPath
  Sha256 = $deploy.Sha256
  ExtractPath = $deploy.ExtractPath
  ExtractedFileCount = $deploy.FileCount
  Published = [bool]$PublishGitHub
} | Format-List
