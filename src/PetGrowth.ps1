function Get-PetGrowthDateKey {
  param([datetime]$Now = (Get-Date))
  return $Now.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-PetGrowthLevel {
  param($TotalXp)
  $xp = [Math]::Max(0, [int][double]$TotalXp)
  if ($xp -ge 450) { return 5 }
  if ($xp -ge 250) { return 4 }
  if ($xp -ge 125) { return 3 }
  if ($xp -ge 50) { return 2 }
  return 1
}

function Get-PetGrowthNextLevelXp {
  param($TotalXp)
  $level = Get-PetGrowthLevel -TotalXp $TotalXp
  switch ($level) {
    1 { return 50 }
    2 { return 125 }
    3 { return 250 }
    4 { return 450 }
    default { return $null }
  }
}

function Normalize-PetGrowthMode {
  param($Value)
  $mode = if ($null -eq $Value) { "balanced" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($mode -in @("conserve", "balanced", "active")) { return $mode }
  return "balanced"
}

function Get-PetGrowthPrimaryTargetUsed {
  param([string]$GrowthMode = "balanced")
  $mode = Normalize-PetGrowthMode $GrowthMode
  if ($mode -eq "conserve") { return 20.0 }
  if ($mode -eq "active") { return 60.0 }
  return 40.0
}

function Get-PetGrowthPrimaryUsedPercent {
  param($PrimaryRemaining)
  if ($null -eq $PrimaryRemaining) { return $null }
  $primary = [Math]::Max(0.0, [Math]::Min(100.0, [double]$PrimaryRemaining))
  return [Math]::Round(100.0 - $primary, 3)
}

function Get-PetGrowthTodayXpTarget {
  param($PrimaryRemaining, [bool]$HasUsageSnapshot = $true, [string]$GrowthMode = "balanced")
  if (-not $HasUsageSnapshot -or $null -eq $PrimaryRemaining) { return 0 }
  $used = Get-PetGrowthPrimaryUsedPercent -PrimaryRemaining $PrimaryRemaining
  if ($null -eq $used) { return 0 }
  $target = Get-PetGrowthPrimaryTargetUsed -GrowthMode $GrowthMode
  if ($target -le 0.0) { return 0 }
  $progress = [Math]::Max(0.0, [Math]::Min(1.0, [double]$used / [double]$target))
  return [Math]::Min(30, [int][Math]::Floor($progress * 30.0))
}

function Get-PetGrowthCondition {
  param($PrimaryRemaining, $SecondaryRemaining, [bool]$HasUsageSnapshot = $true, [string]$GrowthMode = "balanced")
  if (-not $HasUsageSnapshot -or $null -eq $PrimaryRemaining) {
    return "waiting"
  }

  $primary = [Math]::Max(0.0, [Math]::Min(100.0, [double]$PrimaryRemaining))
  $secondary = if ($null -eq $SecondaryRemaining) { 100.0 } else { [Math]::Max(0.0, [Math]::Min(100.0, [double]$SecondaryRemaining)) }
  if ($primary -lt 10.0 -or $secondary -lt 10.0) { return "sleepy" }
  if ($primary -lt 20.0 -or $secondary -lt 20.0) { return "tired" }

  $primaryUsed = 100.0 - $primary
  $healthyPrimaryUsed = Get-PetGrowthPrimaryTargetUsed -GrowthMode $GrowthMode

  if ($primaryUsed -ge $healthyPrimaryUsed) { return "healthy" }
  return "stable"
}

function New-PetGrowthState {
  param([datetime]$Now = (Get-Date))
  return [PSCustomObject][ordered]@{
    version = 1
    totalXp = 0
    level = 1
    condition = "waiting"
    todayKey = Get-PetGrowthDateKey -Now $Now
    todayHealthySeconds = 0
    todayXp = 0
    todayPrimaryUsedPercent = 0
    todayTargetUsedPercent = 0
    healthyRemainderSeconds = 0
    lastUpdatedAt = $null
    lastCondition = "waiting"
    awardedResetKeys = @()
    inventory = [ordered]@{
      snack = 0
      gem = 0
      ticket = 0
      patch = 0
      fontPixel = $false
      fontTerminal = $false
      themeForest = $false
      themeArcane = $false
      themeRoyal = $false
      themeCyber = $false
      themeCelestial = $false
      activeFont = ""
      activeTheme = ""
      rewardRolls = 0
      totalDrops = 0
      totalKeys = 0
      lastDropAt = $null
      lastDropItem = ""
    }
  }
}

function ConvertTo-PetGrowthDateTime {
  param($Value)
  if ($null -eq $Value) { return $null }
  try {
    $date = [datetime]$Value
    if ($date.Kind -eq [System.DateTimeKind]::Utc) { return $date.ToLocalTime() }
    return $date
  } catch { return $null }
}

function Normalize-PetGrowthResetKeys {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @([string]$Value) }
  try { return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } catch { return @() }
}

function Normalize-PetGrowthState {
  param($State, [datetime]$Now = (Get-Date))
  $defaults = New-PetGrowthState -Now $Now
  if ($null -eq $State) { return $defaults }

  $get = {
    param($Object, [string]$Name, $Default)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
      $value = $Object[$Name]
      if ($null -eq $value) { return $Default }
      return $value
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
  }

  $totalXp = [Math]::Max(0, [int][double](& $get $State "totalXp" 0))
  $todayXp = [Math]::Max(0, [Math]::Min(30, [int][double](& $get $State "todayXp" 0)))
  $todayHealthy = [Math]::Max(0.0, [double](& $get $State "todayHealthySeconds" 0))
  $todayPrimaryUsed = [Math]::Max(0.0, [Math]::Min(100.0, [double](& $get $State "todayPrimaryUsedPercent" 0)))
  $todayTargetUsed = [Math]::Max(0.0, [Math]::Min(100.0, [double](& $get $State "todayTargetUsedPercent" 0)))
  $remainder = [Math]::Max(0.0, [Math]::Min(59.999, [double](& $get $State "healthyRemainderSeconds" 0)))
  $condition = [string](& $get $State "condition" "waiting")
  if ($condition -notin @("waiting", "healthy", "stable", "tired", "sleepy")) { $condition = "waiting" }
  $lastCondition = [string](& $get $State "lastCondition" $condition)
  if ($lastCondition -notin @("waiting", "healthy", "stable", "tired", "sleepy")) { $lastCondition = $condition }
  $todayKey = [string](& $get $State "todayKey" (Get-PetGrowthDateKey -Now $Now))
  if ([string]::IsNullOrWhiteSpace($todayKey)) { $todayKey = Get-PetGrowthDateKey -Now $Now }
  $inventory = & $get $State "inventory" $null
  $fontPixel = [bool](& $get $inventory "fontPixel" $false)
  $fontTerminal = [bool](& $get $inventory "fontTerminal" $false)
  $themeForest = [bool](& $get $inventory "themeForest" $false)
  $themeArcane = [bool](& $get $inventory "themeArcane" $false)
  $themeRoyal = [bool](& $get $inventory "themeRoyal" $false)
  $themeCyber = [bool](& $get $inventory "themeCyber" $false)
  $themeCelestial = [bool](& $get $inventory "themeCelestial" $false)
  $themeKeys = @("themeForest", "themeArcane", "themeRoyal", "themeCyber", "themeCelestial")
  $unlockKeys = @("fontPixel", "fontTerminal") + $themeKeys
  $cosmeticDropCount = @($fontPixel, $fontTerminal, $themeForest, $themeArcane, $themeRoyal, $themeCyber, $themeCelestial).Where({ $_ }).Count
  $activeFont = [string](& $get $inventory "activeFont" "")
  if ($activeFont -notin @("fontPixel", "fontTerminal") -or -not [bool](& $get $inventory $activeFont $false)) { $activeFont = "" }
  $activeTheme = [string](& $get $inventory "activeTheme" "")
  if ($activeTheme -notin $themeKeys -or -not [bool](& $get $inventory $activeTheme $false)) { $activeTheme = "" }
  $lastDropItem = [string](& $get $inventory "lastDropItem" "")
  $lastDropAt = & $get $inventory "lastDropAt" $null
  if ($lastDropItem -notin $unlockKeys) {
    $lastDropItem = ""
    $lastDropAt = $null
  }
  $rewardRolls = [Math]::Max(0, [int][double](& $get $inventory "rewardRolls" 0))
  if ($cosmeticDropCount -le 0) { $rewardRolls = 0 }

  return [PSCustomObject][ordered]@{
    version = 1
    totalXp = $totalXp
    level = Get-PetGrowthLevel -TotalXp $totalXp
    condition = $condition
    todayKey = $todayKey
    todayHealthySeconds = [Math]::Round($todayHealthy, 3)
    todayXp = $todayXp
    todayPrimaryUsedPercent = [Math]::Round($todayPrimaryUsed, 3)
    todayTargetUsedPercent = [Math]::Round($todayTargetUsed, 3)
    healthyRemainderSeconds = [Math]::Round($remainder, 3)
    lastUpdatedAt = & $get $State "lastUpdatedAt" $null
    lastCondition = $lastCondition
    awardedResetKeys = Normalize-PetGrowthResetKeys (& $get $State "awardedResetKeys" @())
    inventory = [ordered]@{
      snack = [Math]::Max(0, [int][double](& $get $inventory "snack" 0))
      gem = [Math]::Max(0, [int][double](& $get $inventory "gem" 0))
      ticket = [Math]::Max(0, [int][double](& $get $inventory "ticket" 0))
      patch = [Math]::Max(0, [int][double](& $get $inventory "patch" 0))
      fontPixel = $fontPixel
      fontTerminal = $fontTerminal
      themeForest = $themeForest
      themeArcane = $themeArcane
      themeRoyal = $themeRoyal
      themeCyber = $themeCyber
      themeCelestial = $themeCelestial
      activeFont = $activeFont
      activeTheme = $activeTheme
      rewardRolls = $rewardRolls
      totalDrops = $cosmeticDropCount
      totalKeys = [Math]::Max(0, [int][double](& $get $inventory "totalKeys" 0))
      lastDropAt = $lastDropAt
      lastDropItem = $lastDropItem
    }
  }
}

function Get-PetGrowthResetKey {
  param([string]$Name, $ResetAt)
  if ($null -eq $ResetAt) { return $null }
  try {
    $reset = ([datetime]$ResetAt).ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    return "${Name}:$reset"
  } catch {
    return $null
  }
}

function Update-PetGrowthState {
  param(
    $State,
    $PrimaryRemaining,
    $SecondaryRemaining,
    $PrimaryResetAt,
    $SecondaryResetAt,
    [datetime]$Now = (Get-Date),
    [bool]$HasUsageSnapshot = $true,
    [bool]$PetVisible = $true,
    [string]$GrowthMode = "balanced",
    [bool]$Enabled = $true
  )

  $next = Normalize-PetGrowthState -State $State -Now $Now
  $oldJson = $next | ConvertTo-Json -Depth 6 -Compress
  $todayKey = Get-PetGrowthDateKey -Now $Now
  if ($next.todayKey -ne $todayKey) {
    $next.todayKey = $todayKey
    $next.todayHealthySeconds = 0
    $next.todayXp = 0
    $next.todayPrimaryUsedPercent = 0
    $next.todayTargetUsedPercent = 0
    $next.healthyRemainderSeconds = 0
  }

  $condition = if ($Enabled -and $PetVisible) {
    Get-PetGrowthCondition -PrimaryRemaining $PrimaryRemaining -SecondaryRemaining $SecondaryRemaining -HasUsageSnapshot $HasUsageSnapshot -GrowthMode $GrowthMode
  } else {
    "waiting"
  }

  $lastUpdatedAt = ConvertTo-PetGrowthDateTime $next.lastUpdatedAt

  $awardedXp = 0
  $weeklyResetApplied = $false
  if ($Enabled -and $PetVisible -and $HasUsageSnapshot -and $null -ne $lastUpdatedAt) {
    $weeklyResetAt = ConvertTo-PetGrowthDateTime $SecondaryResetAt
    if ($null -ne $weeklyResetAt -and $lastUpdatedAt -lt $weeklyResetAt -and $Now -ge $weeklyResetAt) {
      $weeklyResetKey = Get-PetGrowthResetKey -Name "secondary" -ResetAt $weeklyResetAt
      if ($null -ne $weeklyResetKey -and $weeklyResetKey -notin @($next.awardedResetKeys)) {
        $next.totalXp = 0
        $next.level = 1
        $next.todayHealthySeconds = 0
        $next.todayXp = 0
        $next.todayPrimaryUsedPercent = 0
        $next.todayTargetUsedPercent = 0
        $next.healthyRemainderSeconds = 0
        $next.awardedResetKeys = @($next.awardedResetKeys + $weeklyResetKey)
        $weeklyResetApplied = $true
      }
    }
  }

  if ($Enabled -and $PetVisible -and $HasUsageSnapshot -and -not $weeklyResetApplied -and $condition -in @("stable", "healthy")) {
    $usedPercent = Get-PetGrowthPrimaryUsedPercent -PrimaryRemaining $PrimaryRemaining
    if ($null -ne $usedPercent) {
      $next.todayPrimaryUsedPercent = [Math]::Round([double]$usedPercent, 3)
      $next.todayTargetUsedPercent = [Math]::Round((Get-PetGrowthPrimaryTargetUsed -GrowthMode $GrowthMode), 3)
      $targetTodayXp = Get-PetGrowthTodayXpTarget -PrimaryRemaining $PrimaryRemaining -HasUsageSnapshot $HasUsageSnapshot -GrowthMode $GrowthMode
      if ($targetTodayXp -gt [int]$next.todayXp) {
        $deltaXp = [Math]::Min(30 - [int]$next.todayXp, [int]$targetTodayXp - [int]$next.todayXp)
        if ($deltaXp -gt 0) {
          $next.totalXp = [int]$next.totalXp + $deltaXp
          $next.todayXp = [int]$next.todayXp + $deltaXp
          $awardedXp += $deltaXp
        }
      }
    }
    $next.healthyRemainderSeconds = 0

    $primaryResetAt = ConvertTo-PetGrowthDateTime $PrimaryResetAt
    if ($null -ne $primaryResetAt -and $null -ne $lastUpdatedAt -and $lastUpdatedAt -lt $primaryResetAt -and $Now -ge $primaryResetAt) {
      $key = Get-PetGrowthResetKey -Name "primary" -ResetAt $primaryResetAt
      $chargedForReset = ($condition -eq "healthy" -or [string]$next.lastCondition -eq "healthy")
      if ($chargedForReset -and $null -ne $key -and $key -notin @($next.awardedResetKeys)) {
        $next.totalXp = [int]$next.totalXp + 10
        $awardedXp += 10
        $next.awardedResetKeys = @($next.awardedResetKeys + $key)
      }
    }
  }

  $next.awardedResetKeys = @($next.awardedResetKeys | Select-Object -Last 32)
  $next.condition = $condition
  $next.level = Get-PetGrowthLevel -TotalXp $next.totalXp
  $next.lastCondition = $condition
  $next.lastUpdatedAt = $Now.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)

  $newJson = $next | ConvertTo-Json -Depth 6 -Compress
  return [PSCustomObject]@{
    State = $next
    Changed = ($oldJson -ne $newJson)
    AwardedXp = $awardedXp
  }
}
