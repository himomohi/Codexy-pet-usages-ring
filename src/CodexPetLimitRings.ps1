param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$NoLiveUsage,
  [int]$UsagePollSeconds = 30,
  [int]$UsageStaleSeconds = 120,
  [int]$FramePollMs = 60,
  [int]$IdleFramePollMs = 500,
  [int]$PetPollMs = 500,
  [double]$UsageAnimationFactor = 0.22,
  [double]$RingPadding = 38.0,
  [double]$ReadoutPadding = 160.0,
  [double]$OuterStroke = 7.0,
  [double]$InnerStroke = 4.5,
  [byte]$PrimaryOpacity = 172,
  [byte]$SecondaryOpacity = 160,
  [byte]$WarningOpacity = 185,
  [byte]$TrackOpacity = 22,
  [string]$SettingsPath = "",
  [string]$LogDirectory = "",
  [switch]$NoTrayIcon
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codex Pet Limit Rings for Windows can only run on Windows."
}

$UsagePollSeconds = [Math]::Max(5, $UsagePollSeconds)
$UsageStaleSeconds = [Math]::Max($UsagePollSeconds * 3, $UsageStaleSeconds)
$FramePollMs = [Math]::Max(60, $FramePollMs)
$IdleFramePollMs = [Math]::Max($FramePollMs, $IdleFramePollMs)
$PetPollMs = [Math]::Max(150, $PetPollMs)
$UsageAnimationFactor = [Math]::Max(0.01, [Math]::Min(1.0, $UsageAnimationFactor))
$RingPadding = [Math]::Max(12.0, $RingPadding)
$ReadoutPadding = [Math]::Max(0.0, $ReadoutPadding)
$OuterStroke = [Math]::Max(1.0, $OuterStroke)
$InnerStroke = [Math]::Max(1.0, $InnerStroke)

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
  $LogDirectory = Join-Path $env:LOCALAPPDATA "CodexPetLimitRingsWin\logs"
}
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$script:LogFile = Join-Path $LogDirectory "rings.log"

function Write-AppLog {
  param([string]$Message)
  try {
    if ($Message.Length -gt 1000) {
      $Message = $Message.Substring(0, 1000) + " ...[truncated]"
    }
    $line = "{0:s} {1}" -f (Get-Date), $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
  } catch {
    # Logging must never stop the overlay.
  }
}

function Read-Utf8Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

Write-AppLog "Starting Codex Pet Limit Rings for Windows."

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("CodexPetLimitRingNative" -as [type])) {
  Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class CodexPetLimitRingNative {
    private const int GWL_EXSTYLE = -20;
    private static readonly IntPtr WS_EX_TRANSPARENT = new IntPtr(0x00000020);
    private static readonly IntPtr WS_EX_TOOLWINDOW = new IntPtr(0x00000080);
    private static readonly IntPtr WS_EX_NOACTIVATE = new IntPtr(0x08000000);
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_NOOWNERZORDER = 0x0200;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);

    public static void MakeClickThrough(IntPtr hWnd) {
        IntPtr style = GetWindowLongPtr64(hWnd, GWL_EXSTYLE);
        long newStyle = style.ToInt64()
            | WS_EX_TRANSPARENT.ToInt64()
            | WS_EX_TOOLWINDOW.ToInt64()
            | WS_EX_NOACTIVATE.ToInt64();
        SetWindowLongPtr64(hWnd, GWL_EXSTYLE, new IntPtr(newStyle));
    }

    private static bool Overlaps(RECT rect, int left, int top, int right, int bottom) {
        return rect.Left < right && rect.Right > left && rect.Top < bottom && rect.Bottom > top;
    }

    private static bool IsCodexWindow(IntPtr hWnd) {
        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);
        if (processId == 0) {
            return false;
        }

        try {
            Process process = Process.GetProcessById(unchecked((int)processId));
            string processName = process.ProcessName;
            if (string.Equals(processName, "Codex", StringComparison.OrdinalIgnoreCase)) {
                return true;
            }
            if (!string.Equals(processName, "ChatGPT", StringComparison.OrdinalIgnoreCase)) {
                return false;
            }

            string executablePath = process.MainModule == null ? "" : process.MainModule.FileName;
            return executablePath.IndexOf("\\OpenAI.Codex_", StringComparison.OrdinalIgnoreCase) >= 0
                && executablePath.EndsWith("\\app\\ChatGPT.exe", StringComparison.OrdinalIgnoreCase);
        } catch {
            return false;
        }
    }

    public static IntPtr FindOverlappingCodexWindow(
        IntPtr ownHWnd,
        int left,
        int top,
        int right,
        int bottom
    ) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (hWnd == ownHWnd || !IsWindowVisible(hWnd)) {
                return true;
            }

            RECT rect;
            if (!GetWindowRect(hWnd, out rect) || !Overlaps(rect, left, top, right, bottom)) {
                return true;
            }

            if (!IsCodexWindow(hWnd)) {
                return true;
            }

            found = hWnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    public static void PlaceBehind(IntPtr hWnd, IntPtr frontHWnd) {
        if (hWnd == IntPtr.Zero || frontHWnd == IntPtr.Zero) {
            return;
        }

        SetWindowPos(
            hWnd,
            frontHWnd,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
        );
    }

    public static bool TrimWorkingSet() {
        try {
            return EmptyWorkingSet(Process.GetCurrentProcess().Handle);
        } catch {
            return false;
        }
    }
}
"@
}

try {
  [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
} catch {
  Write-AppLog "Process priority update failed: $($_.Exception.Message)"
}

$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
  $SettingsPath = Join-Path $ProjectRoot "settings.json"
}
$SettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)
$SettingsDefaultsPath = Join-Path $ProjectRoot "settings.defaults.json"
$PotionPixelFramePath = Join-Path $ProjectRoot "assets\runtime\potion-pixel-frame.png"
$PotionPixelMaskPath = Join-Path $ProjectRoot "assets\runtime\potion-pixel-mask.png"
$HeartPotionPixelFramePath = Join-Path $ProjectRoot "assets\runtime\heart-potion-pixel-frame.png"
$HeartPotionPixelMaskPath = Join-Path $ProjectRoot "assets\runtime\heart-potion-pixel-mask.png"
$TrayCatIconPath = Join-Path $ProjectRoot "assets\runtime\tray-cat-icon.ico"
$LanguageDetectionScript = Join-Path $ProjectRoot "src\LanguageDetection.ps1"
if (-not (Test-Path -LiteralPath $LanguageDetectionScript)) {
  throw "Missing language detection module: $LanguageDetectionScript"
}
. $LanguageDetectionScript
$script:LanguageCachePath = Get-LanguageCachePath -SettingsPath $SettingsPath
$script:AutomaticLanguageResult = [PSCustomObject]@{
  Language = Get-SystemUiLanguage
  CountryCode = ""
  Source = "system"
}
$StatePath = Join-Path $CodexHome ".codex-global-state.json"
$AuthPath = Join-Path $CodexHome "auth.json"
$LogsPath = Join-Path $CodexHome "logs_2.sqlite"
if (-not (Test-Path -LiteralPath $LogsPath)) {
  $LogsPath = Join-Path $CodexHome "logs_1.sqlite"
}

$script:UsageState = [PSCustomObject]@{
  Source = "none"
  Plan = $null
  PrimaryRemaining = $null
  SecondaryRemaining = $null
  PrimaryResetAt = $null
  SecondaryResetAt = $null
  PrimaryWindowSeconds = $null
  SecondaryWindowSeconds = $null
  ObservedAt = Get-Date
}
$script:DisplayedUsageState = [PSCustomObject]@{
  PrimaryRemaining = $null
  SecondaryRemaining = $null
}
$script:HasUsageSnapshot = $false
$script:LastUsageSuccessAt = [datetime]::MinValue
$script:UsageIsStale = $false
$script:LastUsageSignature = ""
$script:PendingUsageSignature = ""
$script:PendingUsageCount = 0
$script:LastPetRect = $null
$script:LastPetVisible = $null
$script:LastPetFrameSignature = ""
$script:LastZOrderAt = [datetime]::MinValue
$script:LastStateWriteTimeUtc = [datetime]::MinValue
$script:CachedPetRect = $null
$script:RingOuterRadius = $null
$script:RingInnerRadius = $null
$script:LastReadoutRefreshAt = [datetime]::MinValue
$script:LastHoverSignature = ""
$script:RingVisualsVisible = $null
$script:RingAnimationToken = 0
$script:SettingsLastWriteTimeUtc = [datetime]::MinValue
$script:Style = [ordered]@{
  Language = "auto"
  AppearanceMode = "rings"
  PotionScale = 100.0
  PrimaryRgb = @(60, 235, 189)
  SecondaryRgb = @(86, 178, 255)
  WarningRgb = @(255, 66, 56)
  CautionRgb = @(255, 174, 51)
  TrackRgb = @(255, 255, 255)
  ReadoutTextRgb = @(255, 255, 255)
  OuterReadoutBgRgb = @(13, 24, 30)
  InnerReadoutBgRgb = @(15, 22, 36)
  PrimaryOpacity = $PrimaryOpacity
  SecondaryOpacity = $SecondaryOpacity
  WarningOpacity = $WarningOpacity
  TrackOpacity = $TrackOpacity
  ReadoutOpacity = 182
  ReadoutTextOpacity = 240
  ReadoutFontSize = 10.5
  ReadoutLineHeight = 13.0
  RingGap = [Math]::Max(0.0, [double]$RingPadding - 16.0)
  OffsetX = 0.0
  OffsetY = 0.0
  VisibilityMode = "always"
  HoverRange = 24.0
  FadeInMs = 120.0
  FadeOutMs = 180.0
}
$script:RingsEnabled = $true

function New-Brush {
  param([byte]$A, [byte]$R, [byte]$G, [byte]$B)
  $brush = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.Color]::FromArgb($A, $R, $G, $B)
  )
  $brush.Freeze()
  return $brush
}

function New-StyleBrush {
  param([byte]$Opacity, [int[]]$Rgb)
  return New-Brush $Opacity ([byte]$Rgb[0]) ([byte]$Rgb[1]) ([byte]$Rgb[2])
}

function Get-PropertyValue {
  param($Object, [string]$Name, $Default)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Convert-HexColor {
  param($Value, [int[]]$Fallback)
  if ($null -eq $Value) { return $Fallback }
  $hex = ([string]$Value).Trim()
  if ($hex.StartsWith("#")) { $hex = $hex.Substring(1) }
  if ($hex.Length -eq 3) {
    $hex = -join ($hex.ToCharArray() | ForEach-Object { "$_$_" })
  }
  if ($hex -notmatch '^[0-9a-fA-F]{6}$') { return $Fallback }
  return @(
    [Convert]::ToInt32($hex.Substring(0, 2), 16),
    [Convert]::ToInt32($hex.Substring(2, 2), 16),
    [Convert]::ToInt32($hex.Substring(4, 2), 16)
  )
}

function Convert-OpacityByte {
  param($Value, [byte]$Fallback)
  if ($null -eq $Value) { return $Fallback }
  try {
    $number = [double]$Value
    if ($number -le 1.0) { $number = $number * 255.0 }
    return [byte][Math]::Max(0, [Math]::Min(255, [int][Math]::Round($number)))
  } catch {
    return $Fallback
  }
}

function Convert-SettingNumber {
  param($Value, [double]$Fallback, [double]$Min, [double]$Max)
  if ($null -eq $Value) { return $Fallback }
  try { return [Math]::Max($Min, [Math]::Min($Max, [double]$Value)) } catch { return $Fallback }
}

function Ensure-SettingsFile {
  $settingsDirectory = Split-Path -Parent $SettingsPath
  if (-not [string]::IsNullOrWhiteSpace($settingsDirectory)) {
    New-Item -ItemType Directory -Force -Path $settingsDirectory | Out-Null
  }
  if (Test-Path -LiteralPath $SettingsPath) { return }
  if (Test-Path -LiteralPath $SettingsDefaultsPath) {
    Copy-Item -LiteralPath $SettingsDefaultsPath -Destination $SettingsPath -Force
    return
  }
  $fallback = [ordered]@{
    version = 1
    language = "auto"
    appearance = [ordered]@{
      mode = "rings"
      potionScale = 100
    }
    colors = [ordered]@{
      primary = "#3CEBBD"
      secondary = "#56B2FF"
      warning = "#FF4238"
      caution = "#FFAE33"
      track = "#FFFFFF"
      readoutText = "#FFFFFF"
      outerReadoutBackground = "#0D181E"
      innerReadoutBackground = "#0F1624"
    }
    opacity = [ordered]@{
      primary = 0.67
      secondary = 0.63
      warning = 0.73
      track = 0.09
      readout = 0.71
      readoutText = 0.94
    }
    text = [ordered]@{
      fontSize = 10.5
      lineHeight = 13
    }
    layout = [ordered]@{
      ringGap = 22
      offsetX = 0
      offsetY = 0
    }
    behavior = [ordered]@{
      visibilityMode = "always"
      hoverRange = 24
      fadeInMs = 120
      fadeOutMs = 180
    }
  }
  ($fallback | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Update-StyleFromSettings {
  param([switch]$Force)
  try {
    Ensure-SettingsFile
    $item = Get-Item -LiteralPath $SettingsPath -ErrorAction Stop
    if (-not $Force -and $item.LastWriteTimeUtc -eq $script:SettingsLastWriteTimeUtc) {
      return $false
    }
    $settings = Read-Utf8Text -Path $SettingsPath | ConvertFrom-Json
    $appearance = Get-PropertyValue $settings "appearance" $null
    $colors = Get-PropertyValue $settings "colors" $null
    $opacity = Get-PropertyValue $settings "opacity" $null
    $text = Get-PropertyValue $settings "text" $null
    $layout = Get-PropertyValue $settings "layout" $null
    $behavior = Get-PropertyValue $settings "behavior" $null

    $language = ([string](Get-PropertyValue $settings "language" "auto")).Trim().ToLowerInvariant()
    if ($language -notin @("auto", "ko", "en")) { $language = "auto" }
    $script:Style.Language = $language
    $appearanceMode = ([string](Get-PropertyValue $appearance "mode" "rings")).Trim().ToLowerInvariant()
    if ($appearanceMode -notin @("rings", "bars", "wings", "corners", "potions", "heart_potions")) { $appearanceMode = "rings" }
    $script:Style.AppearanceMode = $appearanceMode
    $script:Style.PotionScale = Convert-SettingNumber (Get-PropertyValue $appearance "potionScale" $null) 100 70 140
    $script:Style.PrimaryRgb = Convert-HexColor (Get-PropertyValue $colors "primary" $null) @(60, 235, 189)
    $script:Style.SecondaryRgb = Convert-HexColor (Get-PropertyValue $colors "secondary" $null) @(86, 178, 255)
    $script:Style.WarningRgb = Convert-HexColor (Get-PropertyValue $colors "warning" $null) @(255, 66, 56)
    $script:Style.CautionRgb = Convert-HexColor (Get-PropertyValue $colors "caution" $null) @(255, 174, 51)
    $script:Style.TrackRgb = Convert-HexColor (Get-PropertyValue $colors "track" $null) @(255, 255, 255)
    $script:Style.ReadoutTextRgb = Convert-HexColor (Get-PropertyValue $colors "readoutText" $null) @(255, 255, 255)
    $script:Style.OuterReadoutBgRgb = Convert-HexColor (Get-PropertyValue $colors "outerReadoutBackground" $null) @(13, 24, 30)
    $script:Style.InnerReadoutBgRgb = Convert-HexColor (Get-PropertyValue $colors "innerReadoutBackground" $null) @(15, 22, 36)
    $script:Style.PrimaryOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "primary" $null) $PrimaryOpacity
    $script:Style.SecondaryOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "secondary" $null) $SecondaryOpacity
    $script:Style.WarningOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "warning" $null) $WarningOpacity
    $script:Style.TrackOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "track" $null) $TrackOpacity
    $script:Style.ReadoutOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "readout" $null) 182
    $script:Style.ReadoutTextOpacity = Convert-OpacityByte (Get-PropertyValue $opacity "readoutText" $null) 240
    $script:Style.ReadoutFontSize = Convert-SettingNumber (Get-PropertyValue $text "fontSize" $null) 10.5 8 24
    $script:Style.ReadoutLineHeight = Convert-SettingNumber (Get-PropertyValue $text "lineHeight" $null) 13 10 32
    $script:Style.RingGap = Convert-SettingNumber (Get-PropertyValue $layout "ringGap" $null) ([Math]::Max(0.0, [double]$RingPadding - 16.0)) 0 96
    $script:Style.OffsetX = Convert-SettingNumber (Get-PropertyValue $layout "offsetX" $null) 0 -240 240
    $script:Style.OffsetY = Convert-SettingNumber (Get-PropertyValue $layout "offsetY" $null) 0 -240 240
    $visibilityMode = ([string](Get-PropertyValue $behavior "visibilityMode" "always")).Trim().ToLowerInvariant()
    if ($visibilityMode -notin @("always", "hover")) { $visibilityMode = "always" }
    $script:Style.VisibilityMode = $visibilityMode
    $script:Style.HoverRange = Convert-SettingNumber (Get-PropertyValue $behavior "hoverRange" $null) 24 0 96
    $script:Style.FadeInMs = Convert-SettingNumber (Get-PropertyValue $behavior "fadeInMs" $null) 120 0 1000
    $script:Style.FadeOutMs = Convert-SettingNumber (Get-PropertyValue $behavior "fadeOutMs" $null) 180 0 1000
    $script:SettingsLastWriteTimeUtc = $item.LastWriteTimeUtc
    return $true
  } catch {
    Write-AppLog "Settings update failed: $($_.Exception.Message)"
    return $false
  }
}

