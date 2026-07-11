function Get-SystemUiLanguage {
  try {
    if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like "ko*") { return "ko" }
  } catch {}
  return "en"
}

function Convert-CountryCodeToLanguage {
  param($CountryCode)

  if ($null -eq $CountryCode) { return $null }
  $normalized = ([string]$CountryCode).Trim().ToUpperInvariant()
  if ($normalized -notmatch '^[A-Z]{2}$') { return $null }
  if ($normalized -eq "KR") { return "ko" }
  return "en"
}

function Get-LanguageCachePath {
  param([Parameter(Mandatory = $true)][string]$SettingsPath)

  $settingsFile = [System.IO.Path]::GetFullPath($SettingsPath)
  $directory = Split-Path -Parent $settingsFile
  if ([string]::IsNullOrWhiteSpace($directory)) {
    $directory = (Get-Location).Path
  }
  return (Join-Path $directory ".codex-pet-language-cache.json")
}

function Read-IpCountryCache {
  param(
    [string]$CachePath,
    [double]$CacheHours = 24
  )

  if ([string]::IsNullOrWhiteSpace($CachePath) -or -not (Test-Path -LiteralPath $CachePath)) {
    return $null
  }

  try {
    $cache = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $countryCode = ([string]$cache.country).Trim().ToUpperInvariant()
    if ($countryCode -notmatch '^[A-Z]{2}$') { return $null }

    $checkedAt = [DateTimeOffset]::MinValue
    $parsed = [DateTimeOffset]::TryParse(
      [string]$cache.checkedAtUtc,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::AssumeUniversal,
      [ref]$checkedAt
    )
    if (-not $parsed) { return $null }

    $maximumAge = [TimeSpan]::FromHours([Math]::Max(1, $CacheHours))
    if (([DateTimeOffset]::UtcNow - $checkedAt.ToUniversalTime()) -gt $maximumAge) { return $null }

    return [PSCustomObject]@{
      CountryCode = $countryCode
      Source = "cache"
    }
  } catch {
    return $null
  }
}

function Write-IpCountryCache {
  param(
    [string]$CachePath,
    [Parameter(Mandatory = $true)][string]$CountryCode
  )

  if ([string]::IsNullOrWhiteSpace($CachePath)) { return }
  $normalized = $CountryCode.Trim().ToUpperInvariant()
  if ($normalized -notmatch '^[A-Z]{2}$') { return }

  $temporaryPath = "{0}.{1}.tmp" -f $CachePath, $PID
  try {
    $directory = Split-Path -Parent $CachePath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
      New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $payload = [ordered]@{
      country = $normalized
      checkedAtUtc = [DateTimeOffset]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $json = ($payload | ConvertTo-Json -Depth 3) + [Environment]::NewLine
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8)
    Move-Item -LiteralPath $temporaryPath -Destination $CachePath -Force
  } catch {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-IpCountryResult {
  param(
    [string]$CachePath = "",
    [int]$TimeoutSeconds = 2,
    [double]$CacheHours = 24,
    [string]$CountryCodeOverride = ""
  )

  $override = $CountryCodeOverride.Trim().ToUpperInvariant()
  if ($override -match '^[A-Z]{2}$') {
    return [PSCustomObject]@{
      CountryCode = $override
      Source = "override"
    }
  }

  $cached = Read-IpCountryCache -CachePath $CachePath -CacheHours $CacheHours
  if ($null -ne $cached) { return $cached }

  try {
    $response = Invoke-RestMethod `
      -Uri "https://api.country.is/" `
      -Method Get `
      -TimeoutSec ([Math]::Max(1, $TimeoutSeconds)) `
      -Headers @{ Accept = "application/json" }
    $countryCode = ([string]$response.country).Trim().ToUpperInvariant()
    if ($countryCode -notmatch '^[A-Z]{2}$') { throw "IP country response did not contain a valid country code." }
    Write-IpCountryCache -CachePath $CachePath -CountryCode $countryCode
    return [PSCustomObject]@{
      CountryCode = $countryCode
      Source = "network"
    }
  } catch {
    return [PSCustomObject]@{
      CountryCode = ""
      Source = "unavailable"
    }
  }
}

function Get-AutomaticLanguageResult {
  param(
    [string]$CachePath = "",
    [int]$TimeoutSeconds = 2,
    [double]$CacheHours = 24,
    [string]$CountryCodeOverride = ""
  )

  $country = Get-IpCountryResult `
    -CachePath $CachePath `
    -TimeoutSeconds $TimeoutSeconds `
    -CacheHours $CacheHours `
    -CountryCodeOverride $CountryCodeOverride
  $language = Convert-CountryCodeToLanguage -CountryCode $country.CountryCode
  if ($null -eq $language) {
    return [PSCustomObject]@{
      Language = Get-SystemUiLanguage
      CountryCode = ""
      Source = "system"
    }
  }

  return [PSCustomObject]@{
    Language = $language
    CountryCode = $country.CountryCode
    Source = $country.Source
  }
}
