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

function Assert-DeployInitialRewardState {
  param([string]$ExtractPath)

  Write-Step "Verifying deployment starts with locked rewards"
  Write-Host "Release invariant: deployed reward unlock state must always start locked/reset."
  $stateFileNames = @("gamification.json", "settings.json")
  $stateFiles = @(Get-ChildItem -LiteralPath $ExtractPath -Recurse -File -Force | Where-Object {
    $_.Name -in $stateFileNames
  } | ForEach-Object {
    $_.FullName.Substring($ExtractPath.TrimEnd("\").Length + 1) -replace '\\', '/'
  })
  if ($stateFiles.Count -gt 0) {
    throw "Deployment must not include local reward/settings state files: $($stateFiles -join ', ')"
  }

  $defaultsPath = Join-Path $ExtractPath "settings.defaults.json"
  if (-not (Test-Path -LiteralPath $defaultsPath -PathType Leaf)) {
    throw "Deployment is missing settings.defaults.json."
  }

  $defaults = Get-Content -Raw -LiteralPath $defaultsPath | ConvertFrom-Json
  if ($null -ne $defaults.inventory) {
    throw "settings.defaults.json must not include reward inventory unlock state."
  }
  if ($null -eq $defaults.gamification) {
    throw "settings.defaults.json must include gamification defaults."
  }
  if ([bool]$defaults.gamification.enabled) {
    throw "Deploy defaults must keep gamification disabled until the user enables it."
  }

  $unlockKeys = @(
    "fontPixel",
    "fontTerminal",
    "themeForest",
    "themeArcane",
    "themeRoyal",
    "themeCyber",
    "themeCelestial",
    "effectPawBurst",
    "effectBearPaw",
    "effectDogPaw",
    "activeFont",
    "activeTheme",
    "activeEffect",
    "rewardRolls",
    "totalDrops",
    "totalKeys",
    "lastDropItem"
  )
  foreach ($key in $unlockKeys) {
    if ($null -ne $defaults.PSObject.Properties[$key]) {
      throw "Deploy defaults must not include local reward unlock key '$key'."
    }
    if ($null -ne $defaults.gamification.PSObject.Properties[$key]) {
      throw "Deploy gamification defaults must not include local reward unlock key '$key'."
    }
  }
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
  Assert-DeployInitialRewardState -ExtractPath $extractPath

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
  $body = Get-ChangelogBody -TargetVersion $TargetVersion
  return "## $TargetVersion`r`n`r`n$body`r`n`r`nSHA256: ``$Sha256``"
}

function Get-ChangelogBody {
  param([string]$TargetVersion)

  $text = Get-Content -Raw -LiteralPath (Join-Path $root "CHANGELOG.md")
  $pattern = "(?ms)^##\s+$([regex]::Escape($TargetVersion))\s*(.*?)(?=^##\s+\d+\.\d+\.\d+\s*$|\z)"
  $match = [regex]::Match($text, $pattern)
  if (-not $match.Success) {
    throw "Could not extract CHANGELOG.md notes for $TargetVersion."
  }
  return $match.Groups[1].Value.Trim()
}

function Convert-ChangelogHeadingKo {
  param([string]$Heading)

  switch ($Heading) {
    "Added" { return "추가" }
    "Changed" { return "변경" }
    "Fixed" { return "수정" }
    "Removed" { return "제거" }
    "Security" { return "보안" }
    default { return $Heading }
  }
}

function Convert-ChangelogHeadingEmoji {
  param([string]$Heading)

  switch ($Heading) {
    "Added" { return "✨" }
    "Changed" { return "🔧" }
    "Fixed" { return "✅" }
    "Removed" { return "🧹" }
    "Security" { return "🛡️" }
    default { return "•" }
  }
}

function Convert-ChangelogBulletKo {
  param([string]$Bullet)

  $normalizedBullet = $Bullet -replace '`', ''
  switch ($normalizedBullet) {
    "Added a root Diagnose.bat launcher so double-click users can run diagnostics without opening PowerShell manually." {
      return "PowerShell을 직접 열지 않아도 더블클릭으로 진단을 실행할 수 있도록 루트에 `Diagnose.bat` 런처를 추가했습니다."
    }
    "Made Settings.bat explain why its helper window stays open while the local settings page is active." {
      return "로컬 설정 페이지가 열려 있는 동안 helper 창이 유지되는 이유를 `Settings.bat`에서 안내하도록 개선했습니다."
    }
    "Made Uninstall.bat ask whether to remove installed files when double-clicked, while keeping installed files by default for safety." {
      return "`Uninstall.bat`을 더블클릭하면 설치 파일까지 제거할지 묻고, 안전을 위해 기본값은 파일 보존으로 유지했습니다."
    }
  }

  switch ($Bullet) {
    "Added a root `Diagnose.bat` launcher so double-click users can run diagnostics without opening PowerShell manually." {
      return "PowerShell을 직접 열지 않아도 더블클릭으로 진단을 실행할 수 있도록 루트에 `Diagnose.bat` 런처를 추가했습니다."
    }
    "Served runtime reward assets from the local settings server so the settings inventory can show the actual unlock/effect images." {
      return "설정 보관함에서 실제 해금/이펙트 이미지를 볼 수 있도록 로컬 설정 서버가 런타임 보상 에셋을 제공하게 했습니다."
    }
    "Made `Settings.bat` explain why its helper window stays open while the local settings page is active." {
      return "로컬 설정 페이지가 열려 있는 동안 helper 창이 유지되는 이유를 `Settings.bat`에서 안내하도록 개선했습니다."
    }
    "Made `Uninstall.bat` ask whether to remove installed files when double-clicked, while keeping installed files by default for safety." {
      return "`Uninstall.bat`을 더블클릭하면 설치 파일까지 제거할지 묻고, 안전을 위해 기본값은 파일 보존으로 유지했습니다."
    }
    "Made the release harness explicitly fail deployment when reward unlock state keys appear in defaults, and remind final replies to confirm locked/reset deployment state." {
      return "기본 설정에 보상 해금 상태 키가 포함되면 릴리즈 하네스가 실패하도록 하고, 최종 응답에서도 잠김/초기화 배포 상태를 확인하도록 기록했습니다."
    }
    "Fixed the settings reward summary API so unlocked paw effects and the active effect appear correctly in the settings inventory." {
      return "해금된 발바닥 이펙트와 현재 적용 중인 이펙트가 설정 보관함에 올바르게 표시되도록 보상 요약 API를 수정했습니다."
    }
    "Replaced cat, dog, and bear paw reward effect sprites with cleaner animal-specific paws and no surrounding particle clutter." {
      return "고양이, 강아지, 곰 발바닥 보상 이펙트 스프라이트를 더 깔끔하고 동물별 특징이 보이는 이미지로 교체했습니다."
    }
    "Changed the keyboard counter hook to count only the first key-down event for each held key, preventing OS key-repeat from inflating counts." {
      return "키를 누르고 있을 때 OS 반복 입력이 카운트를 부풀리지 않도록, 각 키의 첫 key-down 이벤트만 카운트하게 개선했습니다."
    }
    "Added key-up state tracking and hook reset cleanup so held keys cannot remain stuck as already counted after visibility or hook changes." {
      return "key-up 상태 추적과 훅 리셋 정리를 추가해 표시 상태나 훅 변경 뒤에도 키가 이미 카운트된 상태로 고정되지 않게 했습니다."
    }
    "Updated smoke checks to guard the no-repeat keyboard counter behavior and the refreshed reward effect assets." {
      return "반복 카운트 방지 동작과 갱신된 보상 이펙트 에셋을 smoke checks에서 검증하도록 업데이트했습니다."
    }
    "Added release announcement output to the release harness with separate Korean and English text blocks generated from the current changelog entry." {
      return "릴리즈 하네스 마지막에 현재 CHANGELOG 항목을 기반으로 한국어와 영어 안내문 코드블록을 각각 출력하도록 추가했습니다."
    }
    "Added deployment validation that fails the release if local reward or settings state files are included in the deploy package." {
      return "배포 패키지에 로컬 보상 상태나 설정 상태 파일이 포함되면 릴리즈가 실패하도록 배포 검증을 추가했습니다."
    }
    "Repositioned the reward bag and reward picker popovers below their HUD anchors so they avoid covering the pet, counter, and other HUD elements." {
      return "보상 보관함과 보상 선택 팝오버를 HUD 앵커 아래쪽에 배치해 펫, 카운터, 다른 HUD 요소를 가리지 않도록 개선했습니다."
    }
    "Kept deployment defaults locked by verifying release packages do not include inventory unlock state and keep gamification disabled by default." {
      return "릴리즈 패키지에 인벤토리 해금 상태가 없고 기본 gamification 값이 꺼져 있는지 확인해 배포 기본 상태를 잠금 상태로 유지합니다."
    }
    "Fixed stale fully unlocked local test state from leaking into the deployment folder or release zip." {
      return "테스트 중 전체해금된 로컬 상태가 배포용 폴더나 릴리즈 zip으로 새어 나가지 않도록 수정했습니다."
    }
    "Fixed reward bag popover placement so it no longer opens to the side over nearby HUD controls." {
      return "보상 보관함 팝오버가 옆으로 열려 근처 HUD 컨트롤 위를 덮는 배치 문제를 수정했습니다."
    }
    "Reduced perceived keyboard counter latency by updating the visible count before reward drops and burst effects run." {
      return "보상 드랍과 버스트 이펙트가 실행되기 전에 보이는 카운트 숫자를 먼저 갱신해 키보드 카운터 체감 지연을 줄였습니다."
    }
    "Deferred reward drop processing and typing burst effects to background dispatcher priority so typing feedback can render first." {
      return "타이핑 피드백이 먼저 렌더링되도록 보상 드랍 처리와 타이핑 버스트 이펙트를 백그라운드 dispatcher 우선순위로 미뤘습니다."
    }
    "Reduced live usage polling pressure by polling less often, shortening the live usage timeout, and skipping usage refresh while typing is active." {
      return "사용량 조회 간격을 늘리고 live usage timeout을 줄였으며, 타이핑 중에는 사용량 refresh를 건너뛰도록 해 polling 부담을 낮췄습니다."
    }
    "Capped batched paw and text burst effects so delayed input batches cannot flood the UI thread." {
      return "지연된 입력 배치가 UI 스레드를 폭주시킬 수 없도록 발바닥과 텍스트 버스트 이펙트 생성량에 상한을 걸었습니다."
    }
    "Fixed slow keyboard counter feedback when live usage lookups timed out or returned 503 errors on the WPF UI thread." {
      return "WPF UI 스레드에서 live usage 조회가 timeout 또는 503 오류로 지연될 때 키보드 카운터 반응이 느려지던 문제를 수정했습니다."
    }
    "Fixed batched typing effects from delaying the next visible key count update." {
      return "배치로 몰린 타이핑 이펙트가 다음 키 카운트 표시 갱신을 늦추던 문제를 수정했습니다."
    }
    "Added low-cost combo heat and reward charge meters to the gamification HUD, with settings toggles for each." {
      return "게이미피케이션 HUD에 저비용 콤보 열기 게이지와 보상 충전 게이지를 추가하고, 설정에서 각각 토글할 수 있게 했습니다."
    }
    "Added a 1000-key reward chest claim button in the reward popover, with a 10-minute cooldown after each claim." {
      return "보상 팝오버에 1000키 충전 상자 열기 버튼을 추가하고, 상자를 연 뒤에는 10분 쿨다운이 걸리도록 했습니다."
    }
    "Added a generated ready-state chest icon that appears on the HUD when a reward chest can be opened." {
      return "보상 상자를 열 수 있을 때 HUD에 표시되는 생성형 ready 상자 아이콘을 추가했습니다."
    }
    "Added an interactive settings sidebar with section-aware navigation for General, Growth, Rewards, Presets, Colors, Readout, Opacity, and Motion." {
      return "일반, 성장, 보상, 프리셋, 색상, 읽기 표시, 투명도, 모션 섹션을 빠르게 이동할 수 있는 인터랙티브 설정 사이드바를 추가했습니다."
    }
    "Kept the new meters event-driven and fixed-size so typing feedback stays responsive without adding new polling timers." {
      return "새 게이지를 이벤트 기반과 고정 크기 구조로 유지해 추가 polling 타이머 없이 타이핑 피드백 반응성을 지켰습니다."
    }
    "Changed reward drops to roll only when the user opens a charged chest, deducting 1000 stored key points instead of resetting the counter." {
      return "보상 드랍은 충전된 상자를 열 때만 굴러가도록 바꾸고, 카운터를 0으로 초기화하지 않고 저장된 키 포인트에서 1000만 차감하게 했습니다."
    }
    "Wrapped reward popover status/button text so Korean and long charge values do not get clipped." {
      return "한국어 문구와 긴 충전값이 잘리지 않도록 보상 팝오버 상태/버튼 텍스트를 줄바꿈 처리했습니다."
    }
    "Reworked the settings page from a pixel hero layout into a compact settings app with a left navigation rail, single-column control flow, and sticky HUD preview." {
      return "설정 페이지를 픽셀 hero 레이아웃에서 좌측 네비게이션, 단일 흐름 컨트롤, 고정 HUD 미리보기를 갖춘 compact 설정 앱 구조로 재정리했습니다."
    }
    "Migrated already-typed key totals into the new reward charge bank so existing 1000+ users can see the ready chest icon immediately." {
      return "이미 누적된 타자 수를 새 보상 충전값으로 마이그레이션해 1000회 이상 사용자는 바로 ready 상자 아이콘을 볼 수 있게 했습니다."
    }
    "Kept the ready chest icon tied to the 1000-key charge state so fully unlocked test inventories still show that the chest is charged." {
      return "테스트 인벤토리가 전체 해금 상태여도 1000키 충전 상태 자체는 ready 상자 아이콘으로 표시되게 했습니다."
    }
    "Hid the inactive reward claim button when every reward is already unlocked so the reward popover no longer shows an unexplained gray bar." {
      return "모든 보상이 이미 해금된 상태에서는 비활성 보상 상자 버튼을 숨겨, 보상 팝오버에 의미 없는 회색 막대가 보이지 않도록 수정했습니다."
    }
    default {
      return $Bullet
    }
  }
}

function Convert-ChangelogBodyToAnnouncementLines {
  param([string]$Body, [switch]$Korean)

  $lines = New-Object System.Collections.Generic.List[string]
  $body -split "`r?`n" | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    if ($line -match '^###\s+(.+)$') {
      $heading = $matches[1].Trim()
      $emoji = Convert-ChangelogHeadingEmoji -Heading $heading
      if ($Korean) {
        $lines.Add("")
        $lines.Add("$emoji $(Convert-ChangelogHeadingKo -Heading $heading)")
      } else {
        $lines.Add("")
        $lines.Add("$emoji $heading")
      }
      return
    }

    if ($line -match '^-\s+(.+)$') {
      $bullet = $matches[1].Trim()
      if ($Korean) {
        $bullet = Convert-ChangelogBulletKo -Bullet $bullet
      }
      $lines.Add("- $bullet")
    }
  }

  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
    $lines.RemoveAt(0)
  }
  return @($lines)
}