function Apply-StyleSettings {
  if ($null -ne $script:OuterTrack) {
    $script:OuterTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:InnerTrack) {
    $innerTrackOpacity = [byte][Math]::Max(10, [Math]::Min(255, [int]$script:Style.TrackOpacity - 4))
    $script:InnerTrack.Stroke = New-StyleBrush $innerTrackOpacity ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:OuterAltTrack) {
    $script:OuterAltTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:InnerAltTrack) {
    $innerTrackOpacity = [byte][Math]::Max(10, [Math]::Min(255, [int]$script:Style.TrackOpacity - 4))
    $script:InnerAltTrack.Stroke = New-StyleBrush $innerTrackOpacity ([int[]]$script:Style.TrackRgb)
  }
  foreach ($potionTrack in @($script:OuterPotionTrack, $script:InnerPotionTrack)) {
    if ($null -ne $potionTrack) {
      $potionTrack.Fill = New-StyleBrush 235 @(202, 148, 69)
      $potionTrack.Stroke = New-StyleBrush 245 @(92, 57, 26)
    }
  }
  foreach ($potionBackdrop in @($script:OuterPotionBackdrop, $script:InnerPotionBackdrop)) {
    if ($null -ne $potionBackdrop) {
      $potionBackdrop.Fill = New-StyleBrush 214 @(16, 20, 31)
      $potionBackdrop.Stroke = New-StyleBrush 180 @(239, 183, 87)
    }
  }
  foreach ($pixelPotion in @($script:OuterPixelPotion, $script:InnerPixelPotion, $script:OuterHeartPotion, $script:InnerHeartPotion)) {
    if ($null -ne $pixelPotion) {
      $pixelPotion.Backdrop.Fill = New-StyleBrush 238 @(19, 20, 20)
    }
  }
  if ($null -ne $script:OuterReadoutText) {
    $script:OuterReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    $script:OuterReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
    $script:OuterReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
  }
  if ($null -ne $script:InnerReadoutText) {
    $script:InnerReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    $script:InnerReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
    $script:InnerReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
  }
  if ($null -ne $script:OuterReadoutBorder) {
    $script:OuterReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
  }
  if ($null -ne $script:InnerReadoutBorder) {
    $script:InnerReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
  }
  Update-RingGeometry
  Set-RingShapesVisibility -Visibility $(if ($script:RingVisualsVisible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
  [void](Update-ReadoutText -Force)
  Update-TrayMenuText
  Update-TrayText
}

function Get-CapacityBrush {
  param([double]$Remaining, [switch]$Secondary)
  if ($Remaining -le 12) {
    return New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.WarningRgb)
  }
  if ($Remaining -le 30) {
    return New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.CautionRgb)
  }
  if ($Secondary) {
    return New-StyleBrush ([byte]$script:Style.SecondaryOpacity) ([int[]]$script:Style.SecondaryRgb)
  }
  return New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
}

function Get-EffectiveLanguage {
  $language = if ($null -ne $script:Style.Language) { [string]$script:Style.Language } else { "auto" }
  if ($language -eq "ko" -or $language -eq "en") { return $language }
  if ($null -ne $script:AutomaticLanguageResult) {
    $automatic = [string]$script:AutomaticLanguageResult.Language
    if ($automatic -eq "ko" -or $automatic -eq "en") { return $automatic }
  }
  return (Get-SystemUiLanguage)
}

function Update-AutomaticLanguage {
  if ([string]$script:Style.Language -ne "auto") { return }
  $script:AutomaticLanguageResult = Get-AutomaticLanguageResult `
    -CachePath $script:LanguageCachePath `
    -TimeoutSeconds 2 `
    -CacheHours 24
  Write-AppLog (
    "Automatic language resolved: language={0}, country={1}, source={2}." -f `
      $script:AutomaticLanguageResult.Language,
      $script:AutomaticLanguageResult.CountryCode,
      $script:AutomaticLanguageResult.Source
  )
}

function Test-KoreanLanguage {
  return ((Get-EffectiveLanguage) -eq "ko")
}

