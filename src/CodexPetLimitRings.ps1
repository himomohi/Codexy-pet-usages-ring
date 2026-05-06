param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$NoLiveUsage,
  [int]$UsagePollSeconds = 10,
  [int]$FramePollMs = 60,
  [int]$IdleFramePollMs = 300,
  [int]$PetPollMs = 300,
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
            string processName = Process.GetProcessById(unchecked((int)processId)).ProcessName;
            return string.Equals(processName, "Codex", StringComparison.OrdinalIgnoreCase);
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
$script:LastUsageSignature = ""
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
    }
    behavior = [ordered]@{
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
    $colors = Get-PropertyValue $settings "colors" $null
    $opacity = Get-PropertyValue $settings "opacity" $null
    $text = Get-PropertyValue $settings "text" $null
    $layout = Get-PropertyValue $settings "layout" $null
    $behavior = Get-PropertyValue $settings "behavior" $null

    $language = ([string](Get-PropertyValue $settings "language" "auto")).Trim().ToLowerInvariant()
    if ($language -notin @("auto", "ko", "en", "ja", "zh")) { $language = "auto" }
    $script:Style.Language = $language
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
  if ($language -in @("ko", "en", "ja", "zh")) { return $language }
  try {
    $cultureName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($cultureName -like "ko*") { return "ko" }
    if ($cultureName -like "ja*") { return "ja" }
    if ($cultureName -like "zh*") { return "zh" }
  } catch {}
  return "en"
}

function Test-KoreanLanguage {
  return ((Get-EffectiveLanguage) -eq "ko")
}

function Test-JapaneseLanguage {
  return ((Get-EffectiveLanguage) -eq "ja")
}