function Get-ReleaseAnnouncement {
  param([string]$TargetVersion)

  $parts = Get-ReleaseAnnouncementParts -TargetVersion $TargetVersion
  return ([string]$parts.Korean + "`r`n`r`n" + [string]$parts.English)
}

function Get-ReleaseAnnouncementParts {
  param([string]$TargetVersion)

  $displayVersion = "v$TargetVersion"
  $fenceStart = (([string][char]96) * 3) + "text"
  $fenceEnd = ([string][char]96) * 3
  $changelogBody = Get-ChangelogBody -TargetVersion $TargetVersion
  $koreanUpdates = Convert-ChangelogBodyToAnnouncementLines -Body $changelogBody -Korean
  $englishUpdates = Convert-ChangelogBodyToAnnouncementLines -Body $changelogBody

  $koreanLines = @(
    $fenceStart,
    "✨ Codexy Pet Usages Ring $displayVersion 업데이트 ",
    "",
    "이번 버전에 포함된 업데이트입니다.",
    ""
  ) + $koreanUpdates + @(
    "",
    "🐾 Codex Desktop 안에서 즐기는",
    "작은 펫 게이미피케이션 기능입니다.",
    "",
    "🔗 https://github.com/himomohi/Codexy-pet-usages-ring",
    $fenceEnd
  )
  $korean = $koreanLines -join "`r`n"

  $englishLines = @(
    $fenceStart,
    "✨ Codexy Pet Usages Ring $displayVersion Update",
    "",
    "This release includes the following updates.",
    ""
  ) + $englishUpdates + @(
    "",
    "🐾 A Small Pet Gamification Feature",
    "Made to be enjoyed inside Codex Desktop.",
    "",
    "🔗 https://github.com/himomohi/Codexy-pet-usages-ring",
    $fenceEnd
  )
  $english = $englishLines -join "`r`n"

  return [PSCustomObject]@{
    Korean = $korean
    English = $english
    Combined = ($korean + "`r`n`r`n" + $english)
  }
}