function Expand-UnicodeText {
  param([string]$Text)
  return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

function Get-UiText {
  param([string]$Key)
  if (Test-KoreanLanguage) {
    switch ($Key) {
      "TrayTitle" { return (Expand-UnicodeText "Codex \uB9C1") }
      "TrayText" { return (Expand-UnicodeText "Codex \uB9C1: {0} 5h, {1} \uC8FC\uAC04") }
      "ShowRings" { return (Expand-UnicodeText "\uB9C1 \uD45C\uC2DC") }
      "RefreshNow" { return (Expand-UnicodeText "\uC9C0\uAE08 \uC0C8\uB85C\uACE0\uCE68") }
      "Settings" { return (Expand-UnicodeText "\uC124\uC815") }
      "OpenLogs" { return (Expand-UnicodeText "\uB85C\uADF8 \uC5F4\uAE30") }
      "Quit" { return (Expand-UnicodeText "\uC885\uB8CC") }
    }
  }
  switch ($Key) {
    "TrayTitle" { return "Codex Rings" }
    "TrayText" { return "Codex Rings: {0} 5h, {1} weekly" }
    "ShowRings" { return "Show Rings" }
    "RefreshNow" { return "Refresh Now" }
    "Settings" { return "Settings" }
    "OpenLogs" { return "Open Logs" }
    "Quit" { return "Quit" }
  }
  return $Key
}

function Get-BucketRemaining {
  param($Bucket)
  if ($null -eq $Bucket) { return $null }
  if ($null -ne $Bucket.remaining_percent) {
    return [Math]::Max(0, [Math]::Min(100, [double]$Bucket.remaining_percent))
  }
  if ($null -ne $Bucket.used_percent) {
    return [Math]::Max(0, [Math]::Min(100, 100.0 - [double]$Bucket.used_percent))
  }
  return $null
}

function Get-BucketWindowSeconds {
  param($Bucket)
  if ($null -eq $Bucket) { return $null }
  if ($null -ne $Bucket.limit_window_seconds) { return [double]$Bucket.limit_window_seconds }
  if ($null -ne $Bucket.window_seconds) { return [double]$Bucket.window_seconds }
  if ($null -ne $Bucket.window_minutes) { return [double]$Bucket.window_minutes * 60.0 }
  return $null
}

function Resolve-UsageBuckets {
  param($Primary, $Secondary)
  $primaryWindow = Get-BucketWindowSeconds $Primary
  $secondaryWindow = Get-BucketWindowSeconds $Secondary

  # During events the short window can disappear and the weekly bucket may be
  # returned as primary. Keep the UI slots tied to duration, not API position.
  $primaryLooksWeekly = $null -ne $primaryWindow -and [double]$primaryWindow -ge 86400.0
  $secondaryLooksShort = $null -ne $secondaryWindow -and [double]$secondaryWindow -lt 86400.0
  if ($primaryLooksWeekly -and ($null -eq $Secondary -or $secondaryLooksShort)) {
    return [PSCustomObject]@{ Primary = $Secondary; Secondary = $Primary }
  }

  return [PSCustomObject]@{ Primary = $Primary; Secondary = $Secondary }
}

function Convert-ResetValue {
  param($ResetAt, $ResetAfterSeconds, $ObservedAt = $null)
  if ($null -ne $ResetAt) {
    try {
      $epoch = [Int64][double]$ResetAt
      if ($epoch -gt 999999999999) {
        $epoch = [Int64][Math]::Floor($epoch / 1000.0)
      }
      return [System.DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
    } catch {
      try { return [datetime]::Parse([string]$ResetAt).ToLocalTime() } catch {}
    }
  }
  if ($null -ne $ResetAfterSeconds) {
    try {
      $baseTime = if ($null -eq $ObservedAt) { Get-Date } else { [datetime]$ObservedAt }
      return $baseTime.AddSeconds([double]$ResetAfterSeconds)
    } catch {}
  }
  return $null
}

function Get-BucketResetAt {
  param($Bucket)
  if ($null -eq $Bucket) { return $null }
  $resetAt = $null
  foreach ($name in @("reset_at", "resets_at", "reset_time", "expires_at", "window_reset_at")) {
    if ($null -ne $Bucket.$name) {
      $resetAt = $Bucket.$name
      break
    }
  }
  $resetAfter = $null
  foreach ($name in @("reset_after_seconds", "seconds_until_reset", "reset_in_seconds")) {
    if ($null -ne $Bucket.$name) {
      $resetAfter = $Bucket.$name
      break
    }
  }
  return Convert-ResetValue -ResetAt $resetAt -ResetAfterSeconds $resetAfter
}

function Convert-UsagePayload {
  param($Payload, [string]$Source)
  $rate = if ($Payload.rate_limit) { $Payload.rate_limit } elseif ($Payload.rate_limits) { $Payload.rate_limits } else { $null }
  if ($null -eq $rate) { return $null }

  $rawPrimary = if ($rate.primary) { $rate.primary } elseif ($rate.primary_window) { $rate.primary_window } else { $null }
  $rawSecondary = if ($rate.secondary) { $rate.secondary } elseif ($rate.secondary_window) { $rate.secondary_window } else { $null }
  $resolved = Resolve-UsageBuckets -Primary $rawPrimary -Secondary $rawSecondary
  $primary = $resolved.Primary
  $secondary = $resolved.Secondary
  $primaryRemaining = Get-BucketRemaining $primary
  $secondaryRemaining = Get-BucketRemaining $secondary
  if ($null -eq $primaryRemaining -and $null -eq $secondaryRemaining) { return $null }

  return [PSCustomObject]@{
    Source = $Source
    Plan = $Payload.plan_type
    PrimaryRemaining = $primaryRemaining
    SecondaryRemaining = $secondaryRemaining
    PrimaryResetAt = Get-BucketResetAt $primary
    SecondaryResetAt = Get-BucketResetAt $secondary
    PrimaryWindowSeconds = Get-BucketWindowSeconds $primary
    SecondaryWindowSeconds = Get-BucketWindowSeconds $secondary
    ObservedAt = Get-Date
  }
}

function Get-LiveUsage {
  if ($NoLiveUsage) { return $null }
  if (-not (Test-Path -LiteralPath $AuthPath)) { return $null }
  try {
    $auth = Read-Utf8Text -Path $AuthPath | ConvertFrom-Json
    $token = $auth.tokens.access_token
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }
    $headers = @{ Authorization = "Bearer $token"; Accept = "application/json" }
    if (-not [string]::IsNullOrWhiteSpace([string]$auth.tokens.account_id)) {
      $headers["ChatGPT-Account-Id"] = [string]$auth.tokens.account_id
    }
    $payload = Invoke-RestMethod `
      -Uri "https://chatgpt.com/backend-api/wham/usage" `
      -Headers $headers `
      -TimeoutSec 8
    return Convert-UsagePayload -Payload $payload -Source "live"
  } catch {
    Write-AppLog "Live usage lookup failed: $($_.Exception.Message)"
    return $null
  }
}

function Get-LogUsage {
  if (-not (Test-Path -LiteralPath $LogsPath)) { return $null }
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($null -eq $python) { return $null }

  $code = @'
import json
import sqlite3
import sys
from datetime import datetime, timezone

def extract_rate_limit_json(body):
    marker = '{"type":"codex.rate_limits"'
    start = body.find(marker)
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaping = False
    for i, ch in enumerate(body[start:], start):
        if in_string:
            if escaping:
                escaping = False
            elif ch == "\\":
                escaping = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return body[start:i + 1]
    return None

def remaining(bucket):
    if not bucket:
        return None
    if bucket.get("remaining_percent") is not None:
        return max(0.0, min(100.0, float(bucket["remaining_percent"])))
    if bucket.get("used_percent") is not None:
        return max(0.0, min(100.0, 100.0 - float(bucket["used_percent"])))
    return None

def window_seconds(bucket):
    if not bucket:
        return None
    if bucket.get("limit_window_seconds") is not None:
        return float(bucket["limit_window_seconds"])
    if bucket.get("window_seconds") is not None:
        return float(bucket["window_seconds"])
    if bucket.get("window_minutes") is not None:
        return float(bucket["window_minutes"]) * 60.0
    return None

def reset_at(bucket):
    if not bucket:
        return None
    for key in ("reset_at", "resets_at", "reset_time", "expires_at", "window_reset_at"):
        if bucket.get(key) is not None:
            return bucket.get(key)
    after = reset_after_seconds(bucket)
    return None if after is None else None

def reset_after_seconds(bucket):
    if not bucket:
        return None
    for key in ("reset_after_seconds", "seconds_until_reset", "reset_in_seconds"):
        if bucket.get(key) is not None:
            return bucket.get(key)
    return None

path = sys.argv[1]
con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
try:
    row = con.execute(
        """
        SELECT feedback_log_body, ts, ts_nanos
        FROM logs
        WHERE feedback_log_body LIKE '%"type":"codex.rate_limits"%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
        """
    ).fetchone()
finally:
    con.close()

if not row:
    print("{}")
    raise SystemExit(0)

raw = extract_rate_limit_json(row[0])
if not raw:
    print("{}")
    raise SystemExit(0)

payload = json.loads(raw)
rate = payload.get("rate_limits") or payload.get("rate_limit") or {}
primary = rate.get("primary") or rate.get("primary_window")
secondary = rate.get("secondary") or rate.get("secondary_window")
print(json.dumps({
    "source": "log",
    "plan": payload.get("plan_type"),
    "primaryRemaining": remaining(primary),
    "secondaryRemaining": remaining(secondary),
    "primaryResetAt": reset_at(primary),
    "secondaryResetAt": reset_at(secondary),
    "primaryResetAfterSeconds": reset_after_seconds(primary),
    "secondaryResetAfterSeconds": reset_after_seconds(secondary),
    "primaryWindowSeconds": window_seconds(primary),
    "secondaryWindowSeconds": window_seconds(secondary),
    "observedAt": datetime.fromtimestamp(float(row[1]) + float(row[2]) / 1_000_000_000.0, tz=timezone.utc).isoformat(),
}))
'@

  try {
    $raw = & $python.Source -c $code $LogsPath
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $payload = $raw | ConvertFrom-Json
    if ($null -eq $payload.primaryRemaining -and $null -eq $payload.secondaryRemaining) { return $null }
    $observedAt = [datetime]::MinValue
    try {
      $observedAt = [DateTimeOffset]::Parse([string]$payload.observedAt, [System.Globalization.CultureInfo]::InvariantCulture).LocalDateTime
    } catch {}
    return [PSCustomObject]@{
      Source = "log"
      Plan = $payload.plan
      PrimaryRemaining = $payload.primaryRemaining
      SecondaryRemaining = $payload.secondaryRemaining
      PrimaryResetAt = Convert-ResetValue -ResetAt $payload.primaryResetAt -ResetAfterSeconds $payload.primaryResetAfterSeconds -ObservedAt $observedAt
      SecondaryResetAt = Convert-ResetValue -ResetAt $payload.secondaryResetAt -ResetAfterSeconds $payload.secondaryResetAfterSeconds -ObservedAt $observedAt
      PrimaryWindowSeconds = $payload.primaryWindowSeconds
      SecondaryWindowSeconds = $payload.secondaryWindowSeconds
      ObservedAt = $observedAt
    }
  } catch {
    Write-AppLog "Log usage lookup failed: $($_.Exception.Message)"
    return $null
  }
}

function Update-UsageState {
  $next = Get-LiveUsage
  if ($null -eq $next) { $next = Get-LogUsage }
  if ($null -ne $next) {
    $signature = "{0}|{1:N2}|{2:N2}|{3}|{4}" -f `
      $next.Source,
      $next.PrimaryRemaining,
      $next.SecondaryRemaining,
      (Format-ResetAt $next.PrimaryResetAt),
      (Format-ResetAt $next.SecondaryResetAt)
    if (-not (Test-UsageTransitionStable -Next $next -Signature $signature)) {
      return
    }
    $observedAt = if ($null -eq $next.ObservedAt) { Get-Date } else { [datetime]$next.ObservedAt }
    $nextIsStale = $next.Source -eq "log" -and (
      $observedAt -eq [datetime]::MinValue -or
      ((Get-Date) - $observedAt).TotalSeconds -ge $UsageStaleSeconds
    )
    if ($script:UsageIsStale -and -not $nextIsStale) {
      Write-AppLog "Usage data recovered."
    }
    if ($nextIsStale -and -not $script:UsageIsStale) {
      Write-AppLog ("Usage log fallback is stale: observed={0}, threshold={1:N0}s." -f (Format-ResetAt $observedAt), $UsageStaleSeconds)
    }
    $script:UsageIsStale = $nextIsStale
    $script:LastUsageSuccessAt = $observedAt
    $script:UsageState = $next
    if (-not $script:HasUsageSnapshot) {
      $script:DisplayedUsageState.PrimaryRemaining = $next.PrimaryRemaining
      $script:DisplayedUsageState.SecondaryRemaining = $next.SecondaryRemaining
      $script:HasUsageSnapshot = $true
      Write-AppLog ("Usage snapshot initialized: source={0}, 5h={1}, weekly={2}, reset5h={3}, resetWeekly={4}" -f `
        $next.Source,
        (Format-Percent $next.PrimaryRemaining),
        (Format-Percent $next.SecondaryRemaining),
        (Format-ResetAt $next.PrimaryResetAt),
        (Format-ResetAt $next.SecondaryResetAt))
      Update-RingGeometry
    } elseif ($signature -ne $script:LastUsageSignature) {
      Write-AppLog ("Usage target updated: source={0}, 5h={1}, weekly={2}, reset5h={3}, resetWeekly={4}" -f `
        $next.Source,
        (Format-Percent $next.PrimaryRemaining),
        (Format-Percent $next.SecondaryRemaining),
        (Format-ResetAt $next.PrimaryResetAt),
        (Format-ResetAt $next.SecondaryResetAt))
      Set-FrameTimerInterval -Fast $true
    }
    $script:LastUsageSignature = $signature
    Update-TrayText
    [void](Update-ReadoutText -Force)
    Update-StaleIndicator
    return
  }

  $now = Get-Date
  $shouldMarkStale = -not $script:HasUsageSnapshot -or (
    $script:LastUsageSuccessAt -ne [datetime]::MinValue -and
    ($now - $script:LastUsageSuccessAt).TotalSeconds -ge $UsageStaleSeconds
  )
  if ($shouldMarkStale -and -not $script:UsageIsStale) {
    $script:UsageIsStale = $true
    Write-AppLog ("Usage data is stale: no successful live or log update for {0:N0}s." -f $UsageStaleSeconds)
    Update-TrayText
    [void](Update-ReadoutText -Force)
    Update-StaleIndicator
  }
}

function Read-PetRect {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    $script:LastStateWriteTimeUtc = [datetime]::MinValue
    $script:CachedPetRect = $null
    return $null
  }
  try {
    $stateItem = Get-Item -LiteralPath $StatePath -ErrorAction Stop
    if ($stateItem.LastWriteTimeUtc -eq $script:LastStateWriteTimeUtc) {
      return $script:CachedPetRect
    }
    $script:LastStateWriteTimeUtc = $stateItem.LastWriteTimeUtc
    $root = Read-Utf8Text -Path $StatePath | ConvertFrom-Json
    # The pet is the source of truth. Stale bounds can remain in state.json after
    # the pet (or Codex itself) closes, so only an explicit open=true may drive
    # the companion overlay.
    if ($root.'electron-avatar-overlay-open' -isnot [bool] -or -not $root.'electron-avatar-overlay-open') {
      $script:CachedPetRect = $null
      return $null
    }
    $bounds = $root.'electron-avatar-overlay-bounds'
    if ($null -eq $bounds) {
      $script:CachedPetRect = $null
      return $null
    }
    $mascot = if ($bounds.mascot) { $bounds.mascot } elseif ($bounds.anchor) { $bounds.anchor } else { $null }
    if ($null -eq $mascot) {
      $script:CachedPetRect = $null
      return $null
    }
    $script:CachedPetRect = [PSCustomObject]@{
      X = [double]$bounds.x + [double]$mascot.left
      Y = [double]$bounds.y + [double]$mascot.top
      Width = [double]$mascot.width
      Height = [double]$mascot.height
    }
    return $script:CachedPetRect
  } catch {
    $script:LastStateWriteTimeUtc = [datetime]::MinValue
    $script:CachedPetRect = $null
    Write-AppLog "Pet bounds lookup failed: $($_.Exception.Message)"
    return $null
  }
}

function New-ArcGeometry {
  param([double]$Center, [double]$Radius, [double]$Percent, [double]$StrokeThickness)
  $percent = [Math]::Max(0, [Math]::Min(100, $Percent))
  if ($percent -le 0.1) { return [System.Windows.Media.Geometry]::Empty }
  if ($percent -ge 99.9) {
    $fullCircle = [System.Windows.Media.EllipseGeometry]::new(
      [System.Windows.Point]::new($Center, $Center),
      $Radius,
      $Radius
    )
    $fullCircle.Freeze()
    return $fullCircle
  }

  $targetSweepDeg = 360.0 * ($percent / 100.0)
  # 둥근 cap이 양 끝에 더하는 길이를 보정해 화면에 보이는 각도를 실제 비율과 맞춘다.
  $capTotalDeg = if ($Radius -gt 0 -and $StrokeThickness -gt 0) {
    ($StrokeThickness / $Radius) * 180.0 / [Math]::PI
  } else {
    0.0
  }
  $geometrySweepDeg = [Math]::Max(0.05, $targetSweepDeg - $capTotalDeg)
  $capHalfDeg = [Math]::Min($targetSweepDeg / 2.0, $capTotalDeg / 2.0)
  $startDeg = -90.0 + $capHalfDeg
  $endDeg = $startDeg + $geometrySweepDeg
  $startRad = [Math]::PI * $startDeg / 180.0
  $endRad = [Math]::PI * $endDeg / 180.0
  $start = [System.Windows.Point]::new(
    $Center + [Math]::Cos($startRad) * $Radius,
    $Center + [Math]::Sin($startRad) * $Radius
  )
  $end = [System.Windows.Point]::new(
    $Center + [Math]::Cos($endRad) * $Radius,
    $Center + [Math]::Sin($endRad) * $Radius
  )
  $geometry = [System.Windows.Media.StreamGeometry]::new()
  $ctx = $geometry.Open()
  $ctx.BeginFigure($start, $false, $false)
  $ctx.ArcTo(
    $end,
    [System.Windows.Size]::new($Radius, $Radius),
    0,
    [bool]($geometrySweepDeg -gt 180.0),
    [System.Windows.Media.SweepDirection]::Clockwise,
    $true,
    $false
  )
  $ctx.Close()
  $geometry.Freeze()
  return $geometry
}

function Set-EllipseBounds {
  param($Ellipse, [double]$Center, [double]$Radius)
  $Ellipse.Width = $Radius * 2
  $Ellipse.Height = $Radius * 2
  [System.Windows.Controls.Canvas]::SetLeft($Ellipse, $Center - $Radius)
  [System.Windows.Controls.Canvas]::SetTop($Ellipse, $Center - $Radius)
}

function Move-RingBehindCodex {
  if ($null -eq $script:Window -or -not $script:Window.IsVisible) {
    return
  }

  $now = Get-Date
  if (($now - $script:LastZOrderAt).TotalMilliseconds -lt 2000) {
    return
  }
  $script:LastZOrderAt = $now

  $handle = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
  if ($handle -eq [IntPtr]::Zero) {
    return
  }

  $left = [int][Math]::Floor([double]$script:Window.Left)
  $top = [int][Math]::Floor([double]$script:Window.Top)
  $right = [int][Math]::Ceiling([double]$script:Window.Left + [double]$script:Window.Width)
  $bottom = [int][Math]::Ceiling([double]$script:Window.Top + [double]$script:Window.Height)
  $front = [CodexPetLimitRingNative]::FindOverlappingCodexWindow($handle, $left, $top, $right, $bottom)
  if ($front -ne [IntPtr]::Zero) {
    [CodexPetLimitRingNative]::PlaceBehind($handle, $front)
  }
}

function Optimize-ProcessFootprint {
  try {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    [void][CodexPetLimitRingNative]::TrimWorkingSet()
  } catch {
    Write-AppLog "Working set trim failed: $($_.Exception.Message)"
  }
}

function Format-Percent {
  param($Value)
  if ($null -eq $Value) { return "-" }
  return ("{0:N0}%" -f [double]$Value)
}

function Format-ResetAt {
  param($Value)
  if ($null -eq $Value) { return "--" }
  try { return ([datetime]$Value).ToString("yyyy-MM-dd HH:mm") } catch { return [string]$Value }
}

function Format-Duration {
  param($Seconds)
  if ($null -eq $Seconds) { return "--" }
  $total = [int][Math]::Max(0, [Math]::Ceiling([double]$Seconds))
  $ko = Test-KoreanLanguage
  if ($total -ge 86400) {
    $days = [int][Math]::Floor($total / 86400)
    $hours = [int][Math]::Floor(($total % 86400) / 3600)
    if ($ko) { return (Expand-UnicodeText "{0}\uC77C {1}\uC2DC\uAC04") -f $days, $hours }
    return "{0}d {1}h" -f $days, $hours
  }
  if ($total -ge 3600) {
    $hours = [int][Math]::Floor($total / 3600)
    $minutes = [int][Math]::Floor(($total % 3600) / 60)
    if ($ko) { return (Expand-UnicodeText "{0}\uC2DC\uAC04 {1}\uBD84") -f $hours, $minutes }
    return "{0}h {1}m" -f $hours, $minutes
  }
  if ($total -ge 60) {
    $minutes = [int][Math]::Floor($total / 60)
    $seconds = $total % 60
    if ($ko) { return (Expand-UnicodeText "{0}\uBD84 {1}\uCD08") -f $minutes, $seconds }
    return "{0}m {1}s" -f $minutes, $seconds
  }
  if ($ko) { return (Expand-UnicodeText "{0}\uCD08") -f $total }
  return "{0}s" -f $total
}

