param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$NoLiveUsage,
  [int]$UsagePollSeconds = 10,
  [int]$FramePollMs = 120,
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
$script:SettingsLastWriteTimeUtc = [datetime]::MinValue
$script:Style = [ordered]@{
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
  if ($total -ge 86400) {
    $days = [int][Math]::Floor($total / 86400)
    $hours = [int][Math]::Floor(($total % 86400) / 3600)
    return "{0}d {1}h" -f $days, $hours
  }
  if ($total -ge 3600) {
    $hours = [int][Math]::Floor($total / 3600)
    $minutes = [int][Math]::Floor(($total % 3600) / 60)
    return "{0}h {1}m" -f $hours, $minutes
  }
  if ($total -ge 60) {
    $minutes = [int][Math]::Floor($total / 60)
    $seconds = $total % 60
    return "{0}m {1}s" -f $minutes, $seconds
  }
  return "{0}s" -f $total
}

function Format-ResetDetail {
  param($ResetAt)
  if ($null -eq $ResetAt) { return "Reset --" }
  $reset = [datetime]$ResetAt
  $remaining = ($reset - (Get-Date)).TotalSeconds
  $timeText = if ($reset.Date -eq (Get-Date).Date) {
    $reset.ToString("HH:mm")
  } else {
    $reset.ToString("MMM d HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
  }
  return "Reset {0} ({1})" -f (Format-Duration $remaining), $timeText
}

function Format-WindowLabel {
  param($Seconds, [string]$Fallback)
  if ($null -eq $Seconds) { return $Fallback }
  $value = [double]$Seconds
  if ([Math]::Abs($value - 18000.0) -lt 180.0) { return "5h" }
  if ([Math]::Abs($value - 604800.0) -lt 3600.0) { return "Weekly" }
  if ($value -ge 86400.0) { return "{0:N0}d" -f ($value / 86400.0) }
  if ($value -ge 3600.0) { return "{0:N0}h" -f ($value / 3600.0) }
  return "{0:N0}m" -f ($value / 60.0)
}

function Get-RingReadoutText {
  param([ValidateSet("Outer", "Inner")][string]$Ring)
  if ($Ring -eq "Outer") {
    $label = Format-WindowLabel -Seconds $script:UsageState.PrimaryWindowSeconds -Fallback "5h"
    return "{0} limit  {1} left`n{2}" -f `
      $label,
      (Format-Percent $script:UsageState.PrimaryRemaining),
      (Format-ResetDetail $script:UsageState.PrimaryResetAt)
  }

  $label = Format-WindowLabel -Seconds $script:UsageState.SecondaryWindowSeconds -Fallback "Weekly"
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
}

function Set-ReadoutNearPoint {
  param($Border, [double]$X, [double]$Y, [double]$Size)
  $Border.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $width = [double]$Border.DesiredSize.Width
  $height = [double]$Border.DesiredSize.Height
  $left = $X + 12.0
  if (($left + $width) -gt ($Size - 4.0)) {
    $left = $X - $width - 12.0
  }
  $top = $Y - $height / 2.0
  $left = [Math]::Max(4.0, [Math]::Min($left, $Size - $width - 4.0))
  $top = [Math]::Max(4.0, [Math]::Min($top, $Size - $height - 4.0))
  [System.Windows.Controls.Canvas]::SetLeft($Border, $left)
  [System.Windows.Controls.Canvas]::SetTop($Border, $top)
}

function Show-RingReadout {
  param([ValidateSet("Outer", "Inner")][string]$Ring, [double]$X, [double]$Y, [double]$Size)
  if ($Ring -eq "Outer") {
    $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
    Set-ReadoutNearPoint -Border $script:OuterReadoutBorder -X $X -Y $Y -Size $Size
    $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
    return
  }

  $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  Set-ReadoutNearPoint -Border $script:InnerReadoutBorder -X $X -Y $Y -Size $Size
  $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
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
  $ringSize = [Math]::Max([double]$rect.Width, [double]$rect.Height) + $RingPadding * 2.0
  $windowSize = $ringSize + $ReadoutPadding * 2.0
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

  if (-not $script:Window.IsVisible) { $script:Window.Show() }
  Set-FrameTimerActive -Active $true
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
  $text = "Codex Rings: {0} 5h, {1} weekly" -f `
    (Format-Percent $script:UsageState.PrimaryRemaining), `
    (Format-Percent $script:UsageState.SecondaryRemaining)
  if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
  $script:NotifyIcon.Text = $text
}

function Stop-RingsApp {
  Write-AppLog "Stopping Codex Pet Limit Rings for Windows."
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

$script:Canvas.Children.Add($script:OuterTrack) | Out-Null
$script:Canvas.Children.Add($script:InnerTrack) | Out-Null
$script:Canvas.Children.Add($script:OuterArc) | Out-Null
$script:Canvas.Children.Add($script:InnerArc) | Out-Null
$script:Canvas.Children.Add($script:OuterReadoutBorder) | Out-Null
$script:Canvas.Children.Add($script:InnerReadoutBorder) | Out-Null

$script:Window.Add_SourceInitialized({
  $handle = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
  [CodexPetLimitRingNative]::MakeClickThrough($handle)
})

if (-not $NoTrayIcon) {
  $script:NotifyIcon = [System.Windows.Forms.NotifyIcon]::new()
  $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
  $script:NotifyIcon.Text = "Codex Rings"
  $script:NotifyIcon.Visible = $true
  $menu = [System.Windows.Forms.ContextMenuStrip]::new()
  $showItem = [System.Windows.Forms.ToolStripMenuItem]::new("Show Rings")
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
  $refreshItem = [System.Windows.Forms.ToolStripMenuItem]::new("Refresh Now")
  $refreshItem.Add_Click({ Update-UsageState; Update-PetFrame })
  $settingsItem = [System.Windows.Forms.ToolStripMenuItem]::new("Settings")
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
  $openLogsItem = [System.Windows.Forms.ToolStripMenuItem]::new("Open Logs")
  $openLogsItem.Add_Click({
    try { [System.Diagnostics.Process]::Start("explorer.exe", $LogDirectory) | Out-Null } catch {}
  })
  $quitItem = [System.Windows.Forms.ToolStripMenuItem]::new("Quit")
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
