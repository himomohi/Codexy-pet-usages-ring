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

function Get-PetGrowthCondition {
  param($PrimaryRemaining, $SecondaryRemaining, [bool]$HasUsageSnapshot = $true, [string]$GrowthMode = "balanced")
  if (-not $HasUsageSnapshot -or $null -eq $PrimaryRemaining -or $null -eq $SecondaryRemaining) {
    return "waiting"
  }

  $primary = [Math]::Max(0.0, [Math]::Min(100.0, [double]$PrimaryRemaining))
  $secondary = [Math]::Max(0.0, [Math]::Min(100.0, [double]$SecondaryRemaining))
  if ($primary -lt 10.0 -or $secondary -lt 10.0) { return "sleepy" }
  if ($primary -lt 20.0 -or $secondary -lt 20.0) { return "tired" }

  $mode = Normalize-PetGrowthMode $GrowthMode
  $primaryUsed = 100.0 - $primary
  $secondaryUsed = 100.0 - $secondary
  $healthyPrimaryUsed = 20.0
  $healthySecondaryUsed = 10.0
  if ($mode -eq "balanced") {
    $healthyPrimaryUsed = 40.0
    $healthySecondaryUsed = 20.0
  } elseif ($mode -eq "active") {
    $healthyPrimaryUsed = 60.0
    $healthySecondaryUsed = 35.0
  }

  if ($primaryUsed -ge $healthyPrimaryUsed -and $secondaryUsed -ge $healthySecondaryUsed) { return "healthy" }
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
    healthyRemainderSeconds = 0
    lastUpdatedAt = $null
    lastCondition = "waiting"
    awardedResetKeys = @()
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
  $remainder = [Math]::Max(0.0, [Math]::Min(59.999, [double](& $get $State "healthyRemainderSeconds" 0)))
  $condition = [string](& $get $State "condition" "waiting")
  if ($condition -notin @("waiting", "healthy", "stable", "tired", "sleepy")) { $condition = "waiting" }
  $lastCondition = [string](& $get $State "lastCondition" $condition)
  if ($lastCondition -notin @("waiting", "healthy", "stable", "tired", "sleepy")) { $lastCondition = $condition }
  $todayKey = [string](& $get $State "todayKey" (Get-PetGrowthDateKey -Now $Now))
  if ([string]::IsNullOrWhiteSpace($todayKey)) { $todayKey = Get-PetGrowthDateKey -Now $Now }

  return [PSCustomObject][ordered]@{
    version = 1
    totalXp = $totalXp
    level = Get-PetGrowthLevel -TotalXp $totalXp
    condition = $condition
    todayKey = $todayKey
    todayHealthySeconds = [Math]::Round($todayHealthy, 3)
    todayXp = $todayXp
    healthyRemainderSeconds = [Math]::Round($remainder, 3)
    lastUpdatedAt = & $get $State "lastUpdatedAt" $null
    lastCondition = $lastCondition
    awardedResetKeys = Normalize-PetGrowthResetKeys (& $get $State "awardedResetKeys" @())
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
    $next.healthyRemainderSeconds = 0
  }

  $condition = if ($Enabled -and $PetVisible) {
    Get-PetGrowthCondition -PrimaryRemaining $PrimaryRemaining -SecondaryRemaining $SecondaryRemaining -HasUsageSnapshot $HasUsageSnapshot -GrowthMode $GrowthMode
  } else {
    "waiting"
  }

  $lastUpdatedAt = ConvertTo-PetGrowthDateTime $next.lastUpdatedAt
  $elapsedSeconds = if ($null -eq $lastUpdatedAt) {
    0.0
  } else {
    [Math]::Max(0.0, [Math]::Min(300.0, ($Now - $lastUpdatedAt).TotalSeconds))
  }

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
        $next.healthyRemainderSeconds = 0
        $next.awardedResetKeys = @($next.awardedResetKeys + $weeklyResetKey)
        $weeklyResetApplied = $true
      }
    }
  }

  if ($Enabled -and $PetVisible -and $HasUsageSnapshot -and -not $weeklyResetApplied -and $condition -eq "healthy") {
    $next.todayHealthySeconds = [Math]::Round(([double]$next.todayHealthySeconds + $elapsedSeconds), 3)
    $remainder = [double]$next.healthyRemainderSeconds + $elapsedSeconds
    while ($remainder -ge 60.0 -and [int]$next.todayXp -lt 30) {
      $next.totalXp = [int]$next.totalXp + 1
      $next.todayXp = [int]$next.todayXp + 1
      $awardedXp += 1
      $remainder -= 60.0
    }
    if ([int]$next.todayXp -ge 30) {
      $remainder = [Math]::Min($remainder, 59.999)
    }
    $next.healthyRemainderSeconds = [Math]::Round([Math]::Max(0.0, $remainder), 3)

    $primaryResetAt = ConvertTo-PetGrowthDateTime $PrimaryResetAt
    if ($null -ne $primaryResetAt -and $null -ne $lastUpdatedAt -and $lastUpdatedAt -lt $primaryResetAt -and $Now -ge $primaryResetAt) {
      $key = Get-PetGrowthResetKey -Name "primary" -ResetAt $primaryResetAt
      if ($null -ne $key -and $key -notin @($next.awardedResetKeys)) {
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