function New-PolylineGeometry {
  param([System.Windows.Point[]]$Points)
  if ($null -eq $Points -or $Points.Count -lt 2) { return [System.Windows.Media.Geometry]::Empty }
  $geometry = [System.Windows.Media.StreamGeometry]::new()
  $ctx = $geometry.Open()
  $ctx.BeginFigure($Points[0], $false, $false)
  for ($i = 1; $i -lt $Points.Count; $i++) {
    $ctx.LineTo($Points[$i], $true, $false)
  }
  $ctx.Close()
  $geometry.Freeze()
  return $geometry
}

function New-ProgressPolylineGeometry {
  param([System.Windows.Point[]]$Points, [double]$Percent)
  if ($null -eq $Points -or $Points.Count -lt 2) { return [System.Windows.Media.Geometry]::Empty }
  $ratio = [Math]::Max(0.0, [Math]::Min(1.0, $Percent / 100.0))
  if ($ratio -le 0.001) { return [System.Windows.Media.Geometry]::Empty }
  $lengths = @()
  $totalLength = 0.0
  for ($i = 1; $i -lt $Points.Count; $i++) {
    $dx = [double]$Points[$i].X - [double]$Points[$i - 1].X
    $dy = [double]$Points[$i].Y - [double]$Points[$i - 1].Y
    $segmentLength = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $lengths += $segmentLength
    $totalLength += $segmentLength
  }
  if ($totalLength -le 0.001) { return [System.Windows.Media.Geometry]::Empty }
  $remainingLength = $totalLength * $ratio
  $geometry = [System.Windows.Media.StreamGeometry]::new()
  $ctx = $geometry.Open()
  $ctx.BeginFigure($Points[0], $false, $false)
  for ($i = 1; $i -lt $Points.Count -and $remainingLength -gt 0.001; $i++) {
    $segmentLength = [double]$lengths[$i - 1]
    if ($remainingLength -ge $segmentLength) {
      $ctx.LineTo($Points[$i], $true, $false)
      $remainingLength -= $segmentLength
      continue
    }
    $segmentRatio = $remainingLength / [Math]::Max(0.001, $segmentLength)
    $x = [double]$Points[$i - 1].X + ([double]$Points[$i].X - [double]$Points[$i - 1].X) * $segmentRatio
    $y = [double]$Points[$i - 1].Y + ([double]$Points[$i].Y - [double]$Points[$i - 1].Y) * $segmentRatio
    $ctx.LineTo([System.Windows.Point]::new($x, $y), $true, $false)
    $remainingLength = 0.0
  }
  $ctx.Close()
  $geometry.Freeze()
  return $geometry
}

function New-PotionOrbGeometry {
  param([double]$CenterX, [double]$CenterY, [double]$Radius)
  $radius = [Math]::Max(12.0, $Radius)
  $geometry = [System.Windows.Media.EllipseGeometry]::new(
    [System.Windows.Point]::new($CenterX, $CenterY),
    $radius,
    $radius
  )
  $geometry.Freeze()
  return $geometry
}

function New-PotionDiamondGeometry {
  param([double]$CenterX, [double]$CenterY, [double]$Size)
  $geometry = [System.Windows.Media.StreamGeometry]::new()
  $ctx = $geometry.Open()
  $ctx.BeginFigure([System.Windows.Point]::new($CenterX, $CenterY - $Size), $true, $true)
  $ctx.LineTo([System.Windows.Point]::new($CenterX + $Size * 0.62, $CenterY), $true, $false)
  $ctx.LineTo([System.Windows.Point]::new($CenterX, $CenterY + $Size), $true, $false)
  $ctx.LineTo([System.Windows.Point]::new($CenterX - $Size * 0.62, $CenterY), $true, $false)
  $ctx.Close()
  $geometry.Freeze()
  return $geometry
}

function New-PotionFrameGeometry {
  param([double]$CenterX, [double]$CenterY, [double]$Radius)
  $radius = [Math]::Max(12.0, $Radius)
  $outer = New-PotionOrbGeometry -CenterX $CenterX -CenterY $CenterY -Radius ($radius + 5.5)
  $inner = New-PotionOrbGeometry -CenterX $CenterX -CenterY $CenterY -Radius ($radius + 2.0)
  $ring = [System.Windows.Media.CombinedGeometry]::new(
    [System.Windows.Media.GeometryCombineMode]::Exclude,
    $outer,
    $inner
  )
  $ornamentDistance = $radius + 7.0
  $ornamentSize = [Math]::Max(5.0, $radius * 0.24)
  $group = [System.Windows.Media.GeometryGroup]::new()
  $group.Children.Add($ring) | Out-Null
  $group.Children.Add((New-PotionDiamondGeometry -CenterX $CenterX -CenterY ($CenterY - $ornamentDistance) -Size $ornamentSize)) | Out-Null
  $group.Children.Add((New-PotionDiamondGeometry -CenterX $CenterX -CenterY ($CenterY + $ornamentDistance) -Size $ornamentSize)) | Out-Null
  $group.Children.Add((New-PotionDiamondGeometry -CenterX ($CenterX - $ornamentDistance) -CenterY $CenterY -Size $ornamentSize)) | Out-Null
  $group.Children.Add((New-PotionDiamondGeometry -CenterX ($CenterX + $ornamentDistance) -CenterY $CenterY -Size $ornamentSize)) | Out-Null
  $group.Freeze()
  return $group
}

function New-PotionFacetGeometry {
  param([double]$CenterX, [double]$CenterY, [double]$Radius)
  $radius = [Math]::Max(12.0, $Radius) * 0.92
  $hub = [System.Windows.Point]::new($CenterX - $radius * 0.13, $CenterY - $radius * 0.08)
  $points = @(
    [System.Windows.Point]::new($CenterX, $CenterY - $radius),
    [System.Windows.Point]::new($CenterX + $radius * 0.7, $CenterY - $radius * 0.62),
    [System.Windows.Point]::new($CenterX + $radius, $CenterY),
    [System.Windows.Point]::new($CenterX + $radius * 0.58, $CenterY + $radius * 0.72),
    [System.Windows.Point]::new($CenterX, $CenterY + $radius),
    [System.Windows.Point]::new($CenterX - $radius * 0.72, $CenterY + $radius * 0.58),
    [System.Windows.Point]::new($CenterX - $radius, $CenterY),
    [System.Windows.Point]::new($CenterX - $radius * 0.62, $CenterY - $radius * 0.72)
  )
  $geometry = [System.Windows.Media.StreamGeometry]::new()
  $ctx = $geometry.Open()
  foreach ($point in $points) {
    $ctx.BeginFigure($hub, $false, $false)
    $ctx.LineTo($point, $true, $false)
  }
  for ($i = 0; $i -lt $points.Count; $i++) {
    $ctx.BeginFigure($points[$i], $false, $false)
    $ctx.LineTo($points[($i + 1) % $points.Count], $true, $false)
  }
  $ctx.Close()
  $geometry.Freeze()
  return $geometry
}

function New-PotionGemBrush {
  param([System.Windows.Media.SolidColorBrush]$BaseBrush)
  $color = $BaseBrush.Color
  $light = [System.Windows.Media.Color]::FromArgb(
    $color.A,
    [byte][Math]::Min(255, [int]$color.R + 70),
    [byte][Math]::Min(255, [int]$color.G + 70),
    [byte][Math]::Min(255, [int]$color.B + 70)
  )
  $dark = [System.Windows.Media.Color]::FromArgb(
    $color.A,
    [byte][Math]::Max(0, [int]$color.R * 0.42),
    [byte][Math]::Max(0, [int]$color.G * 0.42),
    [byte][Math]::Max(0, [int]$color.B * 0.42)
  )
  $brush = [System.Windows.Media.LinearGradientBrush]::new()
  $brush.StartPoint = [System.Windows.Point]::new(0.12, 0.08)
  $brush.EndPoint = [System.Windows.Point]::new(0.88, 0.92)
  $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($light, 0.0))
  $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($color, 0.46))
  $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($dark, 1.0))
  $brush.Freeze()
  return $brush
}

function New-FrozenBitmapImage {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Missing pixel potion asset: $Path" }
  $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
  $bitmap.BeginInit()
  $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bitmap.UriSource = [Uri]::new([System.IO.Path]::GetFullPath($Path))
  $bitmap.EndInit()
  $bitmap.Freeze()
  return $bitmap
}

function New-PixelPotionTextBlock {
  param(
    [double]$FontSize,
    [System.Windows.Media.Brush]$Foreground,
    [double]$Top,
    [double]$Left = 0.0
  )
  $text = [System.Windows.Controls.TextBlock]::new()
  $text.Width = 68.0
  $text.Height = 16.0
  $text.FontFamily = [System.Windows.Media.FontFamily]::new("Arial Black")
  $text.FontWeight = [System.Windows.FontWeights]::ExtraBold
  $text.FontSize = $FontSize
  $text.Foreground = $Foreground
  $text.TextAlignment = [System.Windows.TextAlignment]::Center
  $text.IsHitTestVisible = $false
  $text.SnapsToDevicePixels = $true
  [System.Windows.Media.TextOptions]::SetTextFormattingMode($text, [System.Windows.Media.TextFormattingMode]::Display)
  [System.Windows.Media.TextOptions]::SetTextRenderingMode($text, [System.Windows.Media.TextRenderingMode]::Aliased)
  [System.Windows.Controls.Canvas]::SetLeft($text, $Left)
  [System.Windows.Controls.Canvas]::SetTop($text, $Top)
  return $text
}

function New-PixelPotionVisual {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [double]$Width = 68.0,
    [double]$Height = 73.0,
    $FrameBitmap = $script:PotionPixelFrameBitmap,
    $MaskBrush = $script:PotionPixelMaskBrush,
    [double]$ValueTop = 31.0,
    [double]$LabelTop = 59.0,
    [double]$ChamberTop = 17.0,
    [double]$ChamberBottom = 57.0
  )

  $canvas = [System.Windows.Controls.Canvas]::new()
  $canvas.Width = $Width
  $canvas.Height = $Height
  $canvas.SnapsToDevicePixels = $true
  $canvas.UseLayoutRounding = $true
  $canvas.IsHitTestVisible = $false

  $backdrop = [System.Windows.Shapes.Rectangle]::new()
  $backdrop.Width = $Width
  $backdrop.Height = $Height
  $backdrop.Fill = New-StyleBrush 238 @(19, 20, 20)
  $backdrop.OpacityMask = $MaskBrush

  $liquid = [System.Windows.Shapes.Rectangle]::new()
  $liquid.Width = $Width
  $liquid.Height = $Height
  $liquid.OpacityMask = $MaskBrush

  $frame = [System.Windows.Controls.Image]::new()
  $frame.Width = $Width
  $frame.Height = $Height
  $frame.Source = $FrameBitmap
  $frame.Stretch = [System.Windows.Media.Stretch]::Fill
  $frame.SnapsToDevicePixels = $true
  [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($frame, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)

  $shadowBrush = New-StyleBrush 255 @(0, 0, 0)
  $valueShadows = @(
    (New-PixelPotionTextBlock -FontSize 11.5 -Foreground $shadowBrush -Top $ValueTop -Left -1.0),
    (New-PixelPotionTextBlock -FontSize 11.5 -Foreground $shadowBrush -Top $ValueTop -Left 1.0),
    (New-PixelPotionTextBlock -FontSize 11.5 -Foreground $shadowBrush -Top ($ValueTop - 1.0)),
    (New-PixelPotionTextBlock -FontSize 11.5 -Foreground $shadowBrush -Top ($ValueTop + 1.0))
  )
  foreach ($textBlock in $valueShadows) { $textBlock.Width = $Width }
  $valueText = New-PixelPotionTextBlock -FontSize 11.5 -Foreground (New-StyleBrush 255 @(255, 255, 255)) -Top $ValueTop
  $labelText = New-PixelPotionTextBlock -FontSize 7.5 -Foreground (New-StyleBrush 255 @(255, 255, 255)) -Top $LabelTop
  $valueText.Width = $Width
  $labelText.Width = $Width
  $labelText.Text = $Label

  $canvas.Children.Add($backdrop) | Out-Null
  $canvas.Children.Add($liquid) | Out-Null
  $canvas.Children.Add($frame) | Out-Null
  foreach ($shadow in $valueShadows) { $canvas.Children.Add($shadow) | Out-Null }
  $canvas.Children.Add($valueText) | Out-Null
  $canvas.Children.Add($labelText) | Out-Null

  return [PSCustomObject]@{
    Container = $canvas
    Backdrop = $backdrop
    Liquid = $liquid
    Frame = $frame
    ValueShadows = $valueShadows
    ValueText = $valueText
    LabelText = $labelText
    Width = $Width
    Height = $Height
    ChamberTop = $ChamberTop
    ChamberBottom = $ChamberBottom
  }
}

function Set-PixelPotionVisual {
  param(
    $Visual,
    [double]$Remaining,
    [System.Windows.Media.Brush]$LiquidBrush,
    [double]$Scale,
    [double]$Left,
    [double]$Top
  )
  if ($null -eq $Visual) { return }
  $ratio = [Math]::Max(0.0, [Math]::Min(1.0, $Remaining / 100.0))
  $chamberTop = [double]$Visual.ChamberTop
  $chamberBottom = [double]$Visual.ChamberBottom
  $fillTop = $chamberBottom - ($chamberBottom - $chamberTop) * $ratio
  $clip = [System.Windows.Media.RectangleGeometry]::new(
    [System.Windows.Rect]::new(0.0, $fillTop, [double]$Visual.Width, $chamberBottom - $fillTop)
  )
  $clip.Freeze()
  $Visual.Liquid.Clip = $clip
  $Visual.Liquid.Fill = $LiquidBrush
  $text = Format-Percent $Remaining
  foreach ($shadow in $Visual.ValueShadows) { $shadow.Text = $text }
  $Visual.ValueText.Text = $text
  $Visual.Container.RenderTransform = [System.Windows.Media.ScaleTransform]::new($Scale, $Scale)
  [System.Windows.Controls.Canvas]::SetLeft($Visual.Container, $Left)
  [System.Windows.Controls.Canvas]::SetTop($Visual.Container, $Top)
}