function Write-ReleaseAnnouncementFiles {
  param([string]$TargetVersion, [string]$OutputDirectory)

  $resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
  if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
  }

  $parts = Get-ReleaseAnnouncementParts -TargetVersion $TargetVersion
  $combinedPath = Join-Path $resolvedOutput "RELEASE_ANNOUNCEMENT_COPY_THIS.md"
  $koPath = Join-Path $resolvedOutput "RELEASE_ANNOUNCEMENT.ko.md"
  $enPath = Join-Path $resolvedOutput "RELEASE_ANNOUNCEMENT.en.md"
  $mustIncludePath = Join-Path $resolvedOutput "FINAL_REPLY_MUST_INCLUDE_RELEASE_ANNOUNCEMENT.txt"

  Set-Content -LiteralPath $combinedPath -Value ([string]$parts.Combined) -Encoding UTF8
  Set-Content -LiteralPath $koPath -Value ([string]$parts.Korean) -Encoding UTF8
  Set-Content -LiteralPath $enPath -Value ([string]$parts.English) -Encoding UTF8
  Set-Content -LiteralPath $mustIncludePath -Encoding UTF8 -Value @(
    "After running the release harness, include the Korean and English release announcement code blocks in the final user-facing reply.",
    "Copy them from RELEASE_ANNOUNCEMENT_COPY_THIS.md.",
    "Do not only summarize the release upload.",
    "Always confirm that deployment rewards/unlocks were verified as locked/reset by the release harness."
  )

  return [PSCustomObject]@{
    CombinedPath = $combinedPath
    KoreanPath = $koPath
    EnglishPath = $enPath
    ReminderPath = $mustIncludePath
  }
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

$announcementFiles = Write-ReleaseAnnouncementFiles -TargetVersion $Version -OutputDirectory $DeployDirectory

Write-Step "Release harness completed"
[PSCustomObject]@{
  Version = $Version
  ZipPath = $deploy.ZipPath
  Sha256 = $deploy.Sha256
  ExtractPath = $deploy.ExtractPath
  ExtractedFileCount = $deploy.FileCount
  Published = [bool]$PublishGitHub
  AnnouncementPath = $announcementFiles.CombinedPath
  AnnouncementKoPath = $announcementFiles.KoreanPath
  AnnouncementEnPath = $announcementFiles.EnglishPath
  FinalReplyReminderPath = $announcementFiles.ReminderPath
} | Format-List

Write-Step "Release announcement"
Write-Output (Get-Content -Raw -LiteralPath $announcementFiles.CombinedPath)