function Test-ChineseLanguage {
  return ((Get-EffectiveLanguage) -eq "zh")
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
  if (Test-JapaneseLanguage) {
    switch ($Key) {
      "TrayTitle" { return (Expand-UnicodeText "Codex \u30EA\u30F3\u30B0") }
      "TrayText" { return (Expand-UnicodeText "Codex \u30EA\u30F3\u30B0: {0} 5h, {1} \u9031\u6B21") }
      "ShowRings" { return (Expand-UnicodeText "\u30EA\u30F3\u30B0\u3092\u8868\u793A") }
      "RefreshNow" { return (Expand-UnicodeText "\u4ECA\u3059\u3050\u66F4\u65B0") }
      "Settings" { return (Expand-UnicodeText "\u8A2D\u5B9A") }
      "OpenLogs" { return (Expand-UnicodeText "\u30ED\u30B0\u3092\u958B\u304F") }
      "Quit" { return (Expand-UnicodeText "\u7D42\u4E86") }
    }
  }
  if (Test-ChineseLanguage) {
    switch ($Key) {
      "TrayTitle" { return (Expand-UnicodeText "Codex \u5706\u73AF") }
      "TrayText" { return (Expand-UnicodeText "Codex \u5706\u73AF\uFF1A{0} 5h\uFF0C{1} \u6BCF\u5468") }
      "ShowRings" { return (Expand-UnicodeText "\u663E\u793A\u5706\u73AF") }
      "RefreshNow" { return (Expand-UnicodeText "\u7ACB\u5373\u5237\u65B0") }
      "Settings" { return (Expand-UnicodeText "\u8BBE\u7F6E") }
      "OpenLogs" { return (Expand-UnicodeText "\u6253\u5F00\u65E5\u5FD7") }
      "Quit" { return (Expand-UnicodeText "\u9000\u51FA") }
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

function Convert-ResetValue {
  param($ResetAt, $ResetAfterSeconds)
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
    try { return (Get-Date).AddSeconds([double]$ResetAfterSeconds) } catch {}
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

  $primary = if ($rate.primary) { $rate.primary } elseif ($rate.primary_window) { $rate.primary_window } else { $null }
  $secondary = if ($rate.secondary) { $rate.secondary } elseif ($rate.secondary_window) { $rate.secondary_window } else { $null }
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
    $payload = Invoke-RestMethod `
      -Uri "https://chatgpt.com/backend-api/wham/usage" `
      -Headers @{ Authorization = "Bearer $token"; Accept = "application/json" } `
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
        SELECT feedback_log_body
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
}))
'@

  try {
    $raw = & $python.Source -c $code $LogsPath
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $payload = $raw | ConvertFrom-Json
    if ($null -eq $payload.primaryRemaining -and $null -eq $payload.secondaryRemaining) { return $null }
    return [PSCustomObject]@{
      Source = "log"
      Plan = $payload.plan
      PrimaryRemaining = $payload.primaryRemaining
      SecondaryRemaining = $payload.secondaryRemaining
      PrimaryResetAt = Convert-ResetValue -ResetAt $payload.primaryResetAt -ResetAfterSeconds $payload.primaryResetAfterSeconds
      SecondaryResetAt = Convert-ResetValue -ResetAt $payload.secondaryResetAt -ResetAfterSeconds $payload.secondaryResetAfterSeconds
      PrimaryWindowSeconds = $payload.primaryWindowSeconds
      SecondaryWindowSeconds = $payload.secondaryWindowSeconds
      ObservedAt = Get-Date
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
    if ($root.'electron-avatar-overlay-open' -is [bool] -and -not $root.'electron-avatar-overlay-open') {
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
  param([double]$Center, [double]$Radius, [double]$Percent)
  $percent = [Math]::Max(0, [Math]::Min(100, $Percent))
  if ($percent -le 0.1) { return [System.Windows.Media.Geometry]::Empty }
  if ($percent -ge 99.9) { $percent = 99.9 }
  $startDeg = -90.0
  $endDeg = $startDeg + 360.0 * ($percent / 100.0)
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
    [bool]($percent -gt 50),
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
  if ($null -eq $Value) { return "--" }
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
  $language = Get-EffectiveLanguage
  if ($total -ge 86400) {
    $days = [int][Math]::Floor($total / 86400)
    $hours = [int][Math]::Floor(($total % 86400) / 3600)
    if ($language -eq "ko") { return (Expand-UnicodeText "{0}\uC77C {1}\uC2DC\uAC04") -f $days, $hours }
    if ($language -eq "ja") { return (Expand-UnicodeText "{0}\u65E5 {1}\u6642\u9593") -f $days, $hours }
    if ($language -eq "zh") { return (Expand-UnicodeText "{0}\u5929 {1}\u5C0F\u65F6") -f $days, $hours }
    return "{0}d {1}h" -f $days, $hours
  }
  if ($total -ge 3600) {
    $hours = [int][Math]::Floor($total / 3600)
    $minutes = [int][Math]::Floor(($total % 3600) / 60)
    if ($language -eq "ko") { return (Expand-UnicodeText "{0}\uC2DC\uAC04 {1}\uBD84") -f $hours, $minutes }
    if ($language -eq "ja") { return (Expand-UnicodeText "{0}\u6642\u9593 {1}\u5206") -f $hours, $minutes }
    if ($language -eq "zh") { return (Expand-UnicodeText "{0}\u5C0F\u65F6 {1}\u5206\u949F") -f $hours, $minutes }
    return "{0}h {1}m" -f $hours, $minutes
  }
  if ($total -ge 60) {
    $minutes = [int][Math]::Floor($total / 60)
    $seconds = $total % 60
    if ($language -eq "ko") { return (Expand-UnicodeText "{0}\uBD84 {1}\uCD08") -f $minutes, $seconds }
    if ($language -eq "ja") { return (Expand-UnicodeText "{0}\u5206 {1}\u79D2") -f $minutes, $seconds }
    if ($language -eq "zh") { return (Expand-UnicodeText "{0}\u5206\u949F {1}\u79D2") -f $minutes, $seconds }
    return "{0}m {1}s" -f $minutes, $seconds
  }
  if ($language -eq "ko") { return (Expand-UnicodeText "{0}\uCD08") -f $total }
  if ($language -eq "ja") { return (Expand-UnicodeText "{0}\u79D2") -f $total }
  if ($language -eq "zh") { return (Expand-UnicodeText "{0}\u79D2") -f $total }
  return "{0}s" -f $total
}

function Format-ResetDetail {
  param($ResetAt)
  $language = Get-EffectiveLanguage
  if ($null -eq $ResetAt) {
    if ($language -eq "ko") { return (Expand-UnicodeText "\uC7AC\uC124\uC815 --") }
    if ($language -eq "ja") { return (Expand-UnicodeText "\u30EA\u30BB\u30C3\u30C8 --") }
    if ($language -eq "zh") { return (Expand-UnicodeText "\u91CD\u7F6E --") }
    return "Reset --"
  }
  $reset = [datetime]$ResetAt
  $remaining = ($reset - (Get-Date)).TotalSeconds
  $timeText = if ($reset.Date -eq (Get-Date).Date) {
    $reset.ToString("HH:mm")
  } else {
    if ($language -eq "ko") {
      $reset.ToString((Expand-UnicodeText "M\uC6D4 d\uC77C HH:mm"), [System.Globalization.CultureInfo]::GetCultureInfo("ko-KR"))
    } elseif ($language -eq "ja") {
      $reset.ToString((Expand-UnicodeText "M\u6708d\u65E5 HH:mm"), [System.Globalization.CultureInfo]::GetCultureInfo("ja-JP"))
    } elseif ($language -eq "zh") {
      $reset.ToString((Expand-UnicodeText "M\u6708d\u65E5 HH:mm"), [System.Globalization.CultureInfo]::GetCultureInfo("zh-CN"))
    } else {
      $reset.ToString("MMM d HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    }
  }
  if ($language -eq "ko") { return (Expand-UnicodeText "\uC7AC\uC124\uC815 {0} ({1})") -f (Format-Duration $remaining), $timeText }
  if ($language -eq "ja") { return (Expand-UnicodeText "\u30EA\u30BB\u30C3\u30C8 {0} ({1})") -f (Format-Duration $remaining), $timeText }
  if ($language -eq "zh") { return (Expand-UnicodeText "\u91CD\u7F6E {0} ({1})") -f (Format-Duration $remaining), $timeText }
  return "Reset {0} ({1})" -f (Format-Duration $remaining), $timeText
}

function Format-WindowLabel {
  param($Seconds, [string]$Fallback)
  if ($null -eq $Seconds) { return $Fallback }
  $language = Get-EffectiveLanguage
  $value = [double]$Seconds
  if ([Math]::Abs($value - 18000.0) -lt 180.0) { return "5h" }
  if ([Math]::Abs($value - 604800.0) -lt 3600.0) {
    if ($language -eq "ko") { return (Expand-UnicodeText "\uC8FC\uAC04") }
    if ($language -eq "ja") { return (Expand-UnicodeText "\u9031\u6B21") }
    if ($language -eq "zh") { return (Expand-UnicodeText "\u6BCF\u5468") }
    return "Weekly"
  }
  if ($value -ge 86400.0) {
    if ($language -eq "ko") { return (Expand-UnicodeText "{0:N0}\uC77C") -f ($value / 86400.0) }
    if ($language -eq "ja") { return (Expand-UnicodeText "{0:N0}\u65E5") -f ($value / 86400.0) }
    if ($language -eq "zh") { return (Expand-UnicodeText "{0:N0}\u5929") -f ($value / 86400.0) }
    return "{0:N0}d" -f ($value / 86400.0)
  }
  if ($value -ge 3600.0) {
    if ($language -eq "ko") { return (Expand-UnicodeText "{0:N0}\uC2DC\uAC04") -f ($value / 3600.0) }
    if ($language -eq "ja") { return (Expand-UnicodeText "{0:N0}\u6642\u9593") -f ($value / 3600.0) }
    if ($language -eq "zh") { return (Expand-UnicodeText "{0:N0}\u5C0F\u65F6") -f ($value / 3600.0) }
    return "{0:N0}h" -f ($value / 3600.0)
  }
  if ($language -eq "ko") { return (Expand-UnicodeText "{0:N0}\uBD84") -f ($value / 60.0) }
  if ($language -eq "ja") { return (Expand-UnicodeText "{0:N0}\u5206") -f ($value / 60.0) }
  if ($language -eq "zh") { return (Expand-UnicodeText "{0:N0}\u5206\u949F") -f ($value / 60.0) }
  return "{0:N0}m" -f ($value / 60.0)
}

function Get-RingReadoutText {
  param([ValidateSet("Outer", "Inner")][string]$Ring)
  $language = Get-EffectiveLanguage
  if ($Ring -eq "Outer") {
    $label = Format-WindowLabel -Seconds $script:UsageState.PrimaryWindowSeconds -Fallback "5h"
    if ($language -eq "ko") {
      return (Expand-UnicodeText "{0} \uD55C\uB3C4  {1} \uB0A8\uC74C`n{2}") -f `
        $label,
        (Format-Percent $script:UsageState.PrimaryRemaining),
        (Format-ResetDetail $script:UsageState.PrimaryResetAt)
    }
    if ($language -eq "ja") {
      return (Expand-UnicodeText "{0}\u5236\u9650  \u6B8B\u308A{1}`n{2}") -f `
        $label,
        (Format-Percent $script:UsageState.PrimaryRemaining),
        (Format-ResetDetail $script:UsageState.PrimaryResetAt)
    }
    if ($language -eq "zh") {
      return (Expand-UnicodeText "{0}\u9650\u5236  \u5269\u4F59{1}`n{2}") -f `
        $label,
        (Format-Percent $script:UsageState.PrimaryRemaining),
        (Format-ResetDetail $script:UsageState.PrimaryResetAt)
    }
    return "{0} limit  {1} left`n{2}" -f `
      $label,
      (Format-Percent $script:UsageState.PrimaryRemaining),
      (Format-ResetDetail $script:UsageState.PrimaryResetAt)
  }

  $weeklyFallback = switch ($language) {
    "ko" { Expand-UnicodeText "\uC8FC\uAC04" }
    "ja" { Expand-UnicodeText "\u9031\u6B21" }
    "zh" { Expand-UnicodeText "\u6BCF\u5468" }
    default { "Weekly" }
  }
  $label = Format-WindowLabel -Seconds $script:UsageState.SecondaryWindowSeconds -Fallback $weeklyFallback
  if ($language -eq "ko") {
    return (Expand-UnicodeText "{0}  {1} \uB0A8\uC74C`n{2}") -f `
      $label,
      (Format-Percent $script:UsageState.SecondaryRemaining),
      (Format-ResetDetail $script:UsageState.SecondaryResetAt)
  }
  if ($language -eq "ja") {
    return (Expand-UnicodeText "{0}  \u6B8B\u308A{1}`n{2}") -f `
      $label,
      (Format-Percent $script:UsageState.SecondaryRemaining),
      (Format-ResetDetail $script:UsageState.SecondaryResetAt)
  }
  if ($language -eq "zh") {
    return (Expand-UnicodeText "{0}  \u5269\u4F59{1}`n{2}") -f `
      $label,
      (Format-Percent $script:UsageState.SecondaryRemaining),
      (Format-ResetDetail $script:UsageState.SecondaryResetAt)
  }
  return "{0}  {1} left`n{2}" -f `
    $label,
    (Format-Percent $script:UsageState.SecondaryRemaining),
    (Format-ResetDetail $script:UsageState.SecondaryResetAt)
}

function Update-ReadoutText {
  param([switch]$Force)
  $now = Get-Date
  if (-not $Force -and ($now - $script:LastReadoutRefreshAt).TotalMilliseconds -lt 1000) {
    return $false
  }
  if ($null -ne $script:OuterReadoutText) {
    $script:OuterReadoutText.Text = Get-RingReadoutText -Ring "Outer"
  }
  if ($null -ne $script:InnerReadoutText) {
    $script:InnerReadoutText.Text = Get-RingReadoutText -Ring "Inner"
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

function Set-RingShapesVisibility {
  param([System.Windows.Visibility]$Visibility)
  foreach ($shape in @($script:OuterTrack, $script:InnerTrack, $script:OuterArc, $script:InnerArc)) {
    if ($null -ne $shape) {
      $shape.Visibility = $Visibility
    }
  }
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
  $completedToken = $animationToken
  $completedTargetOpacity = $TargetOpacity
  $completedHideWhenDone = $HideWhenDone
  $animation.Add_Completed({
    if ($script:RingAnimationToken -ne $completedToken) { return }
    $script:Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:Window.Opacity = $completedTargetOpacity
    if ($completedHideWhenDone -and -not $script:RingVisualsVisible) {
      Hide-RingReadouts
      Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)
      if ($script:Window.IsVisible) { $script:Window.Hide() }
    }
  }.GetNewClosure())
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
    Set-ReadoutWindowNearPoint -Window $script:OuterReadoutWindow -Border $script:OuterReadoutBorder -ScreenX $screenX -ScreenY $screenY
    if (-not $script:OuterReadoutWindow.IsVisible) { $script:OuterReadoutWindow.Show() }
    return
  }

  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
  Set-ReadoutWindowNearPoint -Window $script:InnerReadoutWindow -Border $script:InnerReadoutBorder -ScreenX $screenX -ScreenY $screenY
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
  if ($null -eq $Target) { return $Current }
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
  $script:OuterArc.Data = New-ArcGeometry -Center $center -Radius $outerRadius -Percent $primaryRemaining
  $script:InnerArc.Data = New-ArcGeometry -Center $center -Radius $innerRadius -Percent $secondaryRemaining
  $script:OuterArc.Stroke = Get-CapacityBrush -Remaining $primaryRemaining
  $script:InnerArc.Stroke = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary

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
  $ringSize = [Math]::Max([double]$rect.Width, [double]$rect.Height) + $ringPadding * 2.0
  $windowSize = $ringSize
  $left = [double]$rect.X + [double]$rect.Width / 2.0 - $windowSize / 2.0
  $top = [double]$rect.Y + [double]$rect.Height / 2.0 - $windowSize / 2.0

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
  [System.Windows.Application]::Current.Shutdown()
}

[void](Update-StyleFromSettings -Force)

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

$script:OuterReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:OuterReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:OuterReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:OuterReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:OuterReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

$script:InnerReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:InnerReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:InnerReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:InnerReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:InnerReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

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
Set-RingVisualsVisible -Visible $false

$script:Window.Add_SourceInitialized({
  $handle = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
  [CodexPetLimitRingNative]::MakeClickThrough($handle)
})

if (-not $NoTrayIcon) {
  $script:NotifyIcon = [System.Windows.Forms.NotifyIcon]::new()
  $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
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
    if (Update-StyleFromSettings) {
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
})

try {
  $script:App.Run() | Out-Null
} catch {
  Write-AppLog "Fatal error: $($_.Exception.Message)"
  throw
}