function Format-ResetDetail {
  param($ResetAt)
  $ko = Test-KoreanLanguage
  if ($null -eq $ResetAt) {
    if ($ko) { return (Expand-UnicodeText "\uC7AC\uC124\uC815 --") }
    return "Reset --"
  }
  $reset = [datetime]$ResetAt
  $remaining = ($reset - (Get-Date)).TotalSeconds
  $timeText = if ($reset.Date -eq (Get-Date).Date) {
    $reset.ToString("HH:mm")
  } else {
    if ($ko) {
      $reset.ToString((Expand-UnicodeText "M\uC6D4 d\uC77C HH:mm"), [System.Globalization.CultureInfo]::GetCultureInfo("ko-KR"))
    } else {
      $reset.ToString("MMM d HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    }
  }
  if ($ko) { return (Expand-UnicodeText "\uC7AC\uC124\uC815 {0} ({1})") -f (Format-Duration $remaining), $timeText }
  return "Reset {0} ({1})" -f (Format-Duration $remaining), $timeText
}

function Format-WindowLabel {
  param($Seconds, [string]$Fallback)
  if ($null -eq $Seconds) { return $Fallback }
  $ko = Test-KoreanLanguage
  $value = [double]$Seconds
  if ([Math]::Abs($value - 18000.0) -lt 180.0) { return "5h" }
  if ([Math]::Abs($value - 604800.0) -lt 3600.0) {
    if ($ko) { return (Expand-UnicodeText "\uC8FC\uAC04") }
    return "Weekly"
  }
  if ($value -ge 86400.0) {
    if ($ko) { return (Expand-UnicodeText "{0:N0}\uC77C") -f ($value / 86400.0) }
    return "{0:N0}d" -f ($value / 86400.0)
  }
  if ($value -ge 3600.0) {
    if ($ko) { return (Expand-UnicodeText "{0:N0}\uC2DC\uAC04") -f ($value / 3600.0) }
    return "{0:N0}h" -f ($value / 3600.0)
  }
  if ($ko) { return (Expand-UnicodeText "{0:N0}\uBD84") -f ($value / 60.0) }
  return "{0:N0}m" -f ($value / 60.0)
}

function Format-PotionResetMoment {
  param([ValidateSet("Outer", "Inner")][string]$Ring, $ResetAt)
  $ko = Test-KoreanLanguage
  if ($null -eq $ResetAt) {
    if ($ko) { return (Expand-UnicodeText "\uCD08\uAE30\uD654 --") }
    return "Reset --"
  }
  $reset = [datetime]$ResetAt
  if ($Ring -eq "Outer") {
    $moment = $reset.ToString("HH:mm")
  } elseif ($ko) {
    $moment = $reset.ToString((Expand-UnicodeText "M\uC6D4 d\uC77C HH:mm"), [System.Globalization.CultureInfo]::GetCultureInfo("ko-KR"))
  } else {
    $moment = $reset.ToString("MMM d HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($ko) { return (Expand-UnicodeText "\uCD08\uAE30\uD654 {0}") -f $moment }
  return "Reset {0}" -f $moment
}

function Format-PotionRemainingTime {
  param($ResetAt, $Now = (Get-Date))
  $ko = Test-KoreanLanguage
  if ($null -eq $ResetAt) {
    if ($ko) { return (Expand-UnicodeText "\uB0A8\uC740 \uC2DC\uAC04 --") }
    return "Time left --"
  }
  $remaining = ([datetime]$ResetAt - [datetime]$Now).TotalSeconds
  if ($ko) { return (Expand-UnicodeText "\uB0A8\uC740 \uC2DC\uAC04 {0}") -f (Format-Duration $remaining) }
  return "Time left {0}" -f (Format-Duration $remaining)
}

function Get-PotionReadoutText {
  param([ValidateSet("Outer", "Inner")][string]$Ring)
  $ko = Test-KoreanLanguage
  if ($Ring -eq "Outer") {
    if ($ko) {
      return (Expand-UnicodeText "5h  {0} \uB0A8\uC74C`n{1}`n{2}") -f `
        (Format-Percent $script:UsageState.PrimaryRemaining),
        (Format-PotionResetMoment -Ring "Outer" -ResetAt $script:UsageState.PrimaryResetAt),
        (Format-PotionRemainingTime -ResetAt $script:UsageState.PrimaryResetAt)
    }
    return "5h  {0} left`n{1}`n{2}" -f `
      (Format-Percent $script:UsageState.PrimaryRemaining),
      (Format-PotionResetMoment -Ring "Outer" -ResetAt $script:UsageState.PrimaryResetAt),
      (Format-PotionRemainingTime -ResetAt $script:UsageState.PrimaryResetAt)
  }

  $weekly = if ($ko) { (Expand-UnicodeText "\uC8FC\uAC04") } else { "Weekly" }
  if ($ko) {
    return (Expand-UnicodeText "{0}  {1} \uB0A8\uC74C`n{2}`n{3}") -f `
      $weekly,
      (Format-Percent $script:UsageState.SecondaryRemaining),
      (Format-PotionResetMoment -Ring "Inner" -ResetAt $script:UsageState.SecondaryResetAt),
      (Format-PotionRemainingTime -ResetAt $script:UsageState.SecondaryResetAt)
  }
  return "{0}  {1} left`n{2}`n{3}" -f `
    $weekly,
    (Format-Percent $script:UsageState.SecondaryRemaining),
    (Format-PotionResetMoment -Ring "Inner" -ResetAt $script:UsageState.SecondaryResetAt),
    (Format-PotionRemainingTime -ResetAt $script:UsageState.SecondaryResetAt)
}

function Get-RingReadoutText {
  param([ValidateSet("Outer", "Inner")][string]$Ring)
  if ($script:Style.AppearanceMode -in @("potions", "heart_potions")) {
    return Get-PotionReadoutText -Ring $Ring
  }
  $ko = Test-KoreanLanguage
  if ($Ring -eq "Outer") {
    $label = Format-WindowLabel -Seconds $script:UsageState.PrimaryWindowSeconds -Fallback "5h"
    if ($ko) {
      return (Expand-UnicodeText "{0} \uD55C\uB3C4  {1} \uB0A8\uC74C`n{2}") -f `
        $label,
        (Format-Percent $script:UsageState.PrimaryRemaining),
        (Format-ResetDetail $script:UsageState.PrimaryResetAt)
    }
    return "{0} limit  {1} left`n{2}" -f `
      $label,
      (Format-Percent $script:UsageState.PrimaryRemaining),
      (Format-ResetDetail $script:UsageState.PrimaryResetAt)
  }

  $weeklyFallback = if ($ko) { (Expand-UnicodeText "\uC8FC\uAC04") } else { "Weekly" }
  $label = Format-WindowLabel -Seconds $script:UsageState.SecondaryWindowSeconds -Fallback $weeklyFallback
  if ($ko) {
    return (Expand-UnicodeText "{0}  {1} \uB0A8\uC74C`n{2}") -f `
      $label,
      (Format-Percent $script:UsageState.SecondaryRemaining),
      (Format-ResetDetail $script:UsageState.SecondaryResetAt)
  }
  return "{0}  {1} left`n{2}" -f `
    $label,
    (Format-Percent $script:UsageState.SecondaryRemaining),
    (Format-ResetDetail $script:UsageState.SecondaryResetAt)
}

function Get-UsageFreshnessText {
  if (-not $script:UsageIsStale) { return "" }
  $ko = Test-KoreanLanguage
  if ($script:LastUsageSuccessAt -eq [datetime]::MinValue) {
    if ($ko) { return (Expand-UnicodeText "\uC624\uD504\uB77C\uC778 \u00B7 \uC0AC\uC6A9\uB7C9 \uB370\uC774\uD130 \uC5C6\uC74C") }
    return "Offline · no usage data"
  }
  $time = ([datetime]$script:LastUsageSuccessAt).ToString("HH:mm:ss")
  if ($ko) { return (Expand-UnicodeText "\uC624\uD504\uB77C\uC778 \u00B7 \uB9C8\uC9C0\uB9C9 \uAC31\uC2E0 {0}") -f $time }
  return "Offline · last updated {0}" -f $time
}

function Update-StaleIndicator {
  if ($null -eq $script:StaleBadgeBorder -or $null -eq $script:Window) { return }
  $visible = $script:UsageIsStale -and $script:RingVisualsVisible -and $script:Window.IsVisible
  if (-not $visible) {
    $script:StaleBadgeBorder.Visibility = [System.Windows.Visibility]::Collapsed
    return
  }
  $script:StaleBadgeText.Text = Get-UsageFreshnessText
  $script:StaleBadgeBorder.Visibility = [System.Windows.Visibility]::Visible
  $script:StaleBadgeBorder.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $left = [Math]::Max(4.0, ([double]$script:Window.Width - [double]$script:StaleBadgeBorder.DesiredSize.Width) / 2.0)
  [System.Windows.Controls.Canvas]::SetLeft($script:StaleBadgeBorder, $left)
  [System.Windows.Controls.Canvas]::SetTop($script:StaleBadgeBorder, 8.0)
}

function Update-ReadoutText {
  param([switch]$Force)
  $now = Get-Date
  if (-not $Force -and ($now - $script:LastReadoutRefreshAt).TotalMilliseconds -lt 1000) {
    return $false
  }
  $freshness = Get-UsageFreshnessText
  if ($null -ne $script:OuterReadoutText) {
    $text = Get-RingReadoutText -Ring "Outer"
    $script:OuterReadoutText.Text = if ([string]::IsNullOrWhiteSpace($freshness)) { $text } else { "$text`n$freshness" }
  }
  if ($null -ne $script:InnerReadoutText) {
    $text = Get-RingReadoutText -Ring "Inner"
    $script:InnerReadoutText.Text = if ([string]::IsNullOrWhiteSpace($freshness)) { $text } else { "$text`n$freshness" }
  }
  $script:LastReadoutRefreshAt = $now
  return $true
}

function Hide-RingReadouts {
  $script:LastHoverSignature = ""
  if ($null -ne $script:OuterReadoutBorder) {
    $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  }
  if ($null -ne $script:InnerReadoutBorder) {
    $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  }
  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  if ($null -ne $script:InnerReadoutWindow -and $script:InnerReadoutWindow.IsVisible) {
    $script:InnerReadoutWindow.Hide()
  }
}

function Test-UsageTransitionStable {
  param($Next, [string]$Signature)
  if (-not $script:HasUsageSnapshot) { return $true }

  $current = $script:UsageState
  $now = Get-Date
  $suspicious = $false
  foreach ($pair in @(
    @($current.PrimaryRemaining, $Next.PrimaryRemaining, $current.PrimaryResetAt, $Next.PrimaryResetAt),
    @($current.SecondaryRemaining, $Next.SecondaryRemaining, $current.SecondaryResetAt, $Next.SecondaryResetAt)
  )) {
    if ($null -eq $pair[0] -or $null -eq $pair[1]) { continue }
    $currentRemaining = [double]$pair[0]
    $nextRemaining = [double]$pair[1]
    $currentReset = if ($null -ne $pair[2]) { [datetime]$pair[2] } else { $null }
    $nextReset = if ($null -ne $pair[3]) { [datetime]$pair[3] } else { $null }

    # 같은 사용 주기에서 잔여량이 갑자기 복구되는 응답은 두 번 연속 확인한다.
    if ($nextRemaining -gt ($currentRemaining + 3.0) -and $null -ne $currentReset -and $currentReset -gt $now) {
      $suspicious = $true
    }
    # 재설정 시각이 과거 방향으로 크게 이동하는 응답은 일시적인 서버 값일 수 있다.
    if (
      $null -ne $currentReset -and
      $null -ne $nextReset -and
      $currentReset -gt $now -and
      $nextReset -lt $currentReset.AddMinutes(-5) -and
      $nextRemaining -ge ($currentRemaining - 1.0)
    ) {
      $suspicious = $true
    }
  }

  if (-not $suspicious) {
    $script:PendingUsageSignature = ""
    $script:PendingUsageCount = 0
    return $true
  }
  if ($script:PendingUsageSignature -eq $Signature) {
    $script:PendingUsageCount += 1
  } else {
    $script:PendingUsageSignature = $Signature
    $script:PendingUsageCount = 1
  }
  if ($script:PendingUsageCount -ge 2) {
    Write-AppLog "Usage transition confirmed after repeated response."
    $script:PendingUsageSignature = ""
    $script:PendingUsageCount = 0
    return $true
  }

  Write-AppLog ("Usage transition deferred: candidate 5h={0}, weekly={1}, reset5h={2}, resetWeekly={3}" -f `
    (Format-Percent $Next.PrimaryRemaining),
    (Format-Percent $Next.SecondaryRemaining),
    (Format-ResetAt $Next.PrimaryResetAt),
    (Format-ResetAt $Next.SecondaryResetAt))
  return $false
}

function Set-RingShapesVisibility {
  param([System.Windows.Visibility]$Visibility)
  $ringShapes = @($script:OuterTrack, $script:InnerTrack, $script:OuterArc, $script:InnerArc)
  $alternativeShapes = @($script:OuterAltTrack, $script:InnerAltTrack, $script:OuterAltValue, $script:InnerAltValue)
  $potionShapes = @(
    $script:OuterPixelPotion.Container,
    $script:InnerPixelPotion.Container
  )
  $heartPotionShapes = @(
    $script:OuterHeartPotion.Container,
    $script:InnerHeartPotion.Container
  )
  foreach ($shape in @($ringShapes + $alternativeShapes + $potionShapes + $heartPotionShapes)) {
    if ($null -ne $shape) {
      $shape.Visibility = [System.Windows.Visibility]::Collapsed
    }
  }
  if ($Visibility -ne [System.Windows.Visibility]::Visible) {
    Update-StaleIndicator
    return
  }
  $activeShapes = switch ($script:Style.AppearanceMode) {
    "rings" { $ringShapes }
    "potions" { $potionShapes }
    "heart_potions" { $heartPotionShapes }
    default { $alternativeShapes }
  }
  foreach ($shape in $activeShapes) {
    if ($null -ne $shape) { $shape.Visibility = [System.Windows.Visibility]::Visible }
  }
  Update-StaleIndicator
}

function Start-RingOpacityAnimation {
  param([double]$TargetOpacity, [double]$DurationMs, [bool]$HideWhenDone)
  if ($null -eq $script:Window) { return }

  $script:RingAnimationToken += 1
  $animationToken = $script:RingAnimationToken
  $duration = [Math]::Max(0.0, [double]$DurationMs)

  if ($duration -le 0.0) {
    $script:Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:Window.Opacity = $TargetOpacity
    if ($HideWhenDone) {
      Hide-RingReadouts
      Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)
      if ($script:Window.IsVisible) { $script:Window.Hide() }
    }
    return
  }

  $animation = [System.Windows.Media.Animation.DoubleAnimation]::new()
  $animation.From = [double]$script:Window.Opacity
  $animation.To = $TargetOpacity
  $animation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($duration))
  $animation.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
  $easing = [System.Windows.Media.Animation.QuadraticEase]::new()
  $easing.EasingMode = if ($TargetOpacity -gt [double]$script:Window.Opacity) {
    [System.Windows.Media.Animation.EasingMode]::EaseOut
  } else {
    [System.Windows.Media.Animation.EasingMode]::EaseIn
  }
  $animation.EasingFunction = $easing
  $animation.Add_Completed({
    if ($script:RingAnimationToken -ne $animationToken) { return }
    $script:Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:Window.Opacity = $TargetOpacity
    if ($HideWhenDone -and -not $script:RingVisualsVisible) {
      Hide-RingReadouts
      Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)
      if ($script:Window.IsVisible) { $script:Window.Hide() }
    }
  })
  $script:Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)
}

function Set-RingVisualsVisible {
  param([bool]$Visible)
  if ($script:RingVisualsVisible -eq $Visible) {
    if ($Visible) {
      if ($null -ne $script:Window -and -not $script:Window.IsVisible) {
        $script:Window.Opacity = 0.0
        $script:Window.Show()
        Start-RingOpacityAnimation -TargetOpacity 1.0 -DurationMs ([double]$script:Style.FadeInMs) -HideWhenDone $false
      }
      Update-StaleIndicator
    }
    return
  }
  $script:RingVisualsVisible = $Visible

  if ($Visible) {
    Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Visible)
    if ($null -ne $script:Window -and -not $script:Window.IsVisible) {
      $script:Window.Opacity = 0.0
      $script:Window.Show()
    }
    Update-StaleIndicator
    Start-RingOpacityAnimation -TargetOpacity 1.0 -DurationMs ([double]$script:Style.FadeInMs) -HideWhenDone $false
  } else {
    if ($null -ne $script:Window -and $script:Window.IsVisible) {
      Start-RingOpacityAnimation -TargetOpacity 0.0 -DurationMs ([double]$script:Style.FadeOutMs) -HideWhenDone $true
    } else {
      Hide-RingReadouts
      Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)
    }
  }
}

function Test-CursorOverPet {
  param($Cursor)
  if ($null -eq $script:LastPetRect -or $null -eq $Cursor) { return $false }
  $rect = $script:LastPetRect
  return (
    [double]$Cursor.X -ge [double]$rect.X -and
    [double]$Cursor.X -le ([double]$rect.X + [double]$rect.Width) -and
    [double]$Cursor.Y -ge [double]$rect.Y -and
    [double]$Cursor.Y -le ([double]$rect.Y + [double]$rect.Height)
  )
}

function Test-CursorInRingRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    [double]::IsNaN([double]$script:Window.Width) -or
    [double]$script:Window.Width -le 1
  ) {
    return $false
  }

  $size = [double]$script:Window.Width
  $centerX = [double]$script:Window.Left + $size / 2.0
  $centerY = [double]$script:Window.Top + $size / 2.0
  $outerRadius = if ($null -ne $script:RingOuterRadius) {
    [double]$script:RingOuterRadius
  } else {
    $size / 2.0 - 16.0
  }
  $range = [Math]::Max(0.0, [double]$script:Style.HoverRange)
  $distance = [Math]::Sqrt([Math]::Pow([double]$Cursor.X - $centerX, 2) + [Math]::Pow([double]$Cursor.Y - $centerY, 2))
  return ($distance -le ($outerRadius + $range))
}

function Update-RingHoverVisibility {
  if ($null -eq $script:Window -or $null -eq $script:LastPetRect) {
    Set-RingVisualsVisible -Visible $false
    return
  }

  if ($script:Style.VisibilityMode -eq "always") {
    Set-RingVisualsVisible -Visible $true
    return
  }

  $cursor = [System.Windows.Forms.Cursor]::Position
  $showRing = (Test-CursorOverPet -Cursor $cursor) -or ($script:Window.IsVisible -and (Test-CursorInRingRange -Cursor $cursor))
  Set-RingVisualsVisible -Visible $showRing
  Set-FrameTimerInterval -Fast $true
}

function Test-RectOverlap {
  param([double]$Left, [double]$Top, [double]$Width, [double]$Height, $Rect)
  if ($null -eq $Rect) { return $false }
  return (
    $Left -lt ([double]$Rect.X + [double]$Rect.Width) -and
    ($Left + $Width) -gt [double]$Rect.X -and
    $Top -lt ([double]$Rect.Y + [double]$Rect.Height) -and
    ($Top + $Height) -gt [double]$Rect.Y
  )
}

function New-ReadoutPlacement {
  param([double]$Left, [double]$Top, [double]$Width, [double]$Height)
  return [PSCustomObject]@{
    Left = $Left
    Top = $Top
    Width = $Width
    Height = $Height
  }
}

function Clamp-ReadoutPlacement {
  param($Placement, $Bounds)
  $left = [Math]::Max([double]$Bounds.Left + 4.0, [Math]::Min([double]$Placement.Left, [double]$Bounds.Right - [double]$Placement.Width - 4.0))
  $top = [Math]::Max([double]$Bounds.Top + 4.0, [Math]::Min([double]$Placement.Top, [double]$Bounds.Bottom - [double]$Placement.Height - 4.0))
  return New-ReadoutPlacement -Left $left -Top $top -Width ([double]$Placement.Width) -Height ([double]$Placement.Height)
}

function Set-ReadoutWindowNearPoint {
  param($Window, $Border, [double]$ScreenX, [double]$ScreenY)
  if ($null -eq $Window -or $null -eq $Border) { return }

  $Border.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $width = [double]$Border.DesiredSize.Width
  $height = [double]$Border.DesiredSize.Height
  $Window.Width = $width
  $Window.Height = $height

  $screen = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int][Math]::Round($ScreenX), [int][Math]::Round($ScreenY)))
  $bounds = $screen.WorkingArea
  $pet = $script:LastPetRect
  $margin = 12.0
  $candidates = @()
  if ($null -ne $pet) {
    $candidates += New-ReadoutPlacement -Left ([double]$pet.X + [double]$pet.Width + $margin) -Top ($ScreenY - $height / 2.0) -Width $width -Height $height
    $candidates += New-ReadoutPlacement -Left ([double]$pet.X - $width - $margin) -Top ($ScreenY - $height / 2.0) -Width $width -Height $height
    $candidates += New-ReadoutPlacement -Left ($ScreenX - $width / 2.0) -Top ([double]$pet.Y - $height - $margin) -Width $width -Height $height
    $candidates += New-ReadoutPlacement -Left ($ScreenX - $width / 2.0) -Top ([double]$pet.Y + [double]$pet.Height + $margin) -Width $width -Height $height
  }
  $candidates += New-ReadoutPlacement -Left ($ScreenX + $margin) -Top ($ScreenY - $height / 2.0) -Width $width -Height $height
  $candidates += New-ReadoutPlacement -Left ($ScreenX - $width - $margin) -Top ($ScreenY - $height / 2.0) -Width $width -Height $height

  $chosen = $null
  foreach ($candidate in $candidates) {
    $clamped = Clamp-ReadoutPlacement -Placement $candidate -Bounds $bounds
    if (-not (Test-RectOverlap -Left $clamped.Left -Top $clamped.Top -Width $clamped.Width -Height $clamped.Height -Rect $pet)) {
      $chosen = $clamped
      break
    }
  }
  if ($null -eq $chosen) {
    $chosen = Clamp-ReadoutPlacement -Placement $candidates[0] -Bounds $bounds
  }

  $Window.Left = [double]$chosen.Left
  $Window.Top = [double]$chosen.Top
}

function Set-PotionReadoutWindow {
  param([ValidateSet("Outer", "Inner")][string]$Ring, $Window, $Border)
  if ($null -eq $Window -or $null -eq $Border) { return }
  $geometry = if ($Ring -eq "Outer") { $script:OuterPotionBackdrop.Data } else { $script:InnerPotionBackdrop.Data }
  if ($null -eq $geometry) { return }

  $Border.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $width = [double]$Border.DesiredSize.Width
  $height = [double]$Border.DesiredSize.Height
  $Window.Width = $width
  $Window.Height = $height

  $orb = $geometry.Bounds
  $orbCenterY = [double]$script:Window.Top + [double]$orb.Top + [double]$orb.Height / 2.0
  $anchorX = if ($Ring -eq "Outer") {
    [double]$script:Window.Left + [double]$orb.Left
  } else {
    [double]$script:Window.Left + [double]$orb.Right
  }
  $screen = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int][Math]::Round($anchorX), [int][Math]::Round($orbCenterY)))
  $bounds = $screen.WorkingArea
  $margin = 12.0
  $left = if ($Ring -eq "Outer") { $anchorX - $width - $margin } else { $anchorX + $margin }
  $placement = New-ReadoutPlacement -Left $left -Top ($orbCenterY - $height / 2.0) -Width $width -Height $height
  $placement = Clamp-ReadoutPlacement -Placement $placement -Bounds $bounds
  $Window.Left = [double]$placement.Left
  $Window.Top = [double]$placement.Top
}

function Show-RingReadout {
  param([ValidateSet("Outer", "Inner")][string]$Ring, [double]$X, [double]$Y, [double]$Size)
  $screenX = [double]$script:Window.Left + $X
  $screenY = [double]$script:Window.Top + $Y
  if ($Ring -eq "Outer") {
    if ($null -ne $script:InnerReadoutWindow -and $script:InnerReadoutWindow.IsVisible) {
      $script:InnerReadoutWindow.Hide()
    }
    $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
    $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
    if ($script:Style.AppearanceMode -in @("potions", "heart_potions")) {
      Set-PotionReadoutWindow -Ring "Outer" -Window $script:OuterReadoutWindow -Border $script:OuterReadoutBorder
    } else {
      Set-ReadoutWindowNearPoint -Window $script:OuterReadoutWindow -Border $script:OuterReadoutBorder -ScreenX $screenX -ScreenY $screenY
    }
    if (-not $script:OuterReadoutWindow.IsVisible) { $script:OuterReadoutWindow.Show() }
    return
  }

  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
  if ($script:Style.AppearanceMode -in @("potions", "heart_potions")) {
    Set-PotionReadoutWindow -Ring "Inner" -Window $script:InnerReadoutWindow -Border $script:InnerReadoutBorder
  } else {
    Set-ReadoutWindowNearPoint -Window $script:InnerReadoutWindow -Border $script:InnerReadoutBorder -ScreenX $screenX -ScreenY $screenY
  }
  if (-not $script:InnerReadoutWindow.IsVisible) { $script:InnerReadoutWindow.Show() }
}

function Get-RingRemaining {
  param($DisplayedValue, $TargetValue)
  if ($null -ne $DisplayedValue) { return [double]$DisplayedValue }
  if ($null -ne $TargetValue) { return [double]$TargetValue }
  return 0.0
}

function Step-UsageValue {
  param($Current, $Target)
  if ($null -eq $Target) { return $null }
  if ($null -eq $Current) { return [double]$Target }

  $currentValue = [double]$Current
  $targetValue = [double]$Target
  $delta = $targetValue - $currentValue
  if ([Math]::Abs($delta) -lt 0.05) { return $targetValue }
  return $currentValue + $delta * $UsageAnimationFactor
}

function Update-UsageAnimation {
  if (-not $script:HasUsageSnapshot) { return }

  $oldPrimary = $script:DisplayedUsageState.PrimaryRemaining
  $oldSecondary = $script:DisplayedUsageState.SecondaryRemaining
  $script:DisplayedUsageState.PrimaryRemaining = Step-UsageValue `
    -Current $script:DisplayedUsageState.PrimaryRemaining `
    -Target $script:UsageState.PrimaryRemaining
  $script:DisplayedUsageState.SecondaryRemaining = Step-UsageValue `
    -Current $script:DisplayedUsageState.SecondaryRemaining `
    -Target $script:UsageState.SecondaryRemaining

  $primaryChanged = $oldPrimary -ne $script:DisplayedUsageState.PrimaryRemaining
  $secondaryChanged = $oldSecondary -ne $script:DisplayedUsageState.SecondaryRemaining
  if ($primaryChanged -or $secondaryChanged) {
    Update-RingGeometry
    Set-FrameTimerInterval -Fast $true
  } else {
    Set-FrameTimerInterval -Fast $false
  }
}

function Update-RingGeometry {
  if (
    $null -eq $script:Window -or
    [double]::IsNaN([double]$script:Window.Width) -or
    [double]$script:Window.Width -le 1
  ) {
    return
  }
  $size = [double]$script:Window.Width
  $center = $size / 2.0
  $outerRadius = if ($null -ne $script:RingOuterRadius) {
    [double]$script:RingOuterRadius
  } else {
    $size / 2.0 - 16.0
  }
  $innerRadius = if ($null -ne $script:RingInnerRadius) {
    [double]$script:RingInnerRadius
  } else {
    $outerRadius - 13.0
  }

  Set-EllipseBounds $script:OuterTrack $center $outerRadius
  Set-EllipseBounds $script:InnerTrack $center $innerRadius
  $primaryRemaining = Get-RingRemaining `
    -DisplayedValue $script:DisplayedUsageState.PrimaryRemaining `
    -TargetValue $script:UsageState.PrimaryRemaining
  $secondaryRemaining = Get-RingRemaining `
    -DisplayedValue $script:DisplayedUsageState.SecondaryRemaining `
    -TargetValue $script:UsageState.SecondaryRemaining

  $petHalf = [Math]::Max(24.0, $outerRadius - [double]$script:Style.RingGap)
  $extent = [Math]::Min($size / 2.0 - 8.0, $petHalf + [Math]::Max(10.0, [double]$script:Style.RingGap * 0.55))
  $outerPoints = $null
  $innerPoints = $null
  switch ($script:Style.AppearanceMode) {
    "bars" {
      $outerPoints = @(
        [System.Windows.Point]::new($center - $extent, $center - $extent),
        [System.Windows.Point]::new($center + $extent, $center - $extent)
      )
      $innerPoints = @(
        [System.Windows.Point]::new($center - $extent, $center + $extent),
        [System.Windows.Point]::new($center + $extent, $center + $extent)
      )
    }
    "wings" {
      $outerPoints = @(
        [System.Windows.Point]::new($center - $extent, $center + $extent),
        [System.Windows.Point]::new($center - $extent, $center - $extent)
      )
      $innerPoints = @(
        [System.Windows.Point]::new($center + $extent, $center + $extent),
        [System.Windows.Point]::new($center + $extent, $center - $extent)
      )
    }
    "corners" {
      $outerPoints = @(
        [System.Windows.Point]::new($center, $center - $extent),
        [System.Windows.Point]::new($center - $extent, $center - $extent),
        [System.Windows.Point]::new($center - $extent, $center)
      )
      $innerPoints = @(
        [System.Windows.Point]::new($center, $center + $extent),
        [System.Windows.Point]::new($center + $extent, $center + $extent),
        [System.Windows.Point]::new($center + $extent, $center)
      )
    }
    default {
      $outerPoints = @(
        [System.Windows.Point]::new($center - $extent, $center - $extent),
        [System.Windows.Point]::new($center + $extent, $center - $extent)
      )
      $innerPoints = @(
        [System.Windows.Point]::new($center - $extent, $center + $extent),
        [System.Windows.Point]::new($center + $extent, $center + $extent)
      )
    }
  }

  $script:OuterArc.Data = New-ArcGeometry -Center $center -Radius $outerRadius -Percent $primaryRemaining -StrokeThickness $OuterStroke
  $script:InnerArc.Data = New-ArcGeometry -Center $center -Radius $innerRadius -Percent $secondaryRemaining -StrokeThickness $InnerStroke
  $script:OuterArc.Stroke = Get-CapacityBrush -Remaining $primaryRemaining
  $script:InnerArc.Stroke = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary
  if ($null -ne $script:OuterAltTrack) {
    $script:OuterAltTrack.Data = New-PolylineGeometry -Points $outerPoints
    $script:InnerAltTrack.Data = New-PolylineGeometry -Points $innerPoints
    $script:OuterAltValue.Data = New-ProgressPolylineGeometry -Points $outerPoints -Percent $primaryRemaining
    $script:InnerAltValue.Data = New-ProgressPolylineGeometry -Points $innerPoints -Percent $secondaryRemaining
    $script:OuterAltValue.Stroke = Get-CapacityBrush -Remaining $primaryRemaining
    $script:InnerAltValue.Stroke = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary
  }
  if ($null -ne $script:OuterPixelPotion) {
    $outerPotionVisual = if ($script:Style.AppearanceMode -eq "heart_potions") { $script:OuterHeartPotion } else { $script:OuterPixelPotion }
    $innerPotionVisual = if ($script:Style.AppearanceMode -eq "heart_potions") { $script:InnerHeartPotion } else { $script:InnerPixelPotion }
    $potionScale = [double]$script:Style.PotionScale / 100.0
    $potionPadding = [Math]::Max(128.0 + [Math]::Max(0.0, $potionScale - 1.0) * 80.0, [double]$script:Style.RingGap + 16.0)
    $potionPetHalf = [Math]::Max(24.0, $outerRadius - ($potionPadding - 16.0))
    $potionBaseRadius = [Math]::Min(44.0, [Math]::Max(28.0, $potionPetHalf * 0.68))
    $potionRadius = $potionBaseRadius * $potionScale
    $potionOffset = [Math]::Min($outerRadius - $potionRadius - 10.0, $potionPetHalf + $potionRadius + 10.0)
    $leftPotionX = $center - $potionOffset
    $rightPotionX = $center + $potionOffset
    $spriteScale = $potionRadius / ([double]$outerPotionVisual.Width / 2.0)
    $spriteWidth = [double]$outerPotionVisual.Width * $spriteScale
    $spriteHeight = [double]$outerPotionVisual.Height * $spriteScale
    $outerLeft = $leftPotionX - $spriteWidth / 2.0
    $innerLeft = $rightPotionX - $spriteWidth / 2.0
    $spriteTop = $center - ([double]$outerPotionVisual.Height * 0.51) * $spriteScale
    Set-PixelPotionVisual `
      -Visual $outerPotionVisual `
      -Remaining $primaryRemaining `
      -LiquidBrush (Get-CapacityBrush -Remaining $primaryRemaining) `
      -Scale $spriteScale `
      -Left $outerLeft `
      -Top $spriteTop
    Set-PixelPotionVisual `
      -Visual $innerPotionVisual `
      -Remaining $secondaryRemaining `
      -LiquidBrush (Get-CapacityBrush -Remaining $secondaryRemaining -Secondary) `
      -Scale $spriteScale `
      -Left $innerLeft `
      -Top $spriteTop
    $outerHit = [System.Windows.Media.RectangleGeometry]::new(
      [System.Windows.Rect]::new($outerLeft, $spriteTop, $spriteWidth, $spriteHeight)
    )
    $innerHit = [System.Windows.Media.RectangleGeometry]::new(
      [System.Windows.Rect]::new($innerLeft, $spriteTop, $spriteWidth, $spriteHeight)
    )
    $outerHit.Freeze()
    $innerHit.Freeze()
    $script:OuterPotionBackdrop.Data = $outerHit
    $script:InnerPotionBackdrop.Data = $innerHit
  }

  [void](Update-ReadoutText)
}

function Set-PetAutoDetectState {
  param([bool]$Visible)
  if ($script:LastPetVisible -ne $Visible) {
    $script:LastPetVisible = $Visible
    if ($Visible) {
      Write-AppLog "Codex /pet overlay detected; showing rings."
    } else {
      Write-AppLog "Codex /pet overlay is not visible; waiting automatically."
    }
  }
}

function Set-FrameTimerInterval {
  param([bool]$Fast)
  if ($null -eq $script:FrameTimer) { return }
  $targetMs = if ($Fast) { $FramePollMs } else { $IdleFramePollMs }
  if ([Math]::Abs($script:FrameTimer.Interval.TotalMilliseconds - $targetMs) -gt 1.0) {
    $script:FrameTimer.Interval = [TimeSpan]::FromMilliseconds($targetMs)
  }
}

function Set-FrameTimerActive {
  param([bool]$Active)
  if ($null -eq $script:FrameTimer) { return }
  if ($Active) {
    if (-not $script:FrameTimer.IsEnabled) { $script:FrameTimer.Start() }
  } else {
    if ($script:FrameTimer.IsEnabled) { $script:FrameTimer.Stop() }
    Set-RingVisualsVisible -Visible $false
    Hide-RingReadouts
  }
}

function Update-PetFrame {
  if (-not $script:RingsEnabled) {
    if ($script:Window.IsVisible) { $script:Window.Hide() }
    Set-FrameTimerActive -Active $false
    return
  }

  $rect = Read-PetRect
  if ($null -eq $rect) {
    Set-PetAutoDetectState -Visible $false
    $script:LastPetFrameSignature = ""
    if ($script:Window.IsVisible) { $script:Window.Hide() }
    Set-FrameTimerActive -Active $false
    return
  }

  Set-PetAutoDetectState -Visible $true
  $ringPadding = [double]$script:Style.RingGap + 16.0
  if ($script:Style.AppearanceMode -in @("potions", "heart_potions")) {
    $potionScale = [double]$script:Style.PotionScale / 100.0
    $ringPadding = [Math]::Max(128.0 + [Math]::Max(0.0, $potionScale - 1.0) * 80.0, $ringPadding)
  }
  $ringSize = [Math]::Max([double]$rect.Width, [double]$rect.Height) + $ringPadding * 2.0
  $windowSize = $ringSize
  $left = [double]$rect.X + [double]$rect.Width / 2.0 - $windowSize / 2.0 + [double]$script:Style.OffsetX
  $top = [double]$rect.Y + [double]$rect.Height / 2.0 - $windowSize / 2.0 + [double]$script:Style.OffsetY

  $signature = "{0:N1}|{1:N1}|{2:N1}|{3:N1}|{4:N1}|{5:N1}" -f `
    $left,
    $top,
    $windowSize,
    $rect.X,
    $rect.Y,
    $ringSize
  $changed = $signature -ne $script:LastPetFrameSignature
  if ($changed) {
    $script:LastPetRect = $rect
    $script:LastPetFrameSignature = $signature
    $script:RingOuterRadius = $ringSize / 2.0 - 16.0
    $script:RingInnerRadius = $script:RingOuterRadius - 13.0
    $script:Window.Width = $windowSize
    $script:Window.Height = $windowSize
    $script:Canvas.Width = $windowSize
    $script:Canvas.Height = $windowSize
    $script:Window.Left = $left
    $script:Window.Top = $top
    Update-RingGeometry
  }

  Set-FrameTimerActive -Active $true
  Update-RingHoverVisibility
  Update-HoverReadout
  Move-RingBehindCodex
}

function Update-HoverReadout {
  if (-not $script:Window.IsVisible) {
    Hide-RingReadouts
    return
  }
  $cursor = [System.Windows.Forms.Cursor]::Position
  $localX = [double]$cursor.X - [double]$script:Window.Left
  $localY = [double]$cursor.Y - [double]$script:Window.Top
  $size = [double]$script:Window.Width
  if ($localX -lt 0 -or $localY -lt 0 -or $localX -gt $size -or $localY -gt $size) {
    Hide-RingReadouts
    return
  }
  if ($script:Style.AppearanceMode -ne "rings") {
    $point = [System.Windows.Point]::new($localX, $localY)
    if ($script:Style.AppearanceMode -in @("potions", "heart_potions")) {
      $outerHit = $null -ne $script:OuterPotionBackdrop.Data -and $script:OuterPotionBackdrop.Data.FillContains($point)
      $innerHit = $null -ne $script:InnerPotionBackdrop.Data -and $script:InnerPotionBackdrop.Data.FillContains($point)
    } else {
      $hoverPen = [System.Windows.Media.Pen]::new([System.Windows.Media.Brushes]::Black, 36.0)
      $outerHit = $null -ne $script:OuterAltTrack.Data -and $script:OuterAltTrack.Data.StrokeContains($hoverPen, $point)
      $innerHit = $null -ne $script:InnerAltTrack.Data -and $script:InnerAltTrack.Data.StrokeContains($hoverPen, $point)
    }
    if (-not $outerHit -and -not $innerHit) {
      Hide-RingReadouts
      return
    }
    $textUpdated = [bool](Update-ReadoutText)
    $ring = if ($outerHit) { "Outer" } else { "Inner" }
    $hoverSignature = "{0}|{1:N0}|{2:N0}" -f $ring, $localX, $localY
    if (-not $textUpdated -and $script:LastHoverSignature -eq $hoverSignature) { return }
    $script:LastHoverSignature = $hoverSignature
    Show-RingReadout -Ring $ring -X $localX -Y $localY -Size $size
    return
  }
  $distance = [Math]::Sqrt([Math]::Pow($localX - $size / 2.0, 2) + [Math]::Pow($localY - $size / 2.0, 2))
  $outerRadius = if ($null -ne $script:RingOuterRadius) {
    [double]$script:RingOuterRadius
  } else {
    $size / 2.0 - 16.0
  }
  $innerRadius = if ($null -ne $script:RingInnerRadius) {
    [double]$script:RingInnerRadius
  } else {
    $outerRadius - 13.0
  }
  $outerDelta = [Math]::Abs($distance - $outerRadius)
  $innerDelta = [Math]::Abs($distance - $innerRadius)
  $nearestDelta = [Math]::Min($outerDelta, $innerDelta)
  if ($nearestDelta -gt 18.0) {
    Hide-RingReadouts
    return
  }
  $textUpdated = [bool](Update-ReadoutText)
  if ($outerDelta -le $innerDelta) {
    $hoverSignature = "Outer|{0:N0}|{1:N0}" -f $localX, $localY
    if (-not $textUpdated -and $script:LastHoverSignature -eq $hoverSignature) { return }
    $script:LastHoverSignature = $hoverSignature
    Show-RingReadout -Ring "Outer" -X $localX -Y $localY -Size $size
  } else {
    $hoverSignature = "Inner|{0:N0}|{1:N0}" -f $localX, $localY
    if (-not $textUpdated -and $script:LastHoverSignature -eq $hoverSignature) { return }
    $script:LastHoverSignature = $hoverSignature
    Show-RingReadout -Ring "Inner" -X $localX -Y $localY -Size $size
  }
}

function Update-TrayText {
  if ($NoTrayIcon -or $null -eq $script:NotifyIcon) { return }
  $text = (Get-UiText "TrayText") -f `
    (Format-Percent $script:UsageState.PrimaryRemaining), `
    (Format-Percent $script:UsageState.SecondaryRemaining)
  if ($script:UsageIsStale) {
    $text += if (Test-KoreanLanguage) { (Expand-UnicodeText " \u00B7 \uC624\uD504\uB77C\uC778") } else { " · offline" }
  }
  if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
  $script:NotifyIcon.Text = $text
}

function Update-TrayMenuText {
  if ($NoTrayIcon) { return }
  if ($null -ne $script:ShowItem) { $script:ShowItem.Text = Get-UiText "ShowRings" }
  if ($null -ne $script:RefreshItem) { $script:RefreshItem.Text = Get-UiText "RefreshNow" }
  if ($null -ne $script:SettingsItem) { $script:SettingsItem.Text = Get-UiText "Settings" }
  if ($null -ne $script:OpenLogsItem) { $script:OpenLogsItem.Text = Get-UiText "OpenLogs" }
  if ($null -ne $script:QuitItem) { $script:QuitItem.Text = Get-UiText "Quit" }
  if ($null -ne $script:NotifyIcon -and [string]::IsNullOrWhiteSpace($script:NotifyIcon.Text)) {
    $script:NotifyIcon.Text = Get-UiText "TrayTitle"
  }
}

function Stop-RingsApp {
  Write-AppLog "Stopping Codex Pet Limit Rings for Windows."
  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  if ($null -ne $script:InnerReadoutWindow -and $script:InnerReadoutWindow.IsVisible) {
    $script:InnerReadoutWindow.Hide()
  }
  if ($null -ne $script:NotifyIcon) {
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
  }
  if ($null -ne $script:TrayCatIcon) {
    $script:TrayCatIcon.Dispose()
    $script:TrayCatIcon = $null
  }
  [System.Windows.Application]::Current.Shutdown()
}

[void](Update-StyleFromSettings -Force)
Update-AutomaticLanguage

$script:App = [System.Windows.Application]::new()
$script:Window = [System.Windows.Window]::new()
$script:Window.WindowStyle = [System.Windows.WindowStyle]::None
$script:Window.AllowsTransparency = $true
$script:Window.Background = [System.Windows.Media.Brushes]::Transparent
$script:Window.Topmost = $true
$script:Window.ShowInTaskbar = $false
$script:Window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$script:Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual

$script:Canvas = [System.Windows.Controls.Canvas]::new()
$script:Window.Content = $script:Canvas

function New-ReadoutWindow {
  param($Content)
  $window = [System.Windows.Window]::new()
  $window.WindowStyle = [System.Windows.WindowStyle]::None
  $window.AllowsTransparency = $true
  $window.Background = [System.Windows.Media.Brushes]::Transparent
  $window.Topmost = $true
  $window.ShowInTaskbar = $false
  $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
  $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
  $window.Content = $Content
  $window.Add_SourceInitialized({
    param($Sender, $EventArgs)
    $handle = (New-Object System.Windows.Interop.WindowInteropHelper($Sender)).Handle
    [CodexPetLimitRingNative]::MakeClickThrough($handle)
  })
  return $window
}

$script:OuterTrack = [System.Windows.Shapes.Ellipse]::new()
$script:OuterTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
$script:OuterTrack.StrokeThickness = $OuterStroke

$script:InnerTrack = [System.Windows.Shapes.Ellipse]::new()
$script:InnerTrack.Stroke = New-StyleBrush ([byte][Math]::Max(10, [Math]::Min(255, [int]$script:Style.TrackOpacity - 4))) ([int[]]$script:Style.TrackRgb)
$script:InnerTrack.StrokeThickness = $InnerStroke

$script:OuterArc = [System.Windows.Shapes.Path]::new()
$script:OuterArc.StrokeThickness = $OuterStroke
$script:OuterArc.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:OuterArc.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round

$script:InnerArc = [System.Windows.Shapes.Path]::new()
$script:InnerArc.StrokeThickness = $InnerStroke
$script:InnerArc.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:InnerArc.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round

$script:OuterAltTrack = [System.Windows.Shapes.Path]::new()
$script:OuterAltTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
$script:OuterAltTrack.StrokeThickness = $OuterStroke
$script:OuterAltTrack.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:OuterAltTrack.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
$script:OuterAltTrack.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:InnerAltTrack = [System.Windows.Shapes.Path]::new()
$script:InnerAltTrack.Stroke = New-StyleBrush ([byte][Math]::Max(10, [Math]::Min(255, [int]$script:Style.TrackOpacity - 4))) ([int[]]$script:Style.TrackRgb)
$script:InnerAltTrack.StrokeThickness = $InnerStroke
$script:InnerAltTrack.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:InnerAltTrack.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
$script:InnerAltTrack.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:OuterAltValue = [System.Windows.Shapes.Path]::new()
$script:OuterAltValue.StrokeThickness = $OuterStroke
$script:OuterAltValue.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:OuterAltValue.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
$script:OuterAltValue.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:InnerAltValue = [System.Windows.Shapes.Path]::new()
$script:InnerAltValue.StrokeThickness = $InnerStroke
$script:InnerAltValue.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
$script:InnerAltValue.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
$script:InnerAltValue.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:OuterPotionTrack = [System.Windows.Shapes.Path]::new()
$script:OuterPotionTrack.Fill = New-StyleBrush 235 @(202, 148, 69)
$script:OuterPotionTrack.Stroke = New-StyleBrush 245 @(92, 57, 26)
$script:OuterPotionTrack.StrokeThickness = 1.5
$script:OuterPotionTrack.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:InnerPotionTrack = [System.Windows.Shapes.Path]::new()
$script:InnerPotionTrack.Fill = New-StyleBrush 235 @(202, 148, 69)
$script:InnerPotionTrack.Stroke = New-StyleBrush 245 @(92, 57, 26)
$script:InnerPotionTrack.StrokeThickness = 1.5
$script:InnerPotionTrack.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:OuterPotionBackdrop = [System.Windows.Shapes.Path]::new()
$script:OuterPotionBackdrop.Fill = New-StyleBrush 214 @(16, 20, 31)
$script:OuterPotionBackdrop.Stroke = New-StyleBrush 180 @(239, 183, 87)
$script:OuterPotionBackdrop.StrokeThickness = 1.2

$script:InnerPotionBackdrop = [System.Windows.Shapes.Path]::new()
$script:InnerPotionBackdrop.Fill = New-StyleBrush 214 @(16, 20, 31)
$script:InnerPotionBackdrop.Stroke = New-StyleBrush 180 @(239, 183, 87)
$script:InnerPotionBackdrop.StrokeThickness = 1.2

$script:OuterPotionFill = [System.Windows.Shapes.Path]::new()
$script:InnerPotionFill = [System.Windows.Shapes.Path]::new()

$script:OuterPotionFacet = [System.Windows.Shapes.Path]::new()
$script:OuterPotionFacet.Stroke = New-StyleBrush 74 @(255, 255, 255)
$script:OuterPotionFacet.StrokeThickness = 0.9
$script:OuterPotionFacet.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:InnerPotionFacet = [System.Windows.Shapes.Path]::new()
$script:InnerPotionFacet.Stroke = New-StyleBrush 74 @(255, 255, 255)
$script:InnerPotionFacet.StrokeThickness = 0.9
$script:InnerPotionFacet.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round

$script:PotionPixelFrameBitmap = New-FrozenBitmapImage -Path $PotionPixelFramePath
$script:PotionPixelMaskBitmap = New-FrozenBitmapImage -Path $PotionPixelMaskPath
$script:PotionPixelMaskBrush = [System.Windows.Media.ImageBrush]::new($script:PotionPixelMaskBitmap)
$script:PotionPixelMaskBrush.Stretch = [System.Windows.Media.Stretch]::Fill
$script:PotionPixelMaskBrush.Freeze()
$script:OuterPixelPotion = New-PixelPotionVisual -Label "5H"
$script:InnerPixelPotion = New-PixelPotionVisual -Label "WK"
$script:HeartPotionPixelFrameBitmap = New-FrozenBitmapImage -Path $HeartPotionPixelFramePath
$script:HeartPotionPixelMaskBitmap = New-FrozenBitmapImage -Path $HeartPotionPixelMaskPath
$script:HeartPotionPixelMaskBrush = [System.Windows.Media.ImageBrush]::new($script:HeartPotionPixelMaskBitmap)
$script:HeartPotionPixelMaskBrush.Stretch = [System.Windows.Media.Stretch]::Fill
$script:HeartPotionPixelMaskBrush.Freeze()
$script:OuterHeartPotion = New-PixelPotionVisual -Label "5H" -Width 76 -Height 80 -FrameBitmap $script:HeartPotionPixelFrameBitmap -MaskBrush $script:HeartPotionPixelMaskBrush -ValueTop 34 -LabelTop 67 -ChamberTop 20 -ChamberBottom 69
$script:InnerHeartPotion = New-PixelPotionVisual -Label "WK" -Width 76 -Height 80 -FrameBitmap $script:HeartPotionPixelFrameBitmap -MaskBrush $script:HeartPotionPixelMaskBrush -ValueTop 34 -LabelTop 67 -ChamberTop 20 -ChamberBottom 69

$script:StaleBadgeText = [System.Windows.Controls.TextBlock]::new()
$script:StaleBadgeText.Foreground = New-StyleBrush 255 @(253, 224, 71)
$script:StaleBadgeText.FontFamily = [System.Windows.Media.FontFamily]::new("Noto Sans KR, Segoe UI")
$script:StaleBadgeText.FontSize = 10.5
$script:StaleBadgeText.FontWeight = [System.Windows.FontWeights]::SemiBold

$script:StaleBadgeBorder = [System.Windows.Controls.Border]::new()
$script:StaleBadgeBorder.Background = New-StyleBrush 226 @(24, 24, 27)
$script:StaleBadgeBorder.BorderBrush = New-StyleBrush 190 @(251, 191, 36)
$script:StaleBadgeBorder.BorderThickness = [System.Windows.Thickness]::new(1)
$script:StaleBadgeBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:StaleBadgeBorder.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
$script:StaleBadgeBorder.Child = $script:StaleBadgeText
$script:StaleBadgeBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:OuterReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:OuterReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:OuterReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:OuterReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:OuterReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Noto Sans KR, Segoe UI")
$script:OuterReadoutText.FontWeight = [System.Windows.FontWeights]::Medium

$script:InnerReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:InnerReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:InnerReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:InnerReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:InnerReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Noto Sans KR, Segoe UI")
$script:InnerReadoutText.FontWeight = [System.Windows.FontWeights]::Medium

$script:OuterReadoutBorder = [System.Windows.Controls.Border]::new()
$script:OuterReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
$script:OuterReadoutBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:OuterReadoutBorder.Padding = [System.Windows.Thickness]::new(7, 4, 7, 5)
$script:OuterReadoutBorder.Child = $script:OuterReadoutText
$script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:InnerReadoutBorder = [System.Windows.Controls.Border]::new()
$script:InnerReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
$script:InnerReadoutBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:InnerReadoutBorder.Padding = [System.Windows.Thickness]::new(7, 4, 7, 5)
$script:InnerReadoutBorder.Child = $script:InnerReadoutText
$script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:OuterReadoutWindow = New-ReadoutWindow -Content $script:OuterReadoutBorder
$script:InnerReadoutWindow = New-ReadoutWindow -Content $script:InnerReadoutBorder

$script:Canvas.Children.Add($script:OuterTrack) | Out-Null
$script:Canvas.Children.Add($script:InnerTrack) | Out-Null
$script:Canvas.Children.Add($script:OuterArc) | Out-Null
$script:Canvas.Children.Add($script:InnerArc) | Out-Null
$script:Canvas.Children.Add($script:OuterAltTrack) | Out-Null
$script:Canvas.Children.Add($script:InnerAltTrack) | Out-Null
$script:Canvas.Children.Add($script:OuterAltValue) | Out-Null
$script:Canvas.Children.Add($script:InnerAltValue) | Out-Null
$script:Canvas.Children.Add($script:OuterPixelPotion.Container) | Out-Null
$script:Canvas.Children.Add($script:InnerPixelPotion.Container) | Out-Null
$script:Canvas.Children.Add($script:OuterHeartPotion.Container) | Out-Null
$script:Canvas.Children.Add($script:InnerHeartPotion.Container) | Out-Null
$script:Canvas.Children.Add($script:StaleBadgeBorder) | Out-Null
Set-RingVisualsVisible -Visible $false

$script:Window.Add_SourceInitialized({
  $handle = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
  [CodexPetLimitRingNative]::MakeClickThrough($handle)
})

if (-not $NoTrayIcon) {
  $script:NotifyIcon = [System.Windows.Forms.NotifyIcon]::new()
  if (Test-Path -LiteralPath $TrayCatIconPath) {
    $script:TrayCatIcon = [System.Drawing.Icon]::new($TrayCatIconPath)
    $script:NotifyIcon.Icon = $script:TrayCatIcon
  } else {
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
  }
  $script:NotifyIcon.Text = Get-UiText "TrayTitle"
  $script:NotifyIcon.Visible = $true
  $menu = [System.Windows.Forms.ContextMenuStrip]::new()
  $script:ShowItem = [System.Windows.Forms.ToolStripMenuItem]::new((Get-UiText "ShowRings"))
  $showItem = $script:ShowItem
  $showItem.Checked = $true
  $showItem.CheckOnClick = $true
  $showItem.Add_CheckedChanged({
    $script:RingsEnabled = $showItem.Checked
    if ($script:RingsEnabled) {
      Update-PetFrame
    } else {
      if ($script:Window.IsVisible) { $script:Window.Hide() }
      Set-FrameTimerActive -Active $false
    }
  })
  $script:RefreshItem = [System.Windows.Forms.ToolStripMenuItem]::new((Get-UiText "RefreshNow"))
  $refreshItem = $script:RefreshItem
  $refreshItem.Add_Click({ Update-UsageState; Update-PetFrame })
  $script:SettingsItem = [System.Windows.Forms.ToolStripMenuItem]::new((Get-UiText "Settings"))
  $settingsItem = $script:SettingsItem
  $settingsItem.Add_Click({
    try {
      $settingsScript = Join-Path $ProjectRoot "bin\powershell\Settings.ps1"
      if (Test-Path -LiteralPath $settingsScript) {
        Start-Process "powershell.exe" `
          -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $settingsScript, "-SettingsPath", $SettingsPath) `
          -WindowStyle Hidden | Out-Null
      }
    } catch {
      Write-AppLog "Settings launch failed: $($_.Exception.Message)"
    }
  })
  $script:OpenLogsItem = [System.Windows.Forms.ToolStripMenuItem]::new((Get-UiText "OpenLogs"))
  $openLogsItem = $script:OpenLogsItem
  $openLogsItem.Add_Click({
    try { [System.Diagnostics.Process]::Start("explorer.exe", $LogDirectory) | Out-Null } catch {}
  })
  $script:QuitItem = [System.Windows.Forms.ToolStripMenuItem]::new((Get-UiText "Quit"))
  $quitItem = $script:QuitItem
  $quitItem.Add_Click({ Stop-RingsApp })
  $menu.Items.Add($showItem) | Out-Null
  $menu.Items.Add($refreshItem) | Out-Null
  $menu.Items.Add($settingsItem) | Out-Null
  $menu.Items.Add($openLogsItem) | Out-Null
  $menu.Items.Add("-") | Out-Null
  $menu.Items.Add($quitItem) | Out-Null
  $script:NotifyIcon.ContextMenuStrip = $menu
}

$script:FrameTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:FrameTimer.Interval = [TimeSpan]::FromMilliseconds($IdleFramePollMs)
$script:FrameTimer.Add_Tick({
  try {
    Update-UsageAnimation
    Update-RingHoverVisibility
    Update-HoverReadout
  } catch {
    Write-AppLog "Frame update failed: $($_.Exception.Message)"
  }
})

$script:PetTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:PetTimer.Interval = [TimeSpan]::FromMilliseconds($PetPollMs)
$script:PetTimer.Add_Tick({
  try {
    Update-PetFrame
  } catch {
    Write-AppLog "Pet frame update failed: $($_.Exception.Message)"
  }
})
$script:PetTimer.Start()

$script:UsageTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:UsageTimer.Interval = [TimeSpan]::FromSeconds($UsagePollSeconds)
$script:UsageTimer.Add_Tick({
  try {
    Update-UsageState
  } catch {
    Write-AppLog "Usage update failed: $($_.Exception.Message)"
  }
})
$script:UsageTimer.Start()

$script:SettingsTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:SettingsTimer.Interval = [TimeSpan]::FromSeconds(2)
$script:SettingsTimer.Add_Tick({
  try {
    $previousLanguage = [string]$script:Style.Language
    if (Update-StyleFromSettings) {
      if ($script:Style.Language -eq "auto" -and $previousLanguage -ne "auto") {
        Update-AutomaticLanguage
      }
      Apply-StyleSettings
      Write-AppLog "Settings reloaded from $SettingsPath"
    }
  } catch {
    Write-AppLog "Settings timer failed: $($_.Exception.Message)"
  }
})
$script:SettingsTimer.Start()

$script:MaintenanceTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MaintenanceTimer.Interval = [TimeSpan]::FromSeconds(15)
$script:MaintenanceTimer.Add_Tick({
  try {
    Optimize-ProcessFootprint
    $script:MaintenanceTimer.Interval = [TimeSpan]::FromMinutes(30)
  } catch {
    Write-AppLog "Maintenance update failed: $($_.Exception.Message)"
  }
})
$script:MaintenanceTimer.Start()

Update-UsageState
Update-PetFrame

$script:App.Add_Exit({
  if ($null -ne $script:NotifyIcon) {
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
  }
  if ($null -ne $script:TrayCatIcon) {
    $script:TrayCatIcon.Dispose()
    $script:TrayCatIcon = $null
  }
})

try {
  $script:App.Run() | Out-Null
} catch {
  Write-AppLog "Fatal error: $($_.Exception.Message)"
  throw
}
