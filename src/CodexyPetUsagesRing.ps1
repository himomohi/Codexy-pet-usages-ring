param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [switch]$NoLiveUsage,
  [int]$UsagePollSeconds = 10,
  [int]$FramePollMs = 60,
  [int]$KeyCounterPollMs = 16,
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
  [switch]$NoExitWithCodex,
  [switch]$NoTrayIcon
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "Codexy pet usages ring can only run on Windows."
}

$UsagePollSeconds = [Math]::Max(5, $UsagePollSeconds)
$FramePollMs = [Math]::Max(24, $FramePollMs)
$KeyCounterPollMs = [Math]::Max(8, $KeyCounterPollMs)
$IdleFramePollMs = [Math]::Max($FramePollMs, $IdleFramePollMs)
$PetPollMs = [Math]::Max(150, $PetPollMs)
$UsageAnimationFactor = [Math]::Max(0.01, [Math]::Min(1.0, $UsageAnimationFactor))
$RingPadding = [Math]::Max(12.0, $RingPadding)
$ReadoutPadding = [Math]::Max(0.0, $ReadoutPadding)
$OuterStroke = [Math]::Max(1.0, $OuterStroke)
$InnerStroke = [Math]::Max(1.0, $InnerStroke)

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
  $LogDirectory = Join-Path $env:LOCALAPPDATA "CodexyPetUsagesRing\logs"
}
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$script:LogFile = Join-Path $LogDirectory "codexy-pet-usages-ring.log"

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

Write-AppLog "Starting Codexy pet usages ring."

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
using System.Threading;

public static class CodexPetLimitRingNative {
    private const int GWL_EXSTYLE = -20;
    private static readonly IntPtr WS_EX_TRANSPARENT = new IntPtr(0x00000020);
    private static readonly IntPtr WS_EX_TOOLWINDOW = new IntPtr(0x00000080);
    private static readonly IntPtr WS_EX_NOACTIVATE = new IntPtr(0x08000000);
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_NOOWNERZORDER = 0x0200;
    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int VK_LBUTTON = 0x01;
    private static readonly IntPtr IDC_HAND = new IntPtr(32649);
    private static IntPtr keyboardHook = IntPtr.Zero;
    private static IntPtr mouseHook = IntPtr.Zero;
    private static IntPtr handCursor = IntPtr.Zero;
    private static LowLevelKeyboardProc keyboardProc = KeyboardHookCallback;
    private static LowLevelMouseProc mouseProc = MouseHookCallback;
    private static int pendingKeyPresses = 0;
    private static int pendingLeftMouseClicks = 0;
    private static int lastLeftClickX = 0;
    private static int lastLeftClickY = 0;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT {
        public POINT Pt;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
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

    [DllImport("user32.dll", SetLastError=true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", EntryPoint="SetWindowsHookEx", SetLastError=true)]
    private static extern IntPtr SetWindowsHookExMouse(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError=true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadCursor(IntPtr hInstance, IntPtr lpCursorName);

    [DllImport("user32.dll")]
    private static extern IntPtr SetCursor(IntPtr hCursor);

    public static void MakeClickThrough(IntPtr hWnd) {
        IntPtr style = GetWindowLongPtr64(hWnd, GWL_EXSTYLE);
        long newStyle = style.ToInt64()
            | WS_EX_TRANSPARENT.ToInt64()
            | WS_EX_TOOLWINDOW.ToInt64()
            | WS_EX_NOACTIVATE.ToInt64();
        SetWindowLongPtr64(hWnd, GWL_EXSTYLE, new IntPtr(newStyle));
    }

    public static bool InstallKeyboardCounter() {
        if (keyboardHook != IntPtr.Zero) {
            return true;
        }
        try {
            using (Process process = Process.GetCurrentProcess()) {
                using (ProcessModule module = process.MainModule) {
                    keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardProc, GetModuleHandle(module.ModuleName), 0);
                }
            }
        } catch {
            keyboardHook = IntPtr.Zero;
        }
        return keyboardHook != IntPtr.Zero;
    }

    public static void UninstallKeyboardCounter() {
        if (keyboardHook != IntPtr.Zero) {
            try {
                UnhookWindowsHookEx(keyboardHook);
            } catch {
            }
            keyboardHook = IntPtr.Zero;
        }
        Interlocked.Exchange(ref pendingKeyPresses, 0);
    }

    public static int ConsumeKeyPresses() {
        return Interlocked.Exchange(ref pendingKeyPresses, 0);
    }

    public static bool InstallMouseClickCounter() {
        if (mouseHook != IntPtr.Zero) {
            return true;
        }
        try {
            using (Process process = Process.GetCurrentProcess()) {
                using (ProcessModule module = process.MainModule) {
                    mouseHook = SetWindowsHookExMouse(WH_MOUSE_LL, mouseProc, GetModuleHandle(module.ModuleName), 0);
                }
            }
        } catch {
            mouseHook = IntPtr.Zero;
        }
        return mouseHook != IntPtr.Zero;
    }

    public static void UninstallMouseClickCounter() {
        if (mouseHook != IntPtr.Zero) {
            try {
                UnhookWindowsHookEx(mouseHook);
            } catch {
            }
            mouseHook = IntPtr.Zero;
        }
        Interlocked.Exchange(ref pendingLeftMouseClicks, 0);
    }

    public static string ConsumeLeftMouseClick() {
        int clicks = Interlocked.Exchange(ref pendingLeftMouseClicks, 0);
        if (clicks <= 0) {
            return "";
        }
        return lastLeftClickX.ToString() + "," + lastLeftClickY.ToString() + "," + clicks.ToString();
    }

    public static bool IsLeftMouseButtonDown() {
        return (GetAsyncKeyState(VK_LBUTTON) & unchecked((short)0x8000)) != 0;
    }

    public static bool ConsumeLeftMouseButtonClick() {
        return (GetAsyncKeyState(VK_LBUTTON) & 0x0001) != 0;
    }

    public static void ShowHandCursor() {
        if (handCursor == IntPtr.Zero) {
            handCursor = LoadCursor(IntPtr.Zero, IDC_HAND);
        }
        if (handCursor != IntPtr.Zero) {
            SetCursor(handCursor);
        }
    }

    private static IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && (wParam.ToInt32() == WM_KEYDOWN || wParam.ToInt32() == WM_SYSKEYDOWN)) {
            Interlocked.Increment(ref pendingKeyPresses);
        }
        return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
    }

    private static IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam.ToInt32() == WM_LBUTTONDOWN) {
            try {
                MSLLHOOKSTRUCT data = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                Interlocked.Exchange(ref lastLeftClickX, data.Pt.X);
                Interlocked.Exchange(ref lastLeftClickY, data.Pt.Y);
                Interlocked.Increment(ref pendingLeftMouseClicks);
            } catch {
            }
        }
        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
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

    public static bool IsCodexDesktopRunning() {
        try {
            foreach (Process process in Process.GetProcessesByName("Codex")) {
                try {
                    string path = process.MainModule.FileName;
                    if (string.IsNullOrWhiteSpace(path)) {
                        continue;
                    }
                    if (path.EndsWith(@"resources\codex.exe", StringComparison.OrdinalIgnoreCase)) {
                        continue;
                    }
                    return true;
                } catch {
                    try {
                        if (!string.IsNullOrWhiteSpace(process.MainWindowTitle)) {
                            return true;
                        }
                    } catch {
                    }
                }
            }
        } catch {
        }
        return false;
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
$PetGrowthScriptPath = Join-Path $ProjectRoot "src\PetGrowth.ps1"
$RewardChestIconPath = Join-Path $ProjectRoot "assets\runtime\reward-chest.png"
$CosmeticThemeKeys = @("themeForest", "themeArcane", "themeRoyal", "themeCyber", "themeCelestial")
$CosmeticUnlockKeys = @("fontPixel", "fontTerminal") + $CosmeticThemeKeys
$ThemeBorderPaths = @{
  themeForest = Join-Path $ProjectRoot "assets\runtime\theme-forest-border.png"
  themeArcane = Join-Path $ProjectRoot "assets\runtime\theme-arcane-border.png"
  themeRoyal = Join-Path $ProjectRoot "assets\runtime\theme-royal-border.png"
  themeCyber = Join-Path $ProjectRoot "assets\runtime\theme-cyber-border.png"
  themeCelestial = Join-Path $ProjectRoot "assets\runtime\theme-celestial-border.png"
}
$InventoryIconPaths = @{
  fontPixel = Join-Path $ProjectRoot "assets\runtime\unlock-font-pixel.png"
  fontTerminal = Join-Path $ProjectRoot "assets\runtime\unlock-font-terminal.png"
  themeForest = Join-Path $ProjectRoot "assets\runtime\theme-forest-border.png"
  themeArcane = Join-Path $ProjectRoot "assets\runtime\unlock-theme-arcane.png"
  themeRoyal = Join-Path $ProjectRoot "assets\runtime\unlock-theme-royal.png"
  themeCyber = Join-Path $ProjectRoot "assets\runtime\theme-cyber-border.png"
  themeCelestial = Join-Path $ProjectRoot "assets\runtime\theme-celestial-border.png"
}
if (-not (Test-Path -LiteralPath $PetGrowthScriptPath)) {
  throw "Missing pet growth helper: $PetGrowthScriptPath"
}
. $PetGrowthScriptPath
$GamificationStatePath = Join-Path $env:LOCALAPPDATA "CodexyPetUsagesRing\gamification.json"
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
$script:BatteryPrimaryBounds = $null
$script:BatterySecondaryBounds = $null
$script:BadgePrimaryBounds = $null
$script:BadgeSecondaryBounds = $null
$script:GrowthChipBounds = $null
$script:KeyCounterBounds = $null
$script:InventoryBounds = $null
$script:InventoryHitBounds = $null
$script:InventoryReadoutPinned = $false
$script:LastReadoutRefreshAt = [datetime]::MinValue
$script:LastHoverSignature = ""
$script:RingVisualsVisible = $null
$script:RingAnimationToken = 0
$script:SettingsLastWriteTimeUtc = [datetime]::MinValue
$script:PetGrowthState = New-PetGrowthState
$script:LastGrowthSaveAt = [datetime]::MinValue
$script:KeyCounterInstalled = $false
$script:KeyPressCount = 0
$script:KeyComboCount = 0
$script:KeyComboMultiplier = 1
$script:KeyFlowState = ""
$script:KeyFlowStateUntil = [datetime]::MinValue
$script:LastKeyInputAt = [datetime]::MinValue
$script:LastKeyBurstAt = [datetime]::MinValue
$script:LastKeyCounterDigits = 1
$script:LastKeyCounterVisualSignature = ""
$script:LastKeyCounterIdleSyncAt = [datetime]::MinValue
$script:LastKeyHookAttemptAt = [datetime]::MinValue
$script:KeyHookFailureLogged = $false
$script:LastKeyRestBonusAt = [datetime]::MinValue
$script:MouseClickCounterInstalled = $false
$script:LastMouseHookAttemptAt = [datetime]::MinValue
$script:MouseHookFailureLogged = $false
$script:LastInventoryToggleAt = [datetime]::MinValue
$script:InventoryMouseWasDown = $false
$script:InventoryItemLabelBlocks = @{}
$script:InventoryItemCountBlocks = @{}
$script:InventoryItemBorders = @{}
$script:InventoryPickerKind = ""
$script:HudCenterX = $null
$script:HudRingSize = $null
$script:Style = [ordered]@{
  Language = "auto"
  DisplayMode = "ring"
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
  VisibilityMode = "hover"
  HoverRange = 24.0
  FadeInMs = 120.0
  FadeOutMs = 180.0
  GamificationEnabled = $false
  GrowthMode = "balanced"
  GamificationHudFocus = "growth"
  ShowGrowthChip = $true
  ShowGrowthHoverReadout = $true
  ShowKeyCounter = $true
  ShowKeyEffects = $true
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

function New-RuntimeImageSource {
  param([string]$Path, [string]$Name, [int]$DecodePixelWidth = 64)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.UriSource = [System.Uri]::new($Path, [System.UriKind]::Absolute)
    $bitmap.DecodePixelWidth = $DecodePixelWidth
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
  } catch {
    Write-AppLog "$Name icon load failed: $($_.Exception.Message)"
    return $null
  }
}

function New-RewardChestImageSource {
  return New-RuntimeImageSource -Path $RewardChestIconPath -Name "Reward chest" -DecodePixelWidth 64
}

function Get-ActiveThemeBorderPath {
  $inventory = Get-InventoryState
  $theme = [string]$inventory.activeTheme
  if ([string]::IsNullOrWhiteSpace($theme) -or -not $ThemeBorderPaths.ContainsKey($theme)) { return "" }
  return [string]$ThemeBorderPaths[$theme]
}

function New-ActiveThemeBorderImageSource {
  $path = Get-ActiveThemeBorderPath
  if ([string]::IsNullOrWhiteSpace($path)) { return $null }
  return New-RuntimeImageSource -Path $path -Name "Theme counter border" -DecodePixelWidth 192
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

function Convert-SettingBool {
  param($Value, [bool]$Fallback)
  if ($null -eq $Value) { return $Fallback }
  if ($Value -is [bool]) { return [bool]$Value }
  $text = ([string]$Value).Trim().ToLowerInvariant()
  if ($text -in @("true", "1", "yes", "on")) { return $true }
  if ($text -in @("false", "0", "no", "off")) { return $false }
  return $Fallback
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
    displayMode = "ring"
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
      visibilityMode = "hover"
      hoverRange = 24
      fadeInMs = 120
      fadeOutMs = 180
    }
    gamification = [ordered]@{
      enabled = $false
      growthMode = "balanced"
      hudFocus = "growth"
      showGrowthChip = $true
      showHoverReadout = $true
      showKeyCounter = $true
      showKeyEffects = $true
    }
  }
  ($fallback | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Read-PetGrowthState {
  try {
    if (-not (Test-Path -LiteralPath $GamificationStatePath)) {
      return New-PetGrowthState
    }
    $raw = Read-Utf8Text -Path $GamificationStatePath
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return New-PetGrowthState
    }
    return Normalize-PetGrowthState -State ($raw | ConvertFrom-Json)
  } catch {
    Write-AppLog "Pet growth state read failed: $($_.Exception.Message)"
    return New-PetGrowthState
  }
}

function Save-PetGrowthState {
  param([switch]$Force)
  try {
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastGrowthSaveAt).TotalSeconds -lt 30) {
      return
    }
    $stateDirectory = Split-Path -Parent $GamificationStatePath
    if (-not [string]::IsNullOrWhiteSpace($stateDirectory)) {
      New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    }
    $json = ($script:PetGrowthState | ConvertTo-Json -Depth 8) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($GamificationStatePath, $json, [System.Text.Encoding]::UTF8)
    $script:LastGrowthSaveAt = $now
  } catch {
    Write-AppLog "Pet growth state save failed: $($_.Exception.Message)"
  }
}

$script:PetGrowthState = Read-PetGrowthState

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
    $gamification = Get-PropertyValue $settings "gamification" $null

    $language = ([string](Get-PropertyValue $settings "language" "auto")).Trim().ToLowerInvariant()
    if ($language -notin @("auto", "ko", "en", "ja", "zh")) { $language = "auto" }
    $displayMode = ([string](Get-PropertyValue $settings "displayMode" "ring")).Trim().ToLowerInvariant()
    if ($displayMode -notin @("ring", "battery", "badge")) { $displayMode = "ring" }
    $script:Style.Language = $language
    $script:Style.DisplayMode = $displayMode
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
    $visibilityMode = ([string](Get-PropertyValue $behavior "visibilityMode" "hover")).Trim().ToLowerInvariant()
    if ($visibilityMode -notin @("hover", "always")) { $visibilityMode = "hover" }
    $script:Style.VisibilityMode = $visibilityMode
    $script:Style.HoverRange = Convert-SettingNumber (Get-PropertyValue $behavior "hoverRange" $null) 24 0 96
    $script:Style.FadeInMs = Convert-SettingNumber (Get-PropertyValue $behavior "fadeInMs" $null) 120 0 1000
    $script:Style.FadeOutMs = Convert-SettingNumber (Get-PropertyValue $behavior "fadeOutMs" $null) 180 0 1000
    $script:Style.GamificationEnabled = Convert-SettingBool (Get-PropertyValue $gamification "enabled" $null) $false
    $growthMode = ([string](Get-PropertyValue $gamification "growthMode" "balanced")).Trim().ToLowerInvariant()
    if ($growthMode -notin @("conserve", "balanced", "active")) { $growthMode = "balanced" }
    $script:Style.GrowthMode = $growthMode
    $hudFocus = ([string](Get-PropertyValue $gamification "hudFocus" "growth")).Trim().ToLowerInvariant()
    if ($hudFocus -notin @("growth", "combo")) { $hudFocus = "growth" }
    $script:Style.GamificationHudFocus = $hudFocus
    $script:Style.ShowGrowthChip = Convert-SettingBool (Get-PropertyValue $gamification "showGrowthChip" $null) $true
    $script:Style.ShowGrowthHoverReadout = Convert-SettingBool (Get-PropertyValue $gamification "showHoverReadout" $null) $true
    $script:Style.ShowKeyCounter = Convert-SettingBool (Get-PropertyValue $gamification "showKeyCounter" $null) $true
    $script:Style.ShowKeyEffects = Convert-SettingBool (Get-PropertyValue $gamification "showKeyEffects" $null) $true
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
  foreach ($track in @($script:PrimaryBatteryTrack, $script:SecondaryBatteryTrack)) {
    if ($null -ne $track) {
      $track.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
      $track.Fill = New-StyleBrush ([byte][Math]::Max(8, [Math]::Min(255, [int]$script:Style.TrackOpacity + 12))) ([int[]]$script:Style.TrackRgb)
    }
  }
  foreach ($cap in @($script:PrimaryBatteryCap, $script:SecondaryBatteryCap)) {
    if ($null -ne $cap) {
      $cap.Fill = New-StyleBrush ([byte][Math]::Max(22, [Math]::Min(255, [int]$script:Style.TrackOpacity + 28))) ([int[]]$script:Style.TrackRgb)
    }
  }
  foreach ($label in @($script:PrimaryBatteryLabel, $script:SecondaryBatteryLabel)) {
    if ($null -ne $label) {
      $label.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    }
  }
  if ($null -ne $script:BadgeBackground) {
    $script:BadgeBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
    $script:BadgeBackground.Stroke = New-StyleBrush ([byte][Math]::Max(20, [Math]::Min(255, [int]$script:Style.TrackOpacity + 34))) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:BadgeDivider) {
    $script:BadgeDivider.Fill = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 26))) ([int[]]$script:Style.TrackRgb)
  }
  foreach ($label in @($script:PrimaryBadgeLabel, $script:SecondaryBadgeLabel)) {
    if ($null -ne $label) {
      $label.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    }
  }
  if ($null -ne $script:GrowthChipBackground) {
    $script:GrowthChipBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
    $script:GrowthChipBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 36))) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:GrowthChipAccent) {
    $script:GrowthChipAccent.Fill = Get-PetGrowthBrush -Condition ([string]$script:PetGrowthState.condition)
  }
  if ($null -ne $script:GrowthChipLabel) {
    $script:GrowthChipLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
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
  if ($null -ne $script:GrowthReadoutText) {
    $script:GrowthReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    $script:GrowthReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
    $script:GrowthReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
  }
  if ($null -ne $script:InventoryReadoutText) {
    $script:InventoryReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
    $script:InventoryReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
    $script:InventoryReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
  }
  if ($null -ne $script:GrowthReadoutBorder) {
    $script:GrowthReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
  }
  if ($null -ne $script:InventoryReadoutBorder) {
    $script:InventoryReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
  }
  if ($null -ne $script:InventoryReadoutTitle) {
    $script:InventoryReadoutTitle.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
  }
  if ($null -ne $script:InventoryReadoutStats) {
    $script:InventoryReadoutStats.Foreground = New-StyleBrush ([byte][Math]::Max(120, [Math]::Min(255, [int]$script:Style.ReadoutTextOpacity - 24))) ([int[]]$script:Style.ReadoutTextRgb)
  }
  if ($null -ne $script:InventoryReadoutHint) {
    $script:InventoryReadoutHint.Foreground = New-StyleBrush ([byte][Math]::Max(112, [Math]::Min(255, [int]$script:Style.ReadoutTextOpacity - 38))) ([int[]]$script:Style.ReadoutTextRgb)
  }
  foreach ($countBlock in $script:InventoryItemCountBlocks.Values) {
    $countBlock.Foreground = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
  }
  if ($null -ne $script:KeyCounterBackground) {
    $script:KeyCounterBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
    $script:KeyCounterBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 42))) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:KeyCounterAccent) {
    $script:KeyCounterAccent.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
  }
  if ($null -ne $script:KeyCounterLabel) {
    $script:KeyCounterLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
  }
  if ($null -ne $script:InventoryBackground) {
    $script:InventoryBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
    $script:InventoryBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 36))) ([int[]]$script:Style.TrackRgb)
  }
  if ($null -ne $script:InventoryHoverBorder) {
    $script:InventoryHoverBorder.Stroke = New-Brush 236 255 218 0
    $script:InventoryHoverBorder.Fill = New-Brush 22 255 218 0
  }
  if ($null -ne $script:InventoryCountBackground) {
    $script:InventoryCountBackground.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
  }
  if ($null -ne $script:InventoryLabel) {
    $script:InventoryLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
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
    "TrayTitle" { return "Codexy" }
    "TrayText" { return "Codexy: {0} 5h, {1} weekly" }
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

function Set-RectangleBounds {
  param($Rectangle, [double]$X, [double]$Y, [double]$Width, [double]$Height)
  if ($null -eq $Rectangle) { return }
  $Rectangle.Width = [Math]::Max(0.0, $Width)
  $Rectangle.Height = [Math]::Max(0.0, $Height)
  [System.Windows.Controls.Canvas]::SetLeft($Rectangle, $X)
  [System.Windows.Controls.Canvas]::SetTop($Rectangle, $Y)
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

function Get-PetGrowthConditionLabel {
  param([string]$Condition)
  $language = Get-EffectiveLanguage
  switch ($Condition) {
    "healthy" {
      if ($language -eq "ko") { return (Expand-UnicodeText "\uC2E0\uB0A8") }
      if ($language -eq "ja") { return (Expand-UnicodeText "\u3052\u3093\u304D") }
      if ($language -eq "zh") { return (Expand-UnicodeText "\u5174\u594B") }
      return "Hyped"
    }
    "stable" {
      if ($language -eq "ko") { return (Expand-UnicodeText "\uBAB8\uD480\uAE30") }
      if ($language -eq "ja") { return (Expand-UnicodeText "\u30A6\u30A9\u30FC\u30E0\u30A2\u30C3\u30D7") }
      if ($language -eq "zh") { return (Expand-UnicodeText "\u70ED\u8EAB\u4E2D") }
      return "Warming Up"
    }
    "tired" {
      if ($language -eq "ko") { return (Expand-UnicodeText "\uACFC\uC5F4") }
      if ($language -eq "ja") { return (Expand-UnicodeText "\u30AA\u30FC\u30D0\u30FC\u30D2\u30FC\u30C8") }
      if ($language -eq "zh") { return (Expand-UnicodeText "\u8FC7\u70ED") }
      return "Overheated"
    }
    "sleepy" {
      if ($language -eq "ko") { return (Expand-UnicodeText "\uCFE8\uB2E4\uC6B4") }
      if ($language -eq "ja") { return (Expand-UnicodeText "\u30AF\u30FC\u30EB\u30C0\u30A6\u30F3") }
      if ($language -eq "zh") { return (Expand-UnicodeText "\u51B7\u5374\u4E2D") }
      return "Cooldown"
    }
    default {
      if ($language -eq "ko") { return (Expand-UnicodeText "\uB300\uAE30\uC911") }
      if ($language -eq "ja") { return (Expand-UnicodeText "\u5F85\u6A5F\u4E2D") }
      if ($language -eq "zh") { return (Expand-UnicodeText "\u5F85\u673A\u4E2D") }
      return "Standby"
    }
  }
}

function Get-PetGrowthChipText {
  $level = [int]$script:PetGrowthState.level
  $condition = Get-PetGrowthConditionLabel -Condition ([string]$script:PetGrowthState.condition)
  return "Lv{0} {1}" -f $level, $condition
}

function Get-PetGrowthReadoutText {
  $language = Get-EffectiveLanguage
  $level = [int]$script:PetGrowthState.level
  $totalXp = [int]$script:PetGrowthState.totalXp
  $nextXp = Get-PetGrowthNextLevelXp -TotalXp $totalXp
  $condition = Get-PetGrowthConditionLabel -Condition ([string]$script:PetGrowthState.condition)
  $todayUsed = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, [double]$script:PetGrowthState.todayPrimaryUsedPercent)), 0)
  $todayTarget = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, [double]$script:PetGrowthState.todayTargetUsedPercent)), 0)
  if ($todayTarget -le 0) {
    $todayTarget = [Math]::Round((Get-PetGrowthPrimaryTargetUsed -GrowthMode ([string]$script:Style.GrowthMode)), 0)
  }
  $todayXp = [int]$script:PetGrowthState.todayXp
  $todayGrowth = if ($language -eq "ko") {
    "5h {0}%/{1}%  +{2} XP" -f $todayUsed, $todayTarget, $todayXp
  } elseif ($language -eq "ja") {
    "5h {0}%/{1}%  +{2} XP" -f $todayUsed, $todayTarget, $todayXp
  } elseif ($language -eq "zh") {
    "5h {0}%/{1}%  +{2} XP" -f $todayUsed, $todayTarget, $todayXp
  } else {
    "5h {0}%/{1}%  +{2} XP" -f $todayUsed, $todayTarget, $todayXp
  }
  if ($null -eq $nextXp) {
    if ($language -eq "ko") { return (Expand-UnicodeText "Lv{0} {1}`n\uCD5C\uB300 \uB808\uBCA8  XP {2}`n\uC624\uB298 \uC131\uC7A5 {3}") -f $level, $condition, $totalXp, $todayGrowth }
    if ($language -eq "ja") { return (Expand-UnicodeText "Lv{0} {1}`n\u6700\u5927\u30EC\u30D9\u30EB  XP {2}`n\u4ECA\u65E5\u306E\u6210\u9577 {3}") -f $level, $condition, $totalXp, $todayGrowth }
    if ($language -eq "zh") { return (Expand-UnicodeText "Lv{0} {1}`n\u5DF2\u8FBE\u6700\u9AD8\u7B49\u7EA7  XP {2}`n\u4ECA\u65E5\u6210\u957F {3}") -f $level, $condition, $totalXp, $todayGrowth }
    return "Lv{0} {1}`nMax level  XP {2}`nGrowth today {3}" -f $level, $condition, $totalXp, $todayGrowth
  }
  $toNext = [Math]::Max(0, [int]$nextXp - $totalXp)
  if ($language -eq "ko") { return (Expand-UnicodeText "Lv{0} {1}`n\uB2E4\uC74C \uB808\uBCA8\uAE4C\uC9C0 {2} XP`n\uC624\uB298 \uC131\uC7A5 {3}") -f $level, $condition, $toNext, $todayGrowth }
  if ($language -eq "ja") { return (Expand-UnicodeText "Lv{0} {1}`n\u6B21\u306E\u30EC\u30D9\u30EB\u307E\u3067 {2} XP`n\u4ECA\u65E5\u306E\u6210\u9577 {3}") -f $level, $condition, $toNext, $todayGrowth }
  if ($language -eq "zh") { return (Expand-UnicodeText "Lv{0} {1}`n\u8DDD\u4E0B\u4E00\u7EA7 {2} XP`n\u4ECA\u65E5\u6210\u957F {3}") -f $level, $condition, $toNext, $todayGrowth }
  return "Lv{0} {1}`n{2} XP to next`nGrowth today {3}" -f $level, $condition, $toNext, $todayGrowth
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
  if ($null -ne $script:GrowthReadoutText) {
    $script:GrowthReadoutText.Text = Get-PetGrowthReadoutText
  }
  Update-InventoryReadoutContent
  $script:LastReadoutRefreshAt = $now
  return $true
}

function Test-InventoryReadoutOpen {
  return (
    $null -ne $script:InventoryReadoutWindow -and
    $script:InventoryReadoutWindow.IsVisible -and
    [bool]$script:InventoryReadoutPinned
  )
}

function Set-InventoryHoverHighlight {
  param([bool]$Visible)
  if ($null -eq $script:InventoryHoverBorder) { return }
  if (
    -not $Visible -or
    $null -eq $script:InventoryHitBounds -or
    -not (Test-InventoryHudVisible)
  ) {
    $script:InventoryHoverBorder.Visibility = [System.Windows.Visibility]::Collapsed
    return
  }

  $bounds = $script:InventoryHitBounds
  Set-RectangleBounds $script:InventoryHoverBorder ([double]$bounds.X) ([double]$bounds.Y) ([double]$bounds.Width) ([double]$bounds.Height)
  $script:InventoryHoverBorder.Visibility = [System.Windows.Visibility]::Visible
}

function Hide-InventoryReadout {
  param([switch]$ResetPinned)
  if ($ResetPinned) { $script:InventoryReadoutPinned = $false }
  if ($null -ne $script:InventoryPickerBorder) {
    $script:InventoryPickerBorder.Visibility = [System.Windows.Visibility]::Collapsed
  }
  if ($null -ne $script:InventoryPickerWindow -and $script:InventoryPickerWindow.IsVisible) {
    $script:InventoryPickerWindow.Hide()
  }
  if ($null -ne $script:InventoryReadoutBorder) {
    $script:InventoryReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  }
  if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
    $script:InventoryReadoutWindow.Hide()
  }
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
  if ($null -ne $script:GrowthReadoutBorder) {
    $script:GrowthReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  }
  if ($null -ne $script:GrowthReadoutWindow -and $script:GrowthReadoutWindow.IsVisible) {
    $script:GrowthReadoutWindow.Hide()
  }
  if (-not (Test-InventoryReadoutOpen)) {
    Hide-InventoryReadout -ResetPinned
  }
}

function Set-RingShapesVisibility {
  param([System.Windows.Visibility]$Visibility)
  foreach ($shape in @(
    $script:OuterTrack,
    $script:InnerTrack,
    $script:OuterArc,
    $script:InnerArc,
    $script:PrimaryBatteryTrack,
    $script:PrimaryBatteryFill,
    $script:PrimaryBatteryCap,
    $script:PrimaryBatteryLabel,
    $script:SecondaryBatteryTrack,
    $script:SecondaryBatteryFill,
    $script:SecondaryBatteryCap,
    $script:SecondaryBatteryLabel,
    $script:BadgeBackground,
    $script:PrimaryBadgeChip,
    $script:SecondaryBadgeChip,
    $script:BadgeDivider,
    $script:PrimaryBadgeLabel,
    $script:SecondaryBadgeLabel,
    $script:GrowthChipBackground,
    $script:GrowthChipAccent,
    $script:GrowthChipLabel,
    $script:KeyCounterBackground,
    $script:KeyCounterThemeBorder,
    $script:KeyCounterLabel,
    $script:InventoryBackground,
    $script:InventoryIcon,
    $script:InventoryCountBackground,
    $script:InventoryLabel
  )) {
    if ($null -ne $shape) {
      $shape.Visibility = $Visibility
    }
  }
}

function Update-ModeShapeVisibility {
  if ($null -eq $script:Window) { return }
  $ringVisibility = if ($script:Style.DisplayMode -eq "ring") {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  $batteryVisibility = if ($script:Style.DisplayMode -eq "battery") {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  $badgeVisibility = if ($script:Style.DisplayMode -eq "badge") {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  foreach ($shape in @($script:OuterTrack, $script:InnerTrack, $script:OuterArc, $script:InnerArc)) {
    if ($null -ne $shape) { $shape.Visibility = $ringVisibility }
  }
  foreach ($shape in @(
    $script:PrimaryBatteryTrack,
    $script:PrimaryBatteryFill,
    $script:PrimaryBatteryCap,
    $script:PrimaryBatteryLabel,
    $script:SecondaryBatteryTrack,
    $script:SecondaryBatteryFill,
    $script:SecondaryBatteryCap,
    $script:SecondaryBatteryLabel
  )) {
    if ($null -ne $shape) { $shape.Visibility = $batteryVisibility }
  }
  foreach ($shape in @(
    $script:BadgeBackground,
    $script:PrimaryBadgeChip,
    $script:SecondaryBadgeChip,
    $script:BadgeDivider,
    $script:PrimaryBadgeLabel,
    $script:SecondaryBadgeLabel
  )) {
    if ($null -ne $shape) { $shape.Visibility = $badgeVisibility }
  }
  $growthVisibility = if (
    $script:RingVisualsVisible -and
    (Test-GrowthHudVisible)
  ) {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  foreach ($shape in @($script:GrowthChipBackground, $script:GrowthChipAccent, $script:GrowthChipLabel)) {
    if ($null -ne $shape) { $shape.Visibility = $growthVisibility }
  }

  $keyCounterVisibility = if (
    $script:RingVisualsVisible -and
    (Test-KeyCounterHudVisible)
  ) {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  foreach ($shape in @($script:KeyCounterBackground, $script:KeyCounterLabel)) {
    if ($null -ne $shape) { $shape.Visibility = $keyCounterVisibility }
  }
  if ($null -ne $script:KeyCounterThemeBorder) {
    $script:KeyCounterThemeBorder.Visibility = if (
      $keyCounterVisibility -eq [System.Windows.Visibility]::Visible -and
      -not [string]::IsNullOrWhiteSpace((Get-ActiveThemeBorderPath))
    ) {
      [System.Windows.Visibility]::Visible
    } else {
      [System.Windows.Visibility]::Collapsed
    }
  }
  if ($null -ne $script:KeyCounterAccent) { $script:KeyCounterAccent.Visibility = [System.Windows.Visibility]::Collapsed }
  $inventoryVisibility = if (
    $script:RingVisualsVisible -and
    (Test-InventoryHudVisible)
  ) {
    [System.Windows.Visibility]::Visible
  } else {
    [System.Windows.Visibility]::Collapsed
  }
  foreach ($shape in @($script:InventoryIcon, $script:InventoryCountBackground, $script:InventoryLabel)) {
    if ($null -ne $shape) { $shape.Visibility = $inventoryVisibility }
  }
}

function Get-PetGrowthBrush {
  param([string]$Condition)
  switch ($Condition) {
    "healthy" { return New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb) }
    "stable" { return New-StyleBrush ([byte]$script:Style.SecondaryOpacity) ([int[]]$script:Style.SecondaryRgb) }
    "tired" { return New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.CautionRgb) }
    "sleepy" { return New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.WarningRgb) }
    default { return New-StyleBrush ([byte][Math]::Max(32, [Math]::Min(255, [int]$script:Style.TrackOpacity + 42))) ([int[]]$script:Style.TrackRgb) }
  }
}

function Update-PetGrowthVisualText {
  if ($null -ne $script:GrowthChipLabel) {
    $script:GrowthChipLabel.Text = Get-PetGrowthChipText
  }
  if ($null -ne $script:GrowthChipAccent) {
    $script:GrowthChipAccent.Fill = Get-PetGrowthBrush -Condition ([string]$script:PetGrowthState.condition)
  }
  if ($null -ne $script:GrowthReadoutText) {
    $script:GrowthReadoutText.Text = Get-PetGrowthReadoutText
  }
}

function Test-GrowthHudVisible {
  return ($script:Style.GamificationEnabled -and $script:Style.ShowGrowthChip -and [string]$script:Style.GamificationHudFocus -eq "growth")
}

function Test-KeyCounterHudVisible {
  return ([bool]$script:Style.GamificationEnabled -and [bool]$script:Style.ShowKeyCounter -and [string]$script:Style.GamificationHudFocus -eq "combo")
}

function Test-InventoryHudVisible {
  return ((Test-KeyCounterHudVisible) -and [string]$script:Style.DisplayMode -ne "badge")
}

function Get-GrowthChipWidth {
  $text = Get-PetGrowthChipText
  return [Math]::Max(104.0, [Math]::Min(132.0, 30.0 + ([double]$text.Length * 9.0)))
}

function Get-KeyCounterChipWidth {
  param([string]$Mode = "")
  $digits = ([string]([int]$script:KeyPressCount)).Length
  $status = Get-KeyCounterStatusText
  $digitWidth = 42.0 + ($digits * 17.0)
  $statusWidth = if ([string]::IsNullOrWhiteSpace($status)) { 0.0 } else { [Math]::Min(148.0, 44.0 + ([double]$status.Length * 9.2)) }
  if ($Mode -eq "badge") { return [Math]::Max(72.0, [Math]::Max($digitWidth, $statusWidth)) }
  if ($Mode -eq "battery") { return [Math]::Max(98.0, [Math]::Max($digitWidth, $statusWidth)) }
  return [Math]::Max(94.0, [Math]::Max($digitWidth, $statusWidth))
}

function Get-KeyCounterChipHeight {
  param([string]$Mode = "")
  $hasStatus = -not [string]::IsNullOrWhiteSpace((Get-KeyCounterStatusText))
  if ($hasStatus) {
    if ($Mode -eq "badge") { return 46.0 }
    return 52.0
  }
  if ($Mode -eq "badge") { return 32.0 }
  return 38.0
}

function Get-BatteryHudBarWidth {
  $baseWidth = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX * 2.0 } elseif ($null -ne $script:Window) { [double]$script:Window.Width } else { 164.0 }
  return [Math]::Min(132.0, [Math]::Max(96.0, $baseWidth - 22.0))
}

function Get-BadgeHudWidth {
  $baseWidth = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX * 2.0 } elseif ($null -ne $script:Window) { [double]$script:Window.Width } else { 164.0 }
  if (Test-KeyCounterHudVisible) {
    return [Math]::Min(246.0, [Math]::Max(226.0, $baseWidth - 8.0))
  }
  return [Math]::Min(156.0, [Math]::Max(128.0, $baseWidth - 18.0))
}

function Get-KeyCounterText {
  $status = Get-KeyCounterStatusText
  if ([string]::IsNullOrWhiteSpace($status)) {
    return "{0}" -f ([int]$script:KeyPressCount)
  }
  return "{0}`n{1}" -f ([int]$script:KeyPressCount), $status
}

function Get-KeyCounterStatusText {
  if ([string]$script:Style.GamificationHudFocus -ne "combo") { return "" }
  $now = Get-Date
  if ($script:KeyFlowStateUntil -gt $now -and -not [string]::IsNullOrWhiteSpace([string]$script:KeyFlowState)) {
    return [string]$script:KeyFlowState
  }
  if ($script:LastKeyInputAt -ne [datetime]::MinValue -and ($now - $script:LastKeyInputAt).TotalSeconds -gt 8.5) {
    return ""
  }
  if ([int]$script:KeyComboMultiplier -gt 1) {
    return "x{0} {1}" -f ([int]$script:KeyComboMultiplier), (Get-KeyFlowName -Multiplier ([int]$script:KeyComboMultiplier) -ComboCount ([int]$script:KeyComboCount))
  }
  return ""
}

function Get-InventoryState {
  $inventory = $script:PetGrowthState.PSObject.Properties["inventory"]
  if ($null -eq $inventory -or $null -eq $inventory.Value) {
    $script:PetGrowthState = Normalize-PetGrowthState -State $script:PetGrowthState
    return $script:PetGrowthState.inventory
  }
  return $inventory.Value
}

function Get-InventoryUnlockCount {
  param($Inventory)
  if ($null -eq $Inventory) { return 0 }
  $count = 0
  foreach ($key in $CosmeticUnlockKeys) {
    try {
      if ([bool]$Inventory.$key) { $count++ }
    } catch {}
  }
  return $count
}

function Get-CosmeticFontFamily {
  $inventory = Get-InventoryState
  switch ([string]$inventory.activeFont) {
    "fontPixel" { return [System.Windows.Media.FontFamily]::new("Courier New") }
    "fontTerminal" { return [System.Windows.Media.FontFamily]::new("Consolas") }
    default { return [System.Windows.Media.FontFamily]::new("Segoe UI") }
  }
}

function Get-ActiveCosmeticKey {
  $inventory = Get-InventoryState
  if (-not [string]::IsNullOrWhiteSpace([string]$inventory.activeTheme)) { return [string]$inventory.activeTheme }
  if (-not [string]::IsNullOrWhiteSpace([string]$inventory.activeFont)) { return [string]$inventory.activeFont }
  return ""
}

function Get-CosmeticAccentRgb {
  $inventory = Get-InventoryState
  switch ([string]$inventory.activeTheme) {
    "themeForest" { return @(96, 232, 190) }
    "themeArcane" { return @(92, 184, 255) }
    "themeRoyal" { return @(255, 202, 64) }
    "themeCyber" { return @(51, 235, 255) }
    "themeCelestial" { return @(184, 142, 255) }
  }
  switch ([string]$inventory.activeFont) {
    "fontPixel" { return @(255, 210, 84) }
    "fontTerminal" { return @(94, 255, 166) }
    default { return [int[]]$script:Style.PrimaryRgb }
  }
}

function Get-CosmeticTextRgb {
  param([switch]$Secondary)
  switch (Get-ActiveCosmeticKey) {
    "fontPixel" { if ($Secondary) { return @(116, 226, 255) }; return @(255, 235, 154) }
    "fontTerminal" { if ($Secondary) { return @(184, 255, 211) }; return @(102, 255, 156) }
    "themeForest" { if ($Secondary) { return @(198, 255, 236) }; return @(118, 255, 207) }
    "themeArcane" { if ($Secondary) { return @(205, 235, 255) }; return @(112, 202, 255) }
    "themeRoyal" { if ($Secondary) { return @(255, 238, 178) }; return @(255, 210, 84) }
    "themeCyber" { if ($Secondary) { return @(255, 154, 238) }; return @(91, 245, 255) }
    "themeCelestial" { if ($Secondary) { return @(210, 244, 255) }; return @(213, 181, 255) }
    default { return [int[]]$script:Style.ReadoutTextRgb }
  }
}

function New-CosmeticGlowEffect {
  param([double]$Radius = 9.0, [double]$Opacity = 0.46)
  $key = Get-ActiveCosmeticKey
  if ([string]::IsNullOrWhiteSpace($key)) { return $null }
  $effect = [System.Windows.Media.Effects.DropShadowEffect]::new()
  $effect.BlurRadius = $Radius
  $effect.ShadowDepth = 0
  $effect.Opacity = $Opacity
  $rgb = Get-CosmeticAccentRgb
  $effect.Color = [System.Windows.Media.Color]::FromRgb([byte]$rgb[0], [byte]$rgb[1], [byte]$rgb[2])
  return $effect
}

function Set-KeyCounterBaseBorderVisibility {
  if ($null -eq $script:KeyCounterBackground) { return }
  if (-not [string]::IsNullOrWhiteSpace((Get-ActiveThemeBorderPath))) {
    $script:KeyCounterBackground.Stroke = New-Brush 0 0 0 0
    $script:KeyCounterBackground.StrokeThickness = 0.0
  }
}

function Apply-CosmeticUnlockVisuals {
  $font = Get-CosmeticFontFamily
  $hasCosmetic = -not [string]::IsNullOrWhiteSpace((Get-ActiveCosmeticKey))
  $primaryTextRgb = Get-CosmeticTextRgb
  $secondaryTextRgb = Get-CosmeticTextRgb -Secondary
  $primaryTextBrush = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$primaryTextRgb)
  $secondaryTextBrush = New-StyleBrush ([byte][Math]::Max(150, [Math]::Min(255, [int]$script:Style.ReadoutTextOpacity - 8))) ([int[]]$secondaryTextRgb)
  foreach ($text in @(
    $script:PrimaryBatteryLabel,
    $script:SecondaryBatteryLabel,
    $script:PrimaryBadgeLabel,
    $script:SecondaryBadgeLabel,
    $script:GrowthChipLabel,
    $script:KeyCounterLabel,
    $script:InventoryLabel,
    $script:OuterReadoutText,
    $script:InnerReadoutText,
    $script:GrowthReadoutText,
    $script:InventoryReadoutText,
    $script:InventoryReadoutTitle,
    $script:InventoryReadoutHint,
    $script:InventoryReadoutStats
  )) {
    if ($null -ne $text) { $text.FontFamily = $font }
  }
  foreach ($text in @($script:KeyCounterLabel, $script:InventoryLabel, $script:InventoryReadoutTitle)) {
    if ($null -ne $text) { $text.Foreground = $primaryTextBrush }
  }
  foreach ($text in @($script:InventoryReadoutHint, $script:InventoryReadoutStats)) {
    if ($null -ne $text) { $text.Foreground = $secondaryTextBrush }
  }
  foreach ($label in $script:InventoryItemLabelBlocks.Values) { $label.FontFamily = $font }
  foreach ($count in $script:InventoryItemCountBlocks.Values) { $count.FontFamily = $font }

  $accent = Get-CosmeticAccentRgb
  if ($null -ne $script:InventoryCountBackground) {
    $script:InventoryCountBackground.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$accent)
  }
  if ($null -ne $script:InventoryHoverBorder) {
    $script:InventoryHoverBorder.Stroke = New-StyleBrush 236 ([int[]]$accent)
    $script:InventoryHoverBorder.Fill = New-StyleBrush 24 ([int[]]$accent)
  }
  if ($null -ne $script:KeyCounterBackground) {
    $script:KeyCounterBackground.Fill = New-StyleBrush ([byte][Math]::Min(230, [int]$script:Style.ReadoutOpacity + $(if ($hasCosmetic) { 16 } else { 0 }))) ([int[]]$script:Style.OuterReadoutBgRgb)
    if ($hasCosmetic) {
      $script:KeyCounterBackground.Stroke = New-StyleBrush 230 ([int[]]$accent)
      $script:KeyCounterBackground.StrokeThickness = 1.8
    }
    Set-KeyCounterBaseBorderVisibility
  }
  if ($null -ne $script:KeyCounterThemeBorder) {
    $hasThemeBorder = -not [string]::IsNullOrWhiteSpace((Get-ActiveThemeBorderPath))
    if ($hasThemeBorder) {
      $script:KeyCounterThemeBorder.Source = New-ActiveThemeBorderImageSource
    }
    $script:KeyCounterThemeBorder.Opacity = if ($hasThemeBorder) { 0.94 } else { 0.0 }
    $script:KeyCounterThemeBorder.Visibility = if ($hasThemeBorder -and $script:RingVisualsVisible -and (Test-KeyCounterHudVisible)) {
      [System.Windows.Visibility]::Visible
    } else {
      [System.Windows.Visibility]::Collapsed
    }
  }
  if ($null -ne $script:KeyCounterAccent) {
    $script:KeyCounterAccent.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$accent)
  }
  foreach ($count in $script:InventoryItemCountBlocks.Values) {
    $count.Foreground = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$accent)
  }
  foreach ($target in @($script:KeyCounterLabel, $script:InventoryLabel, $script:InventoryReadoutTitle)) {
    if ($null -ne $target) {
      $target.Effect = if ($hasCosmetic) { New-CosmeticGlowEffect -Radius 8.0 -Opacity 0.42 } else { $null }
    }
  }
}

function Get-InventoryHudWidth {
  return 46.0
}

function Get-InventoryHudText {
  $inventory = Get-InventoryState
  $totalDrops = Get-InventoryUnlockCount -Inventory $inventory
  if ($totalDrops -gt 99) { return "99+" }
  return "{0}" -f $totalDrops
}

function Get-InventoryUiText {
  param([string]$Key)
  $language = Get-EffectiveLanguage
  if ($language -eq "ko") {
    switch ($Key) {
      "Title" { return (Expand-UnicodeText "\uBCF4\uC0C1 \uBCF4\uAD00\uD568") }
      "EmptyHint" { return (Expand-UnicodeText "\uD76C\uADC0 \uD574\uAE08\uC740 \uB9E4\uC6B0 \uB4DC\uBB3C\uAC8C \uB4F1\uC7A5\uD574\uC694") }
      "Drops" { return (Expand-UnicodeText "\uD574\uAE08 {0}") }
      "Keys" { return (Expand-UnicodeText "\uB204\uC801 \uD0A4 {0}") }
      "Last" { return (Expand-UnicodeText "\uB9C8\uC9C0\uB9C9 {0}") }
      "None" { return (Expand-UnicodeText "\uC5C6\uC74C") }
      "Locked" { return (Expand-UnicodeText "\uC7A0\uAE40") }
      "Unlocked" { return (Expand-UnicodeText "\uD574\uAE08") }
      "Active" { return (Expand-UnicodeText "\uC801\uC6A9 \uC911") }
      "Select" { return (Expand-UnicodeText "\uC120\uD0DD") }
      "FontCategory" { return (Expand-UnicodeText "\uD3F0\uD2B8 \uC120\uD0DD") }
      "ThemeCategory" { return (Expand-UnicodeText "\uD14C\uB9C8 \uC120\uD0DD") }
      "PickerHintFont" { return (Expand-UnicodeText "\uD574\uAE08\uB41C \uD3F0\uD2B8\uB97C \uC120\uD0DD\uD558\uC138\uC694") }
      "PickerHintTheme" { return (Expand-UnicodeText "\uD574\uAE08\uB41C \uD14C\uB9C8\uB97C \uC120\uD0DD\uD558\uC138\uC694") }
      "fontPixel" { return (Expand-UnicodeText "\uD53D\uC140 \uD3F0\uD2B8") }
      "fontTerminal" { return (Expand-UnicodeText "\uD130\uBBF8\uB110 \uD3F0\uD2B8") }
      "themeForest" { return (Expand-UnicodeText "\uBBFC\uD2B8 \uD68C\uB85C \uD14C\uB9C8") }
      "themeArcane" { return (Expand-UnicodeText "\uC544\uCF00\uC778 \uD14C\uB9C8") }
      "themeRoyal" { return (Expand-UnicodeText "\uB85C\uC5F4 \uD14C\uB9C8") }
      "themeCyber" { return (Expand-UnicodeText "\uB124\uC628 \uC0AC\uC774\uBC84 \uD14C\uB9C8") }
      "themeCelestial" { return (Expand-UnicodeText "\uC140\uB808\uC2A4\uD2F0\uC5BC \uD14C\uB9C8") }
    }
  }
  if ($language -eq "ja") {
    switch ($Key) {
      "Title" { return (Expand-UnicodeText "\u5831\u916C\u30DC\u30C3\u30AF\u30B9") }
      "EmptyHint" { return (Expand-UnicodeText "\u30EC\u30A2\u89E3\u653E\u306F\u3068\u3066\u3082\u4F4E\u78BA\u7387\u3067\u3059") }
      "Drops" { return (Expand-UnicodeText "\u89E3\u653E {0}") }
      "Keys" { return (Expand-UnicodeText "\u7D2F\u8A08\u30AD\u30FC {0}") }
      "Last" { return (Expand-UnicodeText "\u6700\u5F8C {0}") }
      "None" { return (Expand-UnicodeText "\u306A\u3057") }
      "Locked" { return (Expand-UnicodeText "\u672A\u89E3\u653E") }
      "Unlocked" { return (Expand-UnicodeText "\u89E3\u653E\u6E08\u307F") }
      "Active" { return (Expand-UnicodeText "\u9069\u7528\u4E2D") }
      "Select" { return (Expand-UnicodeText "\u9078\u629E") }
      "FontCategory" { return "Fonts" }
      "ThemeCategory" { return "Themes" }
      "PickerHintFont" { return "Choose an unlocked font" }
      "PickerHintTheme" { return "Choose an unlocked theme" }
      "fontPixel" { return (Expand-UnicodeText "\u30D4\u30AF\u30BB\u30EB\u30D5\u30A9\u30F3\u30C8") }
      "fontTerminal" { return (Expand-UnicodeText "\u30BF\u30FC\u30DF\u30CA\u30EB\u30D5\u30A9\u30F3\u30C8") }
      "themeForest" { return "Mint Circuit Theme" }
      "themeArcane" { return (Expand-UnicodeText "\u30A2\u30FC\u30B1\u30A4\u30F3\u30C6\u30FC\u30DE") }
      "themeRoyal" { return (Expand-UnicodeText "\u30ED\u30A4\u30E4\u30EB\u30C6\u30FC\u30DE") }
      "themeCyber" { return "Neon Cyber Theme" }
      "themeCelestial" { return "Celestial Prism Theme" }
    }
  }
  if ($language -eq "zh") {
    switch ($Key) {
      "Title" { return (Expand-UnicodeText "\u5956\u52B1\u6536\u85CF\u7BB1") }
      "EmptyHint" { return (Expand-UnicodeText "\u7A00\u6709\u89E3\u9501\u4F1A\u4EE5\u5F88\u4F4E\u6982\u7387\u51FA\u73B0") }
      "Drops" { return (Expand-UnicodeText "\u89E3\u9501 {0}") }
      "Keys" { return (Expand-UnicodeText "\u7D2F\u8BA1\u6309\u952E {0}") }
      "Last" { return (Expand-UnicodeText "\u6700\u540E {0}") }
      "None" { return (Expand-UnicodeText "\u65E0") }
      "Locked" { return (Expand-UnicodeText "\u672A\u89E3\u9501") }
      "Unlocked" { return (Expand-UnicodeText "\u5DF2\u89E3\u9501") }
      "Active" { return (Expand-UnicodeText "\u4F7F\u7528\u4E2D") }
      "Select" { return (Expand-UnicodeText "\u9009\u62E9") }
      "FontCategory" { return "Fonts" }
      "ThemeCategory" { return "Themes" }
      "PickerHintFont" { return "Choose an unlocked font" }
      "PickerHintTheme" { return "Choose an unlocked theme" }
      "fontPixel" { return (Expand-UnicodeText "\u50CF\u7D20\u5B57\u4F53") }
      "fontTerminal" { return (Expand-UnicodeText "\u7EC8\u7AEF\u5B57\u4F53") }
      "themeForest" { return "Mint Circuit Theme" }
      "themeArcane" { return (Expand-UnicodeText "\u79D8\u6CD5\u4E3B\u9898") }
      "themeRoyal" { return (Expand-UnicodeText "\u7687\u5BB6\u4E3B\u9898") }
      "themeCyber" { return "Neon Cyber Theme" }
      "themeCelestial" { return "Celestial Prism Theme" }
    }
  }
  switch ($Key) {
    "Title" { return "Reward Chest" }
    "EmptyHint" { return "Rare unlocks drop at a very low chance" }
    "Drops" { return "Unlocks {0}" }
    "Keys" { return "Keys {0}" }
    "Last" { return "Last {0}" }
    "None" { return "None" }
    "Locked" { return "Locked" }
    "Unlocked" { return "Unlocked" }
    "Active" { return "Active" }
    "Select" { return "Select" }
    "FontCategory" { return "Fonts" }
    "ThemeCategory" { return "Themes" }
    "PickerHintFont" { return "Choose an unlocked font" }
    "PickerHintTheme" { return "Choose an unlocked theme" }
    "fontPixel" { return "Pixel Font" }
    "fontTerminal" { return "Terminal Font" }
    "themeForest" { return "Mint Circuit Theme" }
    "themeArcane" { return "Arcane Theme" }
    "themeRoyal" { return "Royal Theme" }
    "themeCyber" { return "Neon Cyber Theme" }
    "themeCelestial" { return "Celestial Prism Theme" }
  }
  return $Key
}

function Test-InventoryUnlockActive {
  param($Inventory, [string]$ItemKey)
  if ($ItemKey -like "font*") { return ([string]$Inventory.activeFont -eq $ItemKey) }
  if ($ItemKey -like "theme*") { return ([string]$Inventory.activeTheme -eq $ItemKey) }
  return $false
}

function Set-ActiveInventoryUnlock {
  param([string]$ItemKey)
  if ([string]::IsNullOrWhiteSpace($ItemKey)) { return }
  if ($ItemKey -notin $CosmeticUnlockKeys) { return }
  $inventory = Get-InventoryState
  if (-not [bool]$inventory.$ItemKey) { return }
  if ($ItemKey -like "font*") {
    if ([string]$inventory.activeFont -eq $ItemKey) { return }
    $inventory.activeFont = $ItemKey
  } elseif ($ItemKey -like "theme*") {
    if ([string]$inventory.activeTheme -eq $ItemKey) { return }
    $inventory.activeTheme = $ItemKey
  } else {
    return
  }
  Save-PetGrowthState -Force
  Apply-CosmeticUnlockVisuals
  Update-InventoryReadoutContent
  Update-KeyCounterGeometry
  Update-PetFrame
}

function Get-InventoryReadoutText {
  $inventory = Get-InventoryState
  $totalDrops = Get-InventoryUnlockCount -Inventory $inventory
  $totalKeys = [Math]::Max(0, [int]$inventory.totalKeys)
  $lastItem = Get-DropItemLabel -Item ([string]$inventory.lastDropItem)
  if ([string]::IsNullOrWhiteSpace($lastItem)) { $lastItem = Get-InventoryUiText -Key "None" }
  return "{0}`n{1}`n{2}  {3}" -f `
    (Get-InventoryUiText -Key "Title"),
    ((Get-InventoryUiText -Key "Drops") -f $totalDrops),
    ((Get-InventoryUiText -Key "Keys") -f $totalKeys),
    ((Get-InventoryUiText -Key "Last") -f $lastItem)
}

function Update-InventoryReadoutContent {
  $inventory = Get-InventoryState
  $unlocks = @{
    fontPixel = [bool]$inventory.fontPixel
    fontTerminal = [bool]$inventory.fontTerminal
  }
  foreach ($key in $CosmeticThemeKeys) {
    $unlocks[$key] = [bool]$inventory.$key
  }
  foreach ($key in $CosmeticUnlockKeys) {
    $unlocked = [bool]$unlocks[$key]
    $active = $unlocked -and (Test-InventoryUnlockActive -Inventory $inventory -ItemKey $key)
    if ($script:InventoryItemLabelBlocks.ContainsKey($key)) {
      $script:InventoryItemLabelBlocks[$key].Text = Get-InventoryUiText -Key $key
    }
    if ($script:InventoryItemCountBlocks.ContainsKey($key)) {
      $script:InventoryItemCountBlocks[$key].Text = if ($active) {
        Get-InventoryUiText -Key "Active"
      } elseif ($unlocked) {
        Get-InventoryUiText -Key "Select"
      } else {
        Get-InventoryUiText -Key "Locked"
      }
    }
    if ($script:InventoryItemBorders.ContainsKey($key)) {
      $border = $script:InventoryItemBorders[$key]
      $border.Opacity = if ($unlocked) { 1.0 } else { 0.42 }
      $border.Cursor = if ($unlocked) { [System.Windows.Input.Cursors]::Hand } else { [System.Windows.Input.Cursors]::Arrow }
      if ($active) {
        $accent = Get-CosmeticAccentRgb
        $border.BorderBrush = New-StyleBrush 246 ([int[]]$accent)
        $border.BorderThickness = [System.Windows.Thickness]::new(2)
        $border.Background = New-StyleBrush 42 ([int[]]$accent)
      } else {
        $border.BorderBrush = New-Brush 92 255 255 255
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.Background = New-Brush 86 10 17 24
      }
    }
  }

  $totalDrops = Get-InventoryUnlockCount -Inventory $inventory
  $totalKeys = [Math]::Max(0, [int]$inventory.totalKeys)
  $lastItem = Get-DropItemLabel -Item ([string]$inventory.lastDropItem)
  if ([string]::IsNullOrWhiteSpace($lastItem)) { $lastItem = Get-InventoryUiText -Key "None" }

  if ($null -ne $script:InventoryReadoutTitle) {
    $script:InventoryReadoutTitle.Text = Get-InventoryUiText -Key "Title"
  }
  if ($null -ne $script:InventoryReadoutHint) {
    $script:InventoryReadoutHint.Text = if ($totalDrops -gt 0) {
      ((Get-InventoryUiText -Key "Last") -f $lastItem)
    } else {
      Get-InventoryUiText -Key "EmptyHint"
    }
  }
  if ($null -ne $script:InventoryReadoutStats) {
    $script:InventoryReadoutStats.Text = "{0}  {1}" -f `
      ((Get-InventoryUiText -Key "Drops") -f $totalDrops),
      ((Get-InventoryUiText -Key "Keys") -f $totalKeys)
  }
  if ($null -ne $script:InventoryReadoutText) {
    $script:InventoryReadoutText.Text = Get-InventoryReadoutText
  }
  Apply-CosmeticUnlockVisuals
}

function Get-RandomDropItem {
  $inventory = Get-InventoryState
  $weightedCandidates = @()
  $themeWeights = [ordered]@{
    themeForest = 55
    themeArcane = 25
    themeRoyal = 13
    themeCyber = 5
    themeCelestial = 2
  }
  foreach ($key in $themeWeights.Keys) {
    if (-not [bool]$inventory.$key) {
      $weightedCandidates += [pscustomobject]@{ Key = $key; Weight = [int]$themeWeights[$key] }
    }
  }
  foreach ($key in @("fontPixel", "fontTerminal")) {
    if (-not [bool]$inventory.$key) {
      $weightedCandidates += [pscustomobject]@{ Key = $key; Weight = 12 }
    }
  }
  if ($weightedCandidates.Count -le 0) { return "" }
  $totalWeight = 0
  foreach ($candidate in $weightedCandidates) { $totalWeight += [int]$candidate.Weight }
  if ($totalWeight -le 0) { return "" }
  $roll = Get-Random -Minimum 1 -Maximum ($totalWeight + 1)
  $cursor = 0
  foreach ($candidate in $weightedCandidates) {
    $cursor += [int]$candidate.Weight
    if ($roll -le $cursor) { return [string]$candidate.Key }
  }
  return [string]$weightedCandidates[-1].Key
}

function Add-InventoryDrop {
  param([int]$Delta)
  if ($Delta -le 0) { return $null }
  $inventory = Get-InventoryState
  $oldTotalKeys = [Math]::Max(0, [int]$inventory.totalKeys)
  $newTotalKeys = $oldTotalKeys + [Math]::Max(0, [int]$Delta)
  $inventory.totalKeys = $newTotalKeys
  $oldBucket = [Math]::Floor($oldTotalKeys / 100.0)
  $newBucket = [Math]::Floor($newTotalKeys / 100.0)
  if ($newBucket -le $oldBucket) {
    Save-PetGrowthState
    return $null
  }

  $inventory.rewardRolls = [Math]::Max(0, [int]$inventory.rewardRolls) + ([int]$newBucket - [int]$oldBucket)
  $roll = Get-Random -Minimum 1 -Maximum 1001
  if ($roll -gt 25) {
    Save-PetGrowthState
    return $null
  }

  $item = Get-RandomDropItem
  if ([string]::IsNullOrWhiteSpace($item)) {
    Save-PetGrowthState
    return $null
  }
  $inventory.$item = $true
  if ($item -like "font*") { $inventory.activeFont = $item }
  if ($item -like "theme*") { $inventory.activeTheme = $item }
  $inventory.totalDrops = [Math]::Max(0, [int]$inventory.totalDrops) + 1
  $inventory.lastDropItem = $item
  $inventory.lastDropAt = (Get-Date).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
  Save-PetGrowthState -Force
  return $item
}

function Get-DropItemLabel {
  param([string]$Item)
  switch ($Item) {
    "fontPixel" { return (Get-InventoryUiText -Key "fontPixel") }
    "fontTerminal" { return (Get-InventoryUiText -Key "fontTerminal") }
    { $_ -in $CosmeticThemeKeys } { return (Get-InventoryUiText -Key $Item) }
    default { return "" }
  }
}

function Get-KeyFlowName {
  param([int]$Multiplier, [int]$ComboCount)
  if ($ComboCount -ge 70) { return "Cooldown" }
  if ($Multiplier -ge 5) { return "Papang" }
  if ($Multiplier -ge 4) { return "Rush" }
  if ($Multiplier -ge 3) { return "Flow" }
  if ($Multiplier -ge 2) { return "Warmup" }
  return ""
}

function Get-KeyComboMultiplier {
  param([int]$ComboCount)
  if ($ComboCount -ge 70) { return 3 }
  if ($ComboCount -ge 45) { return 5 }
  if ($ComboCount -ge 28) { return 4 }
  if ($ComboCount -ge 14) { return 3 }
  if ($ComboCount -ge 6) { return 2 }
  return 1
}

function Update-KeyComboState {
  param([int]$Delta)
  $now = Get-Date
  $idleSeconds = if ($script:LastKeyInputAt -eq [datetime]::MinValue) { 99999.0 } else { ($now - $script:LastKeyInputAt).TotalSeconds }
  $rested = (
    $idleSeconds -ge 45.0 -and
    $idleSeconds -le 900.0 -and
    [int]$script:KeyComboCount -ge 12 -and
    ($now - $script:LastKeyRestBonusAt).TotalSeconds -ge 60.0
  )

  if ($idleSeconds -gt 3.2) {
    $script:KeyComboCount = [Math]::Max(1, [int]$Delta)
  } else {
    $script:KeyComboCount = [Math]::Min(120, [int]$script:KeyComboCount + [Math]::Max(1, [int]$Delta))
  }

  if ($rested) {
    $script:LastKeyRestBonusAt = $now
    $script:KeyFlowState = "Rest +"
    $script:KeyFlowStateUntil = $now.AddSeconds(7)
    $script:KeyComboMultiplier = [Math]::Max(2, [int]$script:KeyComboMultiplier)
  } else {
    $script:KeyComboMultiplier = Get-KeyComboMultiplier -ComboCount ([int]$script:KeyComboCount)
    if ([int]$script:KeyComboCount -ge 70) {
      $script:KeyFlowState = "Cooldown"
      $script:KeyFlowStateUntil = $now.AddSeconds(7)
    }
  }

  $script:LastKeyInputAt = $now
}

function Update-KeyCounterVisualText {
  if ($null -ne $script:KeyCounterLabel) {
    $status = Get-KeyCounterStatusText
    $script:KeyCounterLabel.Inlines.Clear()
    $countRun = [System.Windows.Documents.Run]::new(("{0}" -f ([int]$script:KeyPressCount)))
    $countRun.FontSize = 20.0
    $countRun.FontWeight = [System.Windows.FontWeights]::Black
    $countRun.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]](Get-CosmeticTextRgb))
    $script:KeyCounterLabel.Inlines.Add($countRun) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($status)) {
      $script:KeyCounterLabel.Inlines.Add([System.Windows.Documents.LineBreak]::new()) | Out-Null
      $statusRun = [System.Windows.Documents.Run]::new($status)
      $statusRun.FontSize = 13.2
      $statusRun.FontWeight = [System.Windows.FontWeights]::Bold
      $statusRun.Foreground = New-StyleBrush ([byte][Math]::Max(150, [Math]::Min(255, [int]$script:Style.ReadoutTextOpacity - 8))) ([int[]](Get-CosmeticTextRgb -Secondary))
      $script:KeyCounterLabel.Inlines.Add($statusRun) | Out-Null
    }
  }
  if ($null -ne $script:KeyCounterBackground) {
    $combo = [int]$script:KeyComboMultiplier
    if ([string](Get-KeyCounterStatusText) -eq "Rest +") {
      $script:KeyCounterBackground.Stroke = New-StyleBrush ([byte]$script:Style.SecondaryOpacity) ([int[]]$script:Style.SecondaryRgb)
      $script:KeyCounterBackground.StrokeThickness = 1.8
    } elseif ($combo -ge 4) {
      $script:KeyCounterBackground.Stroke = New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.CautionRgb)
      $script:KeyCounterBackground.StrokeThickness = 1.7
    } elseif ($combo -ge 2) {
      $script:KeyCounterBackground.Stroke = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
      $script:KeyCounterBackground.StrokeThickness = 1.4
    } else {
      $script:KeyCounterBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 42))) ([int[]]$script:Style.TrackRgb)
      $script:KeyCounterBackground.StrokeThickness = 1.0
    }
    if (-not [string]::IsNullOrWhiteSpace((Get-ActiveCosmeticKey))) {
      $script:KeyCounterBackground.Stroke = New-StyleBrush 230 ([int[]](Get-CosmeticAccentRgb))
      $script:KeyCounterBackground.StrokeThickness = [Math]::Max(1.8, [double]$script:KeyCounterBackground.StrokeThickness)
    }
    Set-KeyCounterBaseBorderVisibility
  }
}

function Sync-KeyCounterIdleVisualState {
  if (-not (Test-KeyCounterHudVisible)) { return }
  $now = Get-Date
  if (($now - $script:LastKeyCounterIdleSyncAt).TotalMilliseconds -lt 250) { return }
  $script:LastKeyCounterIdleSyncAt = $now
  $signature = "{0}|{1}|{2}" -f (([string]([int]$script:KeyPressCount)).Length), (Get-KeyCounterStatusText), ([string]$script:Style.DisplayMode)
  if ($signature -ne [string]$script:LastKeyCounterVisualSignature) {
    $script:LastKeyCounterVisualSignature = $signature
    Update-KeyCounterGeometry
    Update-KeyCounterVisualText
  }
}

function Update-KeyCounterHook {
  $shouldInstall = (Test-KeyCounterHudVisible) -and $null -ne $script:LastPetRect
  if ($shouldInstall -and -not $script:KeyCounterInstalled) {
    $now = Get-Date
    if (($now - $script:LastKeyHookAttemptAt).TotalSeconds -lt 10) { return }
    $script:LastKeyHookAttemptAt = $now
    try {
      $script:KeyCounterInstalled = [bool][CodexPetLimitRingNative]::InstallKeyboardCounter()
      if ($script:KeyCounterInstalled) {
        $script:KeyHookFailureLogged = $false
      } elseif (-not $script:KeyHookFailureLogged) {
        Write-AppLog "Keyboard counter hook could not be installed."
        $script:KeyHookFailureLogged = $true
      }
    } catch {
      $script:KeyCounterInstalled = $false
      if (-not $script:KeyHookFailureLogged) {
        Write-AppLog "Keyboard counter hook install failed: $($_.Exception.Message)"
        $script:KeyHookFailureLogged = $true
      }
    }
  } elseif (-not $shouldInstall -and $script:KeyCounterInstalled) {
    try { [CodexPetLimitRingNative]::UninstallKeyboardCounter() } catch {}
    $script:KeyCounterInstalled = $false
  }
}

function Update-MouseClickHook {
  $shouldInstall = (Test-InventoryHudVisible) -and $null -ne $script:LastPetRect
  if ($shouldInstall -and -not $script:MouseClickCounterInstalled) {
    $now = Get-Date
    if (($now - $script:LastMouseHookAttemptAt).TotalSeconds -lt 10) { return }
    $script:LastMouseHookAttemptAt = $now
    try {
      $script:MouseClickCounterInstalled = [bool][CodexPetLimitRingNative]::InstallMouseClickCounter()
      if ($script:MouseClickCounterInstalled) {
        $script:MouseHookFailureLogged = $false
      } elseif (-not $script:MouseHookFailureLogged) {
        Write-AppLog "Mouse click hook could not be installed."
        $script:MouseHookFailureLogged = $true
      }
    } catch {
      $script:MouseClickCounterInstalled = $false
      if (-not $script:MouseHookFailureLogged) {
        Write-AppLog "Mouse click hook install failed: $($_.Exception.Message)"
        $script:MouseHookFailureLogged = $true
      }
    }
  } elseif (-not $shouldInstall -and $script:MouseClickCounterInstalled) {
    try { [CodexPetLimitRingNative]::UninstallMouseClickCounter() } catch {}
    $script:MouseClickCounterInstalled = $false
  }
}

function Get-ConsumedLeftMouseClickCursor {
  try {
    $raw = [string][CodexPetLimitRingNative]::ConsumeLeftMouseClick()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $parts = $raw.Split(",")
    if ($parts.Count -lt 2) { return $null }
    return [pscustomobject]@{
      X = [double]([int]$parts[0])
      Y = [double]([int]$parts[1])
    }
  } catch {
    return $null
  }
}

function Invoke-InventoryToggle {
  param([double]$LocalX, [double]$LocalY)
  $now = Get-Date
  if (($now - $script:LastInventoryToggleAt).TotalMilliseconds -lt 140) { return }
  $script:LastInventoryToggleAt = $now
  $script:InventoryMouseWasDown = $true
  $script:LastHoverSignature = "InventoryClick|{0:N0}|{1:N0}" -f $LocalX, $LocalY
  Toggle-InventoryReadout
}

function Get-KeyMilestoneTier {
  param([int]$OldCount, [int]$NewCount)
  if ($NewCount -le $OldCount) { return 0 }

  $tier = 0
  $unit = 100
  while ($unit -le 1000000) {
    if ([Math]::Floor($NewCount / $unit) -gt [Math]::Floor($OldCount / $unit)) {
      $tier += 1
    }
    if ($unit -gt 100000) { break }
    $unit *= 10
  }
  return $tier
}

function New-KeyBurstParticle {
  param([double]$X, [double]$Y, [int]$Index, [int]$Tier = 0, [string]$MilestoneText = "")
  if ($null -eq $script:Canvas -or -not $script:Style.ShowKeyEffects) { return }
  if ($script:Canvas.Children.Count -gt 64) { return }

  $scale = 1.0 + ([Math]::Max(0, $Tier) * 0.55)
  $particle = if ($Index % 4 -eq 0 -or -not [string]::IsNullOrWhiteSpace($MilestoneText)) {
    $text = [System.Windows.Controls.TextBlock]::new()
    $text.Text = if ([string]::IsNullOrWhiteSpace($MilestoneText)) { "+1" } else { $MilestoneText }
    $text.FontFamily = Get-CosmeticFontFamily
    $text.FontWeight = [System.Windows.FontWeights]::Black
    $text.FontSize = 11.0 * $scale
    $text.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]](Get-CosmeticTextRgb))
    $text
  } else {
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 7.0 * $scale
    $dot.Height = 7.0 * $scale
    $dot.Fill = if ($Index % 3 -eq 0) {
      New-StyleBrush ([byte]$script:Style.SecondaryOpacity) ([int[]]$script:Style.SecondaryRgb)
    } elseif ($Tier -gt 1) {
      New-StyleBrush ([byte]$script:Style.WarningOpacity) ([int[]]$script:Style.CautionRgb)
    } else {
      New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
    }
    $dot
  }

  $spread = 110.0 + ([Math]::Max(0, $Tier) * 34.0)
  $angle = ((-$spread / 2.0) + (($Index * 37) % [Math]::Max(1, [int]$spread))) * [Math]::PI / 180.0
  $distance = 15.0 + (($Index * 5) % 15) + ([Math]::Max(0, $Tier) * 18.0)
  $fromLeft = $X
  $fromTop = $Y
  $toLeft = $X + [Math]::Cos($angle) * $distance
  $toTop = $Y + [Math]::Sin($angle) * $distance - (10.0 + ([Math]::Max(0, $Tier) * 12.0))
  [System.Windows.Controls.Canvas]::SetLeft($particle, $fromLeft)
  [System.Windows.Controls.Canvas]::SetTop($particle, $fromTop)
  $particle.Opacity = 0.95
  $script:Canvas.Children.Add($particle) | Out-Null

  $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(430 + ([Math]::Max(0, $Tier) * 130)))
  $ease = [System.Windows.Media.Animation.CubicEase]::new()
  $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
  $leftAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new($fromLeft, $toLeft, $duration)
  $topAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new($fromTop, $toTop, $duration)
  $opacityAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new(0.95, 0.0, $duration)
  $leftAnimation.EasingFunction = $ease
  $topAnimation.EasingFunction = $ease
  $opacityAnimation.EasingFunction = $ease
  $opacityAnimation.Add_Completed({
    try { [void]$script:Canvas.Children.Remove($particle) } catch {}
  }.GetNewClosure())
  $particle.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, $leftAnimation)
  $particle.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $topAnimation)
  $particle.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $opacityAnimation)
}

function Start-KeyBurstEffect {
  param([int]$Count, [int]$Tier = 0, [string]$MilestoneText = "")
  if (
    -not $script:Style.ShowKeyEffects -or
    -not $script:RingVisualsVisible -or
    $null -eq $script:KeyCounterBounds
  ) {
    return
  }

  $now = Get-Date
  if (($now - $script:LastKeyBurstAt).TotalMilliseconds -lt 18) { return }
  $script:LastKeyBurstAt = $now
  $tierValue = [Math]::Max(0, [int]$Tier)
  $particleLimit = if ($tierValue -le 0) { 4 } elseif ($tierValue -eq 1) { 10 } elseif ($tierValue -eq 2) { 16 } else { 22 }
  $particles = [Math]::Min($particleLimit, [Math]::Max(1, [int]$Count) + ($tierValue * 4))
  $x = [double]$script:KeyCounterBounds.X + [double]$script:KeyCounterBounds.Width / 2.0
  $y = [double]$script:KeyCounterBounds.Y + 4.0
  if ($Tier -gt 0) {
    New-KeyBurstParticle -X $x -Y $y -Index $script:KeyPressCount -Tier $Tier -MilestoneText $MilestoneText
  }
  for ($i = 0; $i -lt $particles; $i++) {
    New-KeyBurstParticle -X $x -Y $y -Index ($script:KeyPressCount + $i) -Tier $Tier
  }
}

function Start-KeyCounterPulse {
  param([int]$Tier = 0)
  if ($null -eq $script:KeyCounterLabel -or -not $script:RingVisualsVisible) { return }
  $tierValue = [Math]::Max(0, [int]$Tier)
  $peakScale = [Math]::Min(1.34, 1.13 + ($tierValue * 0.05))
  $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(92 + ($tierValue * 18)))
  $backDuration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(145 + ($tierValue * 20)))
  $growX = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, $peakScale, $duration)
  $growY = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, $peakScale, $duration)
  $shrinkX = [System.Windows.Media.Animation.DoubleAnimation]::new($peakScale, 1.0, $backDuration)
  $shrinkY = [System.Windows.Media.Animation.DoubleAnimation]::new($peakScale, 1.0, $backDuration)
  $easeOut = [System.Windows.Media.Animation.CubicEase]::new()
  $easeOut.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
  foreach ($animation in @($growX, $growY, $shrinkX, $shrinkY)) {
    $animation.EasingFunction = $easeOut
  }
  $growX.Add_Completed({
    try {
      $scale = $script:KeyCounterLabel.RenderTransform
      if ($null -ne $scale) {
        $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $shrinkX)
        $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $shrinkY)
      }
    } catch {}
  }.GetNewClosure())
  try {
    $scale = $script:KeyCounterLabel.RenderTransform
    if ($null -ne $scale) {
      $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $growX)
      $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $growY)
    }
  } catch {}

  if ($null -ne $script:KeyCounterAccent -and $null -ne $script:KeyCounterBounds) {
    try {
      $barHeight = if ($tierValue -gt 1) { 4.0 } else { 3.0 }
      $x = [double]$script:KeyCounterBounds.X + 7.0
      $y = [double]$script:KeyCounterBounds.Y + [double]$script:KeyCounterBounds.Height - ($barHeight + 4.0)
      $width = [Math]::Max(8.0, [double]$script:KeyCounterBounds.Width - 14.0)
      Set-RectangleBounds $script:KeyCounterAccent $x $y 0.0 $barHeight
      $script:KeyCounterAccent.Opacity = 0.95
      $script:KeyCounterAccent.Visibility = [System.Windows.Visibility]::Visible

      $flashDuration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(120 + ($tierValue * 20)))
      $fadeDuration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(165 + ($tierValue * 25)))
      $widthAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, $width, $flashDuration)
      $fadeAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new(0.95, 0.0, $fadeDuration)
      $ease = [System.Windows.Media.Animation.CubicEase]::new()
      $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
      $widthAnimation.EasingFunction = $ease
      $fadeAnimation.EasingFunction = $ease
      $fadeAnimation.Add_Completed({
        try { $script:KeyCounterAccent.Visibility = [System.Windows.Visibility]::Collapsed } catch {}
      }.GetNewClosure())
      $script:KeyCounterAccent.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $widthAnimation)
      $script:KeyCounterAccent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeAnimation)
    } catch {}
  }
}

function Update-KeyCounterGeometry {
  if ($null -eq $script:Window -or $null -eq $script:LastPetRect) {
    $script:KeyCounterBounds = $null
    return
  }
  if ($null -eq $script:KeyCounterBackground -or $null -eq $script:KeyCounterLabel) { return }

  $mode = [string]$script:Style.DisplayMode
  $chipWidth = Get-KeyCounterChipWidth -Mode $mode
  $hasStatus = -not [string]::IsNullOrWhiteSpace((Get-KeyCounterStatusText))
  $chipHeight = Get-KeyCounterChipHeight -Mode $mode
  $center = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX } else { [double]$script:Window.Width / 2.0 }
  $ringSize = if ($null -ne $script:HudRingSize) { [double]$script:HudRingSize } else { [Math]::Min([double]$script:Window.Width, [double]$script:Window.Height) }
  $pet = $script:LastPetRect
  $petTop = [double]$pet.Y - [double]$script:Window.Top
  $petBottom = $petTop + [double]$pet.Height
  $growthVisible = Test-GrowthHudVisible
  $growthWidth = if ($growthVisible) { 86.0 } else { 0.0 }
  $gap = if ($growthVisible) { 6.0 } else { 0.0 }
  $inventoryVisible = Test-InventoryHudVisible
  $inventoryWidth = if ($inventoryVisible) { Get-InventoryHudWidth } else { 0.0 }
  $inventoryGap = if ($inventoryVisible) { 6.0 } else { 0.0 }
  if ($mode -eq "ring") {
    $targetX = $center - (($growthWidth + $gap + $chipWidth + $inventoryGap + $inventoryWidth) / 2.0) + $growthWidth + $gap
    $targetY = $ringSize + 6.0
  } elseif ($mode -eq "badge") {
    $badgeWidth = Get-BadgeHudWidth
    $badgeX = $center - $badgeWidth / 2.0
    $slotGap = 4.0
    $slotWidth = ($badgeWidth - 12.0 - ($slotGap * 2.0)) / 3.0
    $targetX = $badgeX + 6.0 + (($slotWidth + $slotGap) * 2.0)
    $targetY = $petBottom + 12.0
    $chipWidth = $slotWidth
  } else {
    $targetX = $center - (($growthWidth + $gap + $chipWidth + $inventoryGap + $inventoryWidth) / 2.0) + $growthWidth + $gap
    $targetY = $petBottom + $(if ($mode -eq "battery") { 12.0 } else { 8.0 })
  }
  $x = [Math]::Max(4.0, [Math]::Min($targetX, [double]$script:Window.Width - $chipWidth - 4.0))
  $y = [Math]::Max(4.0, [Math]::Min($targetY, [double]$script:Window.Height - $chipHeight - 4.0))

  Set-RectangleBounds $script:KeyCounterBackground $x $y $chipWidth $chipHeight
  if ($null -ne $script:KeyCounterThemeBorder) {
    $borderPadX = if ($mode -eq "badge") { 7.0 } else { 8.0 }
    $borderPadY = if ($hasStatus) { 8.0 } else { 7.0 }
    $script:KeyCounterThemeBorder.Width = $chipWidth + ($borderPadX * 2.0)
    $script:KeyCounterThemeBorder.Height = $chipHeight + ($borderPadY * 2.0)
    [System.Windows.Controls.Canvas]::SetLeft($script:KeyCounterThemeBorder, $x - $borderPadX)
    [System.Windows.Controls.Canvas]::SetTop($script:KeyCounterThemeBorder, $y - $borderPadY)
  }
  if ($null -ne $script:KeyCounterAccent) {
    Set-RectangleBounds $script:KeyCounterAccent $x $y 0.0 0.0
  }
  $script:KeyCounterLabel.Width = $chipWidth
  $script:KeyCounterLabel.Height = $chipHeight
  [System.Windows.Controls.Canvas]::SetLeft($script:KeyCounterLabel, $x)
  $script:KeyCounterLabel.LineHeight = if ($hasStatus) { 18.0 } else { [Math]::Max(20.0, $chipHeight - 2.0) }
  $labelTopOffset = if ($hasStatus) { [Math]::Max(4.0, ($chipHeight - ([double]$script:KeyCounterLabel.LineHeight * 2.0)) / 2.0) } else { 0.0 }
  [System.Windows.Controls.Canvas]::SetTop($script:KeyCounterLabel, $y + $labelTopOffset)
  $script:KeyCounterBounds = [pscustomobject]@{ X = $x; Y = $y; Width = $chipWidth; Height = $chipHeight }
  $script:KeyCounterBackground.RadiusX = if ($mode -eq "badge") { 9.0 } else { 8.0 }
  $script:KeyCounterBackground.RadiusY = $script:KeyCounterBackground.RadiusX
  $script:KeyCounterBackground.StrokeThickness = 1.0
  Update-KeyCounterVisualText
  Update-ModeShapeVisibility
}

function Update-InventoryGeometry {
  if (
    -not (Test-InventoryHudVisible) -or
    $null -eq $script:Window -or
    $null -eq $script:InventoryIcon -or
    $null -eq $script:InventoryCountBackground -or
    $null -eq $script:InventoryLabel -or
    $null -eq $script:KeyCounterBounds
  ) {
    $script:InventoryBounds = $null
    $script:InventoryHitBounds = $null
    Set-InventoryHoverHighlight -Visible $false
    return
  }

  $chipWidth = Get-InventoryHudWidth
  $chipHeight = 42.0
  $keyBounds = $script:KeyCounterBounds
  $targetX = [double]$keyBounds.X + [double]$keyBounds.Width + 6.0
  $targetY = [double]$keyBounds.Y + [Math]::Max(0.0, ([double]$keyBounds.Height - $chipHeight) / 2.0)
  $x = [Math]::Max(4.0, [Math]::Min($targetX, [double]$script:Window.Width - $chipWidth - 4.0))
  $y = [Math]::Max(4.0, [Math]::Min($targetY, [double]$script:Window.Height - $chipHeight - 4.0))
  if ($null -ne $script:InventoryBackground) {
    $script:InventoryBackground.Visibility = [System.Windows.Visibility]::Collapsed
    Set-RectangleBounds $script:InventoryBackground 0.0 0.0 0.0 0.0
  }
  $iconX = $x + 3.0
  $iconY = $y
  $iconSize = 40.0
  $badgeX = $x + 25.0
  $badgeY = $y + 25.0
  $badgeWidth = 17.0
  $badgeHeight = 13.0
  $script:InventoryIcon.Width = $iconSize
  $script:InventoryIcon.Height = $iconSize
  [System.Windows.Controls.Canvas]::SetLeft($script:InventoryIcon, $iconX)
  [System.Windows.Controls.Canvas]::SetTop($script:InventoryIcon, $iconY)
  Set-RectangleBounds $script:InventoryCountBackground $badgeX $badgeY $badgeWidth $badgeHeight
  $script:InventoryLabel.Text = Get-InventoryHudText
  $script:InventoryLabel.Width = $badgeWidth
  $script:InventoryLabel.Height = $badgeHeight
  [System.Windows.Controls.Canvas]::SetLeft($script:InventoryLabel, $badgeX)
  [System.Windows.Controls.Canvas]::SetTop($script:InventoryLabel, $badgeY - 2.0)
  $script:InventoryBounds = [pscustomobject]@{ X = $x; Y = $y; Width = $chipWidth; Height = $chipHeight }
  $script:InventoryHitBounds = [pscustomobject]@{ X = ($iconX - 2.0); Y = ($iconY - 2.0); Width = 46.0; Height = 44.0 }
  Set-InventoryHoverHighlight -Visible (Test-InventoryReadoutOpen)
  Update-ModeShapeVisibility
}

function Update-KeyCounter {
  Update-KeyCounterHook
  if (-not $script:KeyCounterInstalled) { return }
  $delta = 0
  try { $delta = [int][CodexPetLimitRingNative]::ConsumeKeyPresses() } catch { return }
  if (-not (Test-KeyCounterHudVisible)) { return }
  if ($delta -le 0) {
    Sync-KeyCounterIdleVisualState
    return
  }
  $oldCount = [int]$script:KeyPressCount
  $oldDigits = ([string]$oldCount).Length
  $oldVisualSignature = [string]$script:LastKeyCounterVisualSignature
  Update-KeyComboState -Delta $delta
  $script:KeyPressCount += $delta
  $newDigits = ([string]([int]$script:KeyPressCount)).Length
  $tier = Get-KeyMilestoneTier -OldCount $oldCount -NewCount ([int]$script:KeyPressCount)
  $comboTier = [Math]::Max(0, [int]$script:KeyComboMultiplier - 1)
  $effectTier = [Math]::Max([int]$tier, [Math]::Min(2, $comboTier))
  $dropItem = Add-InventoryDrop -Delta $delta
  if (-not [string]::IsNullOrWhiteSpace([string]$dropItem)) {
    Apply-CosmeticUnlockVisuals
    Update-KeyCounterGeometry
  }
  $dropText = Get-DropItemLabel -Item ([string]$dropItem)
  $milestoneText = if (-not [string]::IsNullOrWhiteSpace($dropText)) {
    "+ {0}" -f $dropText
  } elseif ($tier -gt 0) {
    "{0}" -f ([int]$script:KeyPressCount)
  } else { "" }
  $newVisualSignature = "{0}|{1}|{2}" -f $newDigits, (Get-KeyCounterStatusText), ([string]$script:Style.DisplayMode)
  if ($newDigits -ne $oldDigits -or $newDigits -ne [int]$script:LastKeyCounterDigits -or $newVisualSignature -ne $oldVisualSignature) {
    $script:LastKeyCounterDigits = $newDigits
    $script:LastKeyCounterVisualSignature = $newVisualSignature
    Update-KeyCounterGeometry
  }
  Update-KeyCounterVisualText
  Update-InventoryGeometry
  Start-KeyCounterPulse -Tier $effectTier
  if ($script:RingVisualsVisible) {
    Start-KeyBurstEffect -Count $delta -Tier $effectTier -MilestoneText $milestoneText
  }
}

function Update-PetGrowth {
  param([bool]$PetVisible)
  if (-not $script:Style.GamificationEnabled) {
    return
  }
  $oldCondition = [string]$script:PetGrowthState.condition
  $oldLevel = [int]$script:PetGrowthState.level
  $result = Update-PetGrowthState `
    -State $script:PetGrowthState `
    -PrimaryRemaining $script:UsageState.PrimaryRemaining `
    -SecondaryRemaining $script:UsageState.SecondaryRemaining `
    -PrimaryResetAt $script:UsageState.PrimaryResetAt `
    -SecondaryResetAt $script:UsageState.SecondaryResetAt `
    -Now (Get-Date) `
    -HasUsageSnapshot ([bool]$script:HasUsageSnapshot) `
    -PetVisible $PetVisible `
    -GrowthMode ([string]$script:Style.GrowthMode) `
    -Enabled ([bool]$script:Style.GamificationEnabled)
  $script:PetGrowthState = $result.State
  Update-PetGrowthVisualText
  $important = ([int]$result.AwardedXp -gt 0) -or ($oldCondition -ne [string]$script:PetGrowthState.condition) -or ($oldLevel -ne [int]$script:PetGrowthState.level)
  if ($result.Changed) {
    Save-PetGrowthState -Force:$important
  }
}

function Hide-PetHud {
  param([bool]$UpdateGrowth = $true)
  if ($UpdateGrowth) {
    Update-PetGrowth -PetVisible $false
  }

  $script:LastPetRect = $null
  $script:LastPetFrameSignature = ""
  $script:RingOuterRadius = $null
  $script:RingInnerRadius = $null
  $script:BatteryPrimaryBounds = $null
  $script:BatterySecondaryBounds = $null
  $script:BadgePrimaryBounds = $null
  $script:BadgeSecondaryBounds = $null
  $script:GrowthChipBounds = $null
  $script:KeyCounterBounds = $null
  $script:InventoryBounds = $null
  $script:InventoryHitBounds = $null
  Set-InventoryHoverHighlight -Visible $false
  $script:HudCenterX = $null
  $script:HudRingSize = $null
  $script:LastHoverSignature = ""
  $script:RingVisualsVisible = $false
  $script:RingAnimationToken += 1
  Update-KeyCounterHook
  Update-MouseClickHook

  Hide-InventoryReadout -ResetPinned
  Hide-RingReadouts
  Set-RingShapesVisibility -Visibility ([System.Windows.Visibility]::Collapsed)
  if ($null -ne $script:Window) {
    $script:Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:Window.Opacity = 0.0
    if ($script:Window.IsVisible) {
      $script:Window.Hide()
    }
  }
}

function Update-GrowthChipGeometry {
  if ($null -eq $script:Window -or $null -eq $script:LastPetRect) {
    $script:GrowthChipBounds = $null
    return
  }
  if ($null -eq $script:GrowthChipBackground -or $null -eq $script:GrowthChipLabel) { return }

  $chipWidth = Get-GrowthChipWidth
  $chipHeight = 26.0
  $pet = $script:LastPetRect
  $petLeft = [double]$pet.X - [double]$script:Window.Left
  $petTop = [double]$pet.Y - [double]$script:Window.Top
  $petBottom = $petTop + [double]$pet.Height
  $mode = [string]$script:Style.DisplayMode
  $center = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX } else { [double]$script:Window.Width / 2.0 }
  $keyVisible = Test-KeyCounterHudVisible
  $keyWidth = if ($keyVisible -and $mode -ne "badge") { Get-KeyCounterChipWidth -Mode $mode } else { 0.0 }
  $rowGap = if ($keyVisible -and $mode -ne "badge") { 6.0 } else { 0.0 }
  $targetX = if ($keyVisible) {
    $center - (($chipWidth + $rowGap + $keyWidth) / 2.0)
  } else {
    $center - ($chipWidth / 2.0)
  }
  $targetY = if ($mode -eq "ring") {
    $ringBottom = if ($null -ne $script:RingOuterRadius) {
      ([double]$script:RingOuterRadius + 16.0) * 2.0
    } else {
      [Math]::Max([double]$pet.Width, [double]$pet.Height) + ([double]$script:Style.RingGap + 16.0) * 2.0
    }
    $ringBottom + 6.0
  } elseif ($mode -eq "badge") {
    $petBottom + 41.0
  } else {
    $petBottom + 8.0
  }
  $x = [Math]::Max(4.0, [Math]::Min($targetX, [double]$script:Window.Width - $chipWidth - 4.0))
  $y = [Math]::Max(4.0, [Math]::Min($targetY, [double]$script:Window.Height - $chipHeight - 4.0))

  Set-RectangleBounds $script:GrowthChipBackground $x $y $chipWidth $chipHeight
  Set-RectangleBounds $script:GrowthChipAccent ($x + 7.0) ($y + 6.0) 5.0 ($chipHeight - 12.0)
  $script:GrowthChipLabel.Width = $chipWidth - 24.0
  $script:GrowthChipLabel.Height = $chipHeight
  [System.Windows.Controls.Canvas]::SetLeft($script:GrowthChipLabel, $x + 18.0)
  [System.Windows.Controls.Canvas]::SetTop($script:GrowthChipLabel, $y + 5.0)
  $script:GrowthChipBounds = [pscustomobject]@{ X = $x; Y = $y; Width = $chipWidth; Height = $chipHeight }
  Update-PetGrowthVisualText
  Update-ModeShapeVisibility
}

function Test-CursorInGrowthChipRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    $null -eq $script:GrowthChipBounds -or
    -not $script:Window.IsVisible -or
    -not (Test-GrowthHudVisible)
  ) {
    return $false
  }

  $localX = [double]$Cursor.X - [double]$script:Window.Left
  $localY = [double]$Cursor.Y - [double]$script:Window.Top
  $padding = [Math]::Max(7.0, [Math]::Min(20.0, [double]$script:Style.HoverRange))
  $bounds = $script:GrowthChipBounds
  return (
    $localX -ge ([double]$bounds.X - $padding) -and
    $localX -le ([double]$bounds.X + [double]$bounds.Width + $padding) -and
    $localY -ge ([double]$bounds.Y - $padding) -and
    $localY -le ([double]$bounds.Y + [double]$bounds.Height + $padding)
  )
}

function Test-CursorInKeyCounterRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    $null -eq $script:KeyCounterBounds -or
    -not $script:Window.IsVisible -or
    -not (Test-KeyCounterHudVisible)
  ) {
    return $false
  }

  $localX = [double]$Cursor.X - [double]$script:Window.Left
  $localY = [double]$Cursor.Y - [double]$script:Window.Top
  $padding = [Math]::Max(7.0, [Math]::Min(20.0, [double]$script:Style.HoverRange))
  $bounds = $script:KeyCounterBounds
  return (
    $localX -ge ([double]$bounds.X - $padding) -and
    $localX -le ([double]$bounds.X + [double]$bounds.Width + $padding) -and
    $localY -ge ([double]$bounds.Y - $padding) -and
    $localY -le ([double]$bounds.Y + [double]$bounds.Height + $padding)
  )
}

function Test-CursorInInventoryRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    $null -eq $script:InventoryHitBounds -or
    -not $script:Window.IsVisible -or
    -not (Test-InventoryHudVisible)
  ) {
    return $false
  }

  $localX = [double]$Cursor.X - [double]$script:Window.Left
  $localY = [double]$Cursor.Y - [double]$script:Window.Top
  $padding = 3.0
  $bounds = $script:InventoryHitBounds
  return (
    $localX -ge ([double]$bounds.X - $padding) -and
    $localX -le ([double]$bounds.X + [double]$bounds.Width + $padding) -and
    $localY -ge ([double]$bounds.Y - $padding) -and
    $localY -le ([double]$bounds.Y + [double]$bounds.Height + $padding)
  )
}

function Show-GrowthReadout {
  if (
    -not $script:Style.ShowGrowthHoverReadout -or
    -not (Test-GrowthHudVisible) -or
    $null -eq $script:GrowthChipBounds -or
    $null -eq $script:GrowthReadoutWindow
  ) {
    return
  }
  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  if ($null -ne $script:InnerReadoutWindow -and $script:InnerReadoutWindow.IsVisible) {
    $script:InnerReadoutWindow.Hide()
  }
  if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
    Hide-InventoryReadout -ResetPinned
  }
  $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InventoryReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:GrowthReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
  [void](Update-ReadoutText -Force)
  $screenX = [double]$script:Window.Left + [double]$script:GrowthChipBounds.X + [double]$script:GrowthChipBounds.Width / 2.0
  $screenY = [double]$script:Window.Top + [double]$script:GrowthChipBounds.Y + [double]$script:GrowthChipBounds.Height / 2.0
  Set-ReadoutWindowNearPoint -Window $script:GrowthReadoutWindow -Border $script:GrowthReadoutBorder -ScreenX $screenX -ScreenY $screenY
  if (-not $script:GrowthReadoutWindow.IsVisible) { $script:GrowthReadoutWindow.Show() }
}

function Show-InventoryReadout {
  if (
    -not (Test-InventoryHudVisible) -or
    $null -eq $script:InventoryHitBounds -or
    $null -eq $script:InventoryReadoutWindow
  ) {
    return
  }
  if ($null -ne $script:OuterReadoutWindow -and $script:OuterReadoutWindow.IsVisible) {
    $script:OuterReadoutWindow.Hide()
  }
  if ($null -ne $script:InnerReadoutWindow -and $script:InnerReadoutWindow.IsVisible) {
    $script:InnerReadoutWindow.Hide()
  }
  if ($null -ne $script:GrowthReadoutWindow -and $script:GrowthReadoutWindow.IsVisible) {
    $script:GrowthReadoutWindow.Hide()
  }
  $script:OuterReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InnerReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:GrowthReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InventoryReadoutBorder.Visibility = [System.Windows.Visibility]::Visible
  $script:InventoryReadoutPinned = $true
  [void](Update-ReadoutText -Force)
  $screenX = [double]$script:Window.Left + [double]$script:InventoryHitBounds.X + [double]$script:InventoryHitBounds.Width / 2.0
  $screenY = [double]$script:Window.Top + [double]$script:InventoryHitBounds.Y + [double]$script:InventoryHitBounds.Height / 2.0
  Set-ReadoutWindowNearPoint -Window $script:InventoryReadoutWindow -Border $script:InventoryReadoutBorder -ScreenX $screenX -ScreenY $screenY
  if (-not $script:InventoryReadoutWindow.IsVisible) { $script:InventoryReadoutWindow.Show() }
}

function Show-InventoryPicker {
  param([string]$Kind)
  if ($Kind -notin @("font", "theme")) { return }
  if (-not (Test-InventoryReadoutOpen)) { Show-InventoryReadout }
  if ($null -eq $script:InventoryPickerWindow -or $null -eq $script:InventoryPickerBorder) { return }

  $script:InventoryPickerKind = $Kind
  $keys = if ($Kind -eq "font") { @("fontPixel", "fontTerminal") } else { $CosmeticThemeKeys }
  $index = 0
  foreach ($key in $CosmeticUnlockKeys) {
    if (-not $script:InventoryItemBorders.ContainsKey($key)) { continue }
    $cell = $script:InventoryItemBorders[$key]
    if ($key -in $keys) {
      [System.Windows.Controls.Grid]::SetColumn($cell, $index % 2)
      [System.Windows.Controls.Grid]::SetRow($cell, [Math]::Floor($index / 2.0))
      $cell.Visibility = [System.Windows.Visibility]::Visible
      $index++
    } else {
      $cell.Visibility = [System.Windows.Visibility]::Collapsed
    }
  }

  if ($null -ne $script:InventoryPickerTitle) {
    $script:InventoryPickerTitle.Text = if ($Kind -eq "font") { Get-InventoryUiText -Key "FontCategory" } else { Get-InventoryUiText -Key "ThemeCategory" }
  }
  if ($null -ne $script:InventoryPickerHint) {
    $script:InventoryPickerHint.Text = if ($Kind -eq "font") { Get-InventoryUiText -Key "PickerHintFont" } else { Get-InventoryUiText -Key "PickerHintTheme" }
  }

  Update-InventoryReadoutContent
  $script:InventoryPickerBorder.Visibility = [System.Windows.Visibility]::Visible
  $screenX = if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
    [double]$script:InventoryReadoutWindow.Left + 360.0
  } else {
    [double]$script:Window.Left + [double]$script:InventoryHitBounds.X + [double]$script:InventoryHitBounds.Width + 140.0
  }
  $screenY = if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
    [double]$script:InventoryReadoutWindow.Top + 50.0
  } else {
    [double]$script:Window.Top + [double]$script:InventoryHitBounds.Y
  }
  Set-ReadoutWindowNearPoint -Window $script:InventoryPickerWindow -Border $script:InventoryPickerBorder -ScreenX $screenX -ScreenY $screenY
  if (-not $script:InventoryPickerWindow.IsVisible) { $script:InventoryPickerWindow.Show() }
}

function Toggle-InventoryReadout {
  if (Test-InventoryReadoutOpen) {
    Hide-InventoryReadout -ResetPinned
    return
  }
  Show-InventoryReadout
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
    Update-ModeShapeVisibility
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
  if ($script:Style.DisplayMode -in @("battery", "badge")) {
    $range = [Math]::Max(0.0, [double]$script:Style.HoverRange)
    return (
      [double]$Cursor.X -ge ([double]$script:Window.Left - $range) -and
      [double]$Cursor.X -le ([double]$script:Window.Left + [double]$script:Window.Width + $range) -and
      [double]$Cursor.Y -ge ([double]$script:Window.Top - $range) -and
      [double]$Cursor.Y -le ([double]$script:Window.Top + [double]$script:Window.Height + $range)
    )
  }
  $centerLocalX = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX } else { $size / 2.0 }
  $ringSize = if ($null -ne $script:HudRingSize) { [double]$script:HudRingSize } else { $size }
  $centerX = [double]$script:Window.Left + $centerLocalX
  $centerY = [double]$script:Window.Top + $ringSize / 2.0
  $outerRadius = if ($null -ne $script:RingOuterRadius) {
    [double]$script:RingOuterRadius
  } else {
    $ringSize / 2.0 - 16.0
  }
  $range = [Math]::Max(0.0, [double]$script:Style.HoverRange)
  $distance = [Math]::Sqrt([Math]::Pow([double]$Cursor.X - $centerX, 2) + [Math]::Pow([double]$Cursor.Y - $centerY, 2))
  return ($distance -le ($outerRadius + $range))
}

function Test-CursorInBadgeRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    -not $script:Window.IsVisible
  ) {
    return $false
  }

  $localX = [double]$Cursor.X - [double]$script:Window.Left
  $localY = [double]$Cursor.Y - [double]$script:Window.Top
  $padding = [Math]::Max(7.0, [Math]::Min(20.0, [double]$script:Style.HoverRange))
  foreach ($bounds in @($script:BadgePrimaryBounds, $script:BadgeSecondaryBounds)) {
    if ($null -eq $bounds) { continue }
    if (
      $localX -ge ([double]$bounds.X - $padding) -and
      $localX -le ([double]$bounds.X + [double]$bounds.Width + $padding) -and
      $localY -ge ([double]$bounds.Y - $padding) -and
      $localY -le ([double]$bounds.Y + [double]$bounds.Height + $padding)
    ) {
      return $true
    }
  }
  return $false
}

function Test-CursorInBatteryRange {
  param($Cursor)
  if (
    $null -eq $script:Window -or
    $null -eq $Cursor -or
    -not $script:Window.IsVisible
  ) {
    return $false
  }

  $localX = [double]$Cursor.X - [double]$script:Window.Left
  $localY = [double]$Cursor.Y - [double]$script:Window.Top
  $padding = [Math]::Max(6.0, [Math]::Min(18.0, [double]$script:Style.HoverRange))
  foreach ($bounds in @($script:BatteryPrimaryBounds, $script:BatterySecondaryBounds)) {
    if ($null -eq $bounds) { continue }
    if (
      $localX -ge ([double]$bounds.X - $padding) -and
      $localX -le ([double]$bounds.X + [double]$bounds.Width + $padding) -and
      $localY -ge ([double]$bounds.Y - $padding) -and
      $localY -le ([double]$bounds.Y + [double]$bounds.Height + $padding)
    ) {
      return $true
    }
  }
  return $false
}

function Update-RingHoverVisibility {
  if ($null -eq $script:Window -or $null -eq $script:LastPetRect) {
    Hide-PetHud -UpdateGrowth $false
    return
  }

  if ($script:Style.VisibilityMode -eq "always") {
    Set-RingVisualsVisible -Visible $true
    Set-FrameTimerInterval -Fast $false
    return
  }

  $cursor = [System.Windows.Forms.Cursor]::Position
  $inventoryOpen = Test-InventoryReadoutOpen
  if ($script:Style.DisplayMode -eq "battery") {
    $showRing = $inventoryOpen -or (Test-CursorOverPet -Cursor $cursor) -or (Test-CursorInBatteryRange -Cursor $cursor) -or (Test-CursorInGrowthChipRange -Cursor $cursor) -or (Test-CursorInKeyCounterRange -Cursor $cursor) -or (Test-CursorInInventoryRange -Cursor $cursor)
  } elseif ($script:Style.DisplayMode -eq "badge") {
    $showRing = $inventoryOpen -or (Test-CursorOverPet -Cursor $cursor) -or (Test-CursorInBadgeRange -Cursor $cursor) -or (Test-CursorInGrowthChipRange -Cursor $cursor) -or (Test-CursorInKeyCounterRange -Cursor $cursor) -or (Test-CursorInInventoryRange -Cursor $cursor)
  } else {
    $showRing = $inventoryOpen -or (Test-CursorOverPet -Cursor $cursor) -or ($script:Window.IsVisible -and ((Test-CursorInRingRange -Cursor $cursor) -or (Test-CursorInGrowthChipRange -Cursor $cursor) -or (Test-CursorInKeyCounterRange -Cursor $cursor) -or (Test-CursorInInventoryRange -Cursor $cursor)))
  }
  Set-RingVisualsVisible -Visible $showRing
  Set-FrameTimerInterval -Fast $showRing
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
    if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
      Hide-InventoryReadout -ResetPinned
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
  if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
    Hide-InventoryReadout -ResetPinned
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
  $size = if ($null -ne $script:HudRingSize) { [double]$script:HudRingSize } else { [double]$script:Window.Width }
  $isBattery = $script:Style.DisplayMode -eq "battery"
  $isBadge = $script:Style.DisplayMode -eq "badge"
  $center = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX } else { $size / 2.0 }
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

  $primaryRemaining = Get-RingRemaining `
    -DisplayedValue $script:DisplayedUsageState.PrimaryRemaining `
    -TargetValue $script:UsageState.PrimaryRemaining
  $secondaryRemaining = Get-RingRemaining `
    -DisplayedValue $script:DisplayedUsageState.SecondaryRemaining `
    -TargetValue $script:UsageState.SecondaryRemaining
  $petBottom = if ($null -ne $script:LastPetRect) {
    [double]$script:LastPetRect.Y - [double]$script:Window.Top + [double]$script:LastPetRect.Height
  } else {
    [double]$script:Window.Height - 43.0
  }
  $growthHudVisible = Test-GrowthHudVisible
  $keyCounterHudVisible = Test-KeyCounterHudVisible
  $hudRowVisible = $growthHudVisible -or $keyCounterHudVisible
  if ($isBattery) {
    $barWidth = Get-BatteryHudBarWidth
    $barHeight = 10.0
    $barX = $center - $barWidth / 2.0
    $batteryHudRowHeight = if ($keyCounterHudVisible) {
      [Math]::Max((Get-KeyCounterChipHeight -Mode "battery"), $(if ((Test-InventoryHudVisible)) { 42.0 } else { 0.0 }))
    } elseif ($growthHudVisible) {
      26.0
    } else {
      0.0
    }
    $barOffset = if ($keyCounterHudVisible) {
      12.0 + $batteryHudRowHeight + 8.0
    } elseif ($growthHudVisible) {
      8.0 + $batteryHudRowHeight + 11.0
    } else {
      14.0
    }
    $barY = $petBottom + $barOffset
    $labelWidth = 24.0
    $bodyX = $barX + $labelWidth
    $bodyWidth = $barWidth - $labelWidth - 7.0
    $capWidth = 4.0
    $primaryFillWidth = $bodyWidth * ([Math]::Max(0.0, [Math]::Min(100.0, $primaryRemaining)) / 100.0)
    $secondaryFillWidth = $bodyWidth * ([Math]::Max(0.0, [Math]::Min(100.0, $secondaryRemaining)) / 100.0)

    Set-RectangleBounds $script:PrimaryBatteryTrack $bodyX $barY $bodyWidth $barHeight
    Set-RectangleBounds $script:PrimaryBatteryFill $bodyX $barY $primaryFillWidth $barHeight
    Set-RectangleBounds $script:PrimaryBatteryCap ($bodyX + $bodyWidth + 2.0) ($barY + 2.0) $capWidth ($barHeight - 4.0)
    Set-RectangleBounds $script:SecondaryBatteryTrack $bodyX ($barY + 17.0) $bodyWidth $barHeight
    Set-RectangleBounds $script:SecondaryBatteryFill $bodyX ($barY + 17.0) $secondaryFillWidth $barHeight
    Set-RectangleBounds $script:SecondaryBatteryCap ($bodyX + $bodyWidth + 2.0) ($barY + 19.0) $capWidth ($barHeight - 4.0)
    [System.Windows.Controls.Canvas]::SetLeft($script:PrimaryBatteryLabel, $barX)
    [System.Windows.Controls.Canvas]::SetTop($script:PrimaryBatteryLabel, $barY - 3.0)
    [System.Windows.Controls.Canvas]::SetLeft($script:SecondaryBatteryLabel, $barX)
    [System.Windows.Controls.Canvas]::SetTop($script:SecondaryBatteryLabel, $barY + 14.0)
    $script:BatteryPrimaryBounds = [pscustomobject]@{ X = $barX; Y = $barY; Width = $barWidth + $capWidth + 3.0; Height = $barHeight }
    $script:BatterySecondaryBounds = [pscustomobject]@{ X = $barX; Y = $barY + 17.0; Width = $barWidth + $capWidth + 3.0; Height = $barHeight }
    $script:PrimaryBatteryFill.Fill = Get-CapacityBrush -Remaining $primaryRemaining
    $script:SecondaryBatteryFill.Fill = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary
    $script:BadgePrimaryBounds = $null
    $script:BadgeSecondaryBounds = $null
  } elseif ($isBadge) {
    $badgeWidth = Get-BadgeHudWidth
    $badgeHeight = 26.0
    $badgeX = $center - $badgeWidth / 2.0
    $badgeY = $petBottom + 8.0
    $gap = 4.0
    $chipCount = if ($keyCounterHudVisible) { 3.0 } else { 2.0 }
    $chipWidth = ($badgeWidth - 12.0 - ($gap * ($chipCount - 1.0))) / $chipCount
    $chipHeight = $badgeHeight - 8.0
    $chipY = $badgeY + 4.0
    $primaryChipX = $badgeX + 6.0
    $secondaryChipX = $primaryChipX + $chipWidth + $gap

    Set-RectangleBounds $script:BadgeBackground $badgeX $badgeY $badgeWidth $badgeHeight
    Set-RectangleBounds $script:PrimaryBadgeChip $primaryChipX $chipY $chipWidth $chipHeight
    Set-RectangleBounds $script:SecondaryBadgeChip $secondaryChipX $chipY $chipWidth $chipHeight
    Set-RectangleBounds $script:BadgeDivider ($primaryChipX + $chipWidth + ($gap / 2.0) - 0.5) ($chipY + 2.5) 1.0 ($chipHeight - 5.0)

    foreach ($labelInfo in @(
      @{ Label = $script:PrimaryBadgeLabel; X = $primaryChipX; Text = ("5h {0}" -f (Format-Percent $primaryRemaining)) },
      @{ Label = $script:SecondaryBadgeLabel; X = $secondaryChipX; Text = ("W {0}" -f (Format-Percent $secondaryRemaining)) }
    )) {
      $label = $labelInfo.Label
      if ($null -eq $label) { continue }
      $label.Text = $labelInfo.Text
      $label.Width = $chipWidth
      $label.Height = $chipHeight
      [System.Windows.Controls.Canvas]::SetLeft($label, [double]$labelInfo.X)
      [System.Windows.Controls.Canvas]::SetTop($label, $chipY + 2.0)
    }

    $script:BadgePrimaryBounds = [pscustomobject]@{ X = $primaryChipX; Y = $chipY; Width = $chipWidth; Height = $chipHeight }
    $script:BadgeSecondaryBounds = [pscustomobject]@{ X = $secondaryChipX; Y = $chipY; Width = $chipWidth; Height = $chipHeight }
    $script:BatteryPrimaryBounds = $null
    $script:BatterySecondaryBounds = $null
    $script:PrimaryBadgeChip.Fill = Get-CapacityBrush -Remaining $primaryRemaining
    $script:SecondaryBadgeChip.Fill = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary
  } else {
    $script:BatteryPrimaryBounds = $null
    $script:BatterySecondaryBounds = $null
    $script:BadgePrimaryBounds = $null
    $script:BadgeSecondaryBounds = $null
    Set-EllipseBounds $script:OuterTrack $center $outerRadius
    Set-EllipseBounds $script:InnerTrack $center $innerRadius
    $script:OuterArc.Data = New-ArcGeometry -Center $center -Radius $outerRadius -Percent $primaryRemaining
    $script:InnerArc.Data = New-ArcGeometry -Center $center -Radius $innerRadius -Percent $secondaryRemaining
    $script:OuterArc.Stroke = Get-CapacityBrush -Remaining $primaryRemaining
    $script:InnerArc.Stroke = Get-CapacityBrush -Remaining $secondaryRemaining -Secondary
  }
  Update-ModeShapeVisibility
  Update-GrowthChipGeometry
  Update-KeyCounterGeometry
  Update-InventoryGeometry

  [void](Update-ReadoutText)
}

function Set-PetAutoDetectState {
  param([bool]$Visible)
  if ($script:LastPetVisible -ne $Visible) {
    $script:LastPetVisible = $Visible
    if ($Visible) {
      Write-AppLog "Codex /pet overlay detected; showing usage visuals."
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
  if ($Active) {
    if ($null -ne $script:FrameTimer -and -not $script:FrameTimer.IsEnabled) { $script:FrameTimer.Start() }
  } else {
    if ($null -ne $script:FrameTimer -and $script:FrameTimer.IsEnabled) { $script:FrameTimer.Stop() }
    Hide-PetHud -UpdateGrowth $true
  }
}

function Update-PetFrame {
  if (-not $script:RingsEnabled) {
    Set-FrameTimerActive -Active $false
    return
  }

  $rect = Read-PetRect
  if ($null -eq $rect) {
    Set-PetAutoDetectState -Visible $false
    Set-FrameTimerActive -Active $false
    return
  }

  Set-PetAutoDetectState -Visible $true
  $isBattery = $script:Style.DisplayMode -eq "battery"
  $isBadge = $script:Style.DisplayMode -eq "badge"
  $growthHudVisible = Test-GrowthHudVisible
  $keyCounterHudVisible = Test-KeyCounterHudVisible
  $hudRowVisible = $growthHudVisible -or $keyCounterHudVisible
  $keyChipWidth = if ($keyCounterHudVisible) { Get-KeyCounterChipWidth -Mode ([string]$script:Style.DisplayMode) } else { 0.0 }
  $keyChipHeight = if ($keyCounterHudVisible) { Get-KeyCounterChipHeight -Mode ([string]$script:Style.DisplayMode) } else { 0.0 }
  $growthChipWidth = if ($growthHudVisible) { Get-GrowthChipWidth } else { 0.0 }
  $inventoryChipWidth = if ((Test-InventoryHudVisible)) { Get-InventoryHudWidth } else { 0.0 }
  $inventoryChipHeight = if ((Test-InventoryHudVisible)) { 42.0 } else { 0.0 }
  $growthChipHeight = if ($growthHudVisible) { 26.0 } else { 0.0 }
  $hudRowGap = if ($growthHudVisible -and $keyCounterHudVisible -and -not $isBadge) { 6.0 } else { 0.0 }
  $inventoryGap = if ($inventoryChipWidth -gt 0.0 -and -not $isBadge) { 6.0 } else { 0.0 }
  $hudRowWidth = $growthChipWidth + $hudRowGap + $(if ($isBadge) { 0.0 } else { $keyChipWidth + $inventoryGap + $inventoryChipWidth })
  $hudRowHeight = [Math]::Max($growthChipHeight, [Math]::Max($keyChipHeight, $inventoryChipHeight))
  if ($isBattery) {
    $baseWindowWidth = [Math]::Max([double]$rect.Width + 34.0, [Math]::Max(164.0, $hudRowWidth + 24.0))
    $windowWidth = $baseWindowWidth
    $batteryHudHeight = if ($keyCounterHudVisible) { [Math]::Max(108.0, $hudRowHeight + 56.0) } elseif ($growthHudVisible) { 84.0 } else { 47.0 }
    $windowHeight = [double]$rect.Height + $batteryHudHeight
    $ringSize = [Math]::Max($baseWindowWidth, $windowHeight)
    $hudCenterX = $baseWindowWidth / 2.0
    $left = [double]$rect.X + [double]$rect.Width / 2.0 - $hudCenterX
    $top = [double]$rect.Y
  } elseif ($isBadge) {
    $badgeMinimumWidth = if ($keyCounterHudVisible) { 246.0 } else { 164.0 }
    $baseWindowWidth = [Math]::Max([double]$rect.Width + 40.0, $badgeMinimumWidth)
    $windowWidth = $baseWindowWidth
    $badgeHudHeight = if ($hudRowVisible) { 73.0 } else { 40.0 }
    $windowHeight = [double]$rect.Height + $badgeHudHeight
    $ringSize = [Math]::Max($baseWindowWidth, $windowHeight)
    $hudCenterX = $baseWindowWidth / 2.0
    $left = [double]$rect.X + [double]$rect.Width / 2.0 - $hudCenterX
    $top = [double]$rect.Y
  } else {
    $ringPadding = [double]$script:Style.RingGap + 16.0
    $ringSize = [Math]::Max([double]$rect.Width, [double]$rect.Height) + $ringPadding * 2.0
    $minimumRingHudWidth = if ($hudRowVisible) { [Math]::Max(164.0, $hudRowWidth + 24.0) } else { $ringSize }
    $ringHudHeight = if ($hudRowVisible) { [Math]::Max(40.0, $hudRowHeight + 12.0) } else { 0.0 }
    $baseWindowWidth = [Math]::Max($ringSize, $minimumRingHudWidth)
    $windowWidth = $baseWindowWidth
    $windowHeight = $ringSize + $ringHudHeight
    $hudCenterX = $ringSize / 2.0
    $left = [double]$rect.X + [double]$rect.Width / 2.0 - $hudCenterX
    $top = [double]$rect.Y + [double]$rect.Height / 2.0 - $ringSize / 2.0
  }

  $signature = "{0}|{1:N1}|{2:N1}|{3:N1}|{4:N1}|{5:N1}|{6:N1}|{7:N1}|{8}|{9}|{10:N1}|{11:N1}|{12:N1}|{13:N1}" -f `
    $script:Style.DisplayMode,
    $left,
    $top,
    $windowWidth,
    $windowHeight,
    $rect.X,
    $rect.Y,
    $ringSize,
    $growthHudVisible,
    $keyCounterHudVisible,
    $hudCenterX,
    $keyChipWidth,
    $keyChipHeight,
    $hudRowHeight
  $changed = $signature -ne $script:LastPetFrameSignature
  if ($changed) {
    $script:LastPetRect = $rect
    $script:LastPetFrameSignature = $signature
    $script:RingOuterRadius = if ($isBattery -or $isBadge) { $null } else { $ringSize / 2.0 - 16.0 }
    $script:RingInnerRadius = if ($isBattery -or $isBadge) { $null } else { $script:RingOuterRadius - 13.0 }
    $script:HudCenterX = $hudCenterX
    $script:HudRingSize = $ringSize
    $script:Window.Width = $windowWidth
    $script:Window.Height = $windowHeight
    $script:Canvas.Width = $windowWidth
    $script:Canvas.Height = $windowHeight
    $script:Window.Left = $left
    $script:Window.Top = $top
    Update-RingGeometry
  }

  Set-FrameTimerActive -Active $true
  Update-PetGrowth -PetVisible $true
  Update-GrowthChipGeometry
  Update-KeyCounterGeometry
  Update-InventoryGeometry
  Update-KeyCounter
  Update-MouseClickHook
  Update-RingHoverVisibility
  Update-HoverReadout
  Move-RingBehindCodex
}

function Update-HoverReadout {
  if ($null -eq $script:Window -or $null -eq $script:LastPetRect -or -not $script:Window.IsVisible) {
    Hide-RingReadouts
    return
  }
  Update-MouseClickHook
  $cursor = [System.Windows.Forms.Cursor]::Position
  $localX = [double]$cursor.X - [double]$script:Window.Left
  $localY = [double]$cursor.Y - [double]$script:Window.Top
  $clickCursor = Get-ConsumedLeftMouseClickCursor
  $clickInInventory = $false
  $clickLocalX = $localX
  $clickLocalY = $localY
  if ($null -ne $clickCursor) {
    $clickInInventory = Test-CursorInInventoryRange -Cursor $clickCursor
    $clickLocalX = [double]$clickCursor.X - [double]$script:Window.Left
    $clickLocalY = [double]$clickCursor.Y - [double]$script:Window.Top
  }
  $width = [double]$script:Window.Width
  $height = [double]$script:Window.Height
  if ($localX -lt 0 -or $localY -lt 0 -or $localX -gt $width -or $localY -gt $height) {
    if ($clickInInventory) {
      Set-InventoryHoverHighlight -Visible $true
      Invoke-InventoryToggle -LocalX $clickLocalX -LocalY $clickLocalY
      return
    }
    $script:InventoryMouseWasDown = $false
    Set-InventoryHoverHighlight -Visible (Test-InventoryReadoutOpen)
    Hide-RingReadouts
    return
  }
  $leftMouseDown = $false
  $leftMouseClicked = $false
  try { $leftMouseDown = [bool][CodexPetLimitRingNative]::IsLeftMouseButtonDown() } catch {}
  try { $leftMouseClicked = [bool][CodexPetLimitRingNative]::ConsumeLeftMouseButtonClick() } catch {}
  if ($clickInInventory) {
    Set-InventoryHoverHighlight -Visible $true
    Invoke-InventoryToggle -LocalX $clickLocalX -LocalY $clickLocalY
    return
  }
  if ((Test-CursorInInventoryRange -Cursor $cursor)) {
    Set-InventoryHoverHighlight -Visible $true
    try { [CodexPetLimitRingNative]::ShowHandCursor() } catch {}
    if ($clickInInventory -or $leftMouseClicked -or ($leftMouseDown -and -not $script:InventoryMouseWasDown)) {
      Invoke-InventoryToggle -LocalX $clickLocalX -LocalY $clickLocalY
      return
    }
    $script:InventoryMouseWasDown = $leftMouseDown
    if ($null -ne $script:InventoryReadoutWindow -and $script:InventoryReadoutWindow.IsVisible) {
      return
    }
  } else {
    $script:InventoryMouseWasDown = $leftMouseDown
    Set-InventoryHoverHighlight -Visible (Test-InventoryReadoutOpen)
  }
  if ((Test-CursorInGrowthChipRange -Cursor $cursor) -and $script:Style.ShowGrowthHoverReadout) {
    $hoverSignature = "Growth|{0:N0}|{1:N0}" -f $localX, $localY
    if ($script:LastHoverSignature -eq $hoverSignature) { return }
    $script:LastHoverSignature = $hoverSignature
    Show-GrowthReadout
    return
  }
  if ($script:Style.DisplayMode -in @("battery", "badge")) {
    $primary = if ($script:Style.DisplayMode -eq "badge") { $script:BadgePrimaryBounds } else { $script:BatteryPrimaryBounds }
    $secondary = if ($script:Style.DisplayMode -eq "badge") { $script:BadgeSecondaryBounds } else { $script:BatterySecondaryBounds }
    $hitPadding = 8.0
    $textUpdated = [bool](Update-ReadoutText)
    foreach ($candidate in @(
      @{ Ring = "Outer"; Bounds = $primary },
      @{ Ring = "Inner"; Bounds = $secondary }
    )) {
      $bounds = $candidate.Bounds
      if ($null -eq $bounds) { continue }
      if (
        $localX -ge ([double]$bounds.X - $hitPadding) -and
        $localX -le ([double]$bounds.X + [double]$bounds.Width + $hitPadding) -and
        $localY -ge ([double]$bounds.Y - $hitPadding) -and
        $localY -le ([double]$bounds.Y + [double]$bounds.Height + $hitPadding)
      ) {
        $hoverSignature = "{0}|{1:N0}|{2:N0}" -f $candidate.Ring, $localX, $localY
        if (-not $textUpdated -and $script:LastHoverSignature -eq $hoverSignature) { return }
        $script:LastHoverSignature = $hoverSignature
        Show-RingReadout -Ring $candidate.Ring -X ([double]$bounds.X + [double]$bounds.Width / 2.0) -Y ([double]$bounds.Y + [double]$bounds.Height / 2.0) -Size $width
        return
      }
    }
    Hide-RingReadouts
    return
  }
  $size = if ($null -ne $script:HudRingSize) { [double]$script:HudRingSize } else { [double]$script:Window.Width }
  $centerX = if ($null -ne $script:HudCenterX) { [double]$script:HudCenterX } else { $size / 2.0 }
  $centerY = $size / 2.0
  $distance = [Math]::Sqrt([Math]::Pow($localX - $centerX, 2) + [Math]::Pow($localY - $centerY, 2))
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
  Write-AppLog "Stopping Codexy pet usages ring."
  Hide-RingReadouts
  Hide-PetHud -UpdateGrowth $false
  try { [CodexPetLimitRingNative]::UninstallKeyboardCounter() } catch {}
  if ($null -ne $script:NotifyIcon) {
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
  }
  [System.Windows.Application]::Current.Shutdown()
}

function Test-CodexDesktopAlive {
  if ($NoExitWithCodex) { return $true }
  try {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'Codex.exe'" -ErrorAction Stop)
    return [bool]($processes | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
      (Split-Path -Leaf $_.ExecutablePath) -ieq "Codex.exe" -and
      $_.ExecutablePath -notmatch '\\resources\\codex\.exe$' -and
      $_.CommandLine -notmatch '\s--type='
    } | Select-Object -First 1)
  } catch {
    return [CodexPetLimitRingNative]::IsCodexDesktopRunning()
  }
}

function Stop-WhenCodexDesktopClosed {
  if ($NoExitWithCodex) { return }
  if (Test-CodexDesktopAlive) { return }
  Write-AppLog "Codex Desktop is not running; stopping companion helper."
  Stop-RingsApp
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
  param($Content, [bool]$ClickThrough = $true)
  $window = [System.Windows.Window]::new()
  $window.WindowStyle = [System.Windows.WindowStyle]::None
  $window.AllowsTransparency = $true
  $window.Background = [System.Windows.Media.Brushes]::Transparent
  $window.Topmost = $true
  $window.ShowInTaskbar = $false
  $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
  $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
  $window.Content = $Content
  if ($ClickThrough) {
    $window.Add_SourceInitialized({
      param($Sender, $EventArgs)
      $handle = (New-Object System.Windows.Interop.WindowInteropHelper($Sender)).Handle
      [CodexPetLimitRingNative]::MakeClickThrough($handle)
    })
  }
  return $window
}

function New-InventoryItemCell {
  param([string]$ItemKey, [string]$IconPath)

  $border = [System.Windows.Controls.Border]::new()
  $border.Background = New-Brush 86 10 17 24
  $border.BorderBrush = New-Brush 92 255 255 255
  $border.BorderThickness = [System.Windows.Thickness]::new(1)
  $border.CornerRadius = [System.Windows.CornerRadius]::new(7)
  $border.Padding = [System.Windows.Thickness]::new(6, 5, 6, 5)
  $border.Margin = [System.Windows.Thickness]::new(3)
  $border.Cursor = [System.Windows.Input.Cursors]::Hand

  $panel = [System.Windows.Controls.StackPanel]::new()
  $panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
  $panel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

  $image = [System.Windows.Controls.Image]::new()
  $image.Source = New-RuntimeImageSource -Path $IconPath -Name $ItemKey -DecodePixelWidth 64
  $image.Width = 34.0
  $image.Height = 34.0
  $image.Stretch = [System.Windows.Media.Stretch]::Uniform
  $image.SnapsToDevicePixels = $true
  $image.UseLayoutRounding = $true
  $image.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)

  $copyPanel = [System.Windows.Controls.StackPanel]::new()
  $copyPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
  $copyPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

  $label = [System.Windows.Controls.TextBlock]::new()
  $label.Text = Get-InventoryUiText -Key $ItemKey
  $label.Foreground = New-Brush 236 255 255 255
  $label.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
  $label.FontSize = 9.5
  $label.FontWeight = [System.Windows.FontWeights]::SemiBold
  $label.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
  $label.Width = 74.0

  $count = [System.Windows.Controls.TextBlock]::new()
  $count.Text = "x0"
  $count.Foreground = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
  $count.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
  $count.FontSize = 13.0
  $count.FontWeight = [System.Windows.FontWeights]::Bold
  $count.LineHeight = 15.0

  $copyPanel.Children.Add($label) | Out-Null
  $copyPanel.Children.Add($count) | Out-Null
  $panel.Children.Add($image) | Out-Null
  $panel.Children.Add($copyPanel) | Out-Null
  $border.Child = $panel

  $script:InventoryItemLabelBlocks[$ItemKey] = $label
  $script:InventoryItemCountBlocks[$ItemKey] = $count
  $script:InventoryItemBorders[$ItemKey] = $border
  $border.Add_MouseLeftButtonUp({
    param($Sender, $EventArgs)
    Set-ActiveInventoryUnlock -ItemKey $ItemKey
    $EventArgs.Handled = $true
  }.GetNewClosure())
  return $border
}

function New-InventoryCategoryCell {
  param([string]$Kind, [string]$LabelKey)

  $border = [System.Windows.Controls.Border]::new()
  $border.Background = New-Brush 98 10 17 24
  $border.BorderBrush = New-StyleBrush 160 ([int[]](Get-CosmeticAccentRgb))
  $border.BorderThickness = [System.Windows.Thickness]::new(1.5)
  $border.CornerRadius = [System.Windows.CornerRadius]::new(7)
  $border.Padding = [System.Windows.Thickness]::new(9, 8, 9, 8)
  $border.Margin = [System.Windows.Thickness]::new(3)
  $border.Cursor = [System.Windows.Input.Cursors]::Hand

  $panel = [System.Windows.Controls.StackPanel]::new()
  $panel.Orientation = [System.Windows.Controls.Orientation]::Vertical
  $panel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

  $title = [System.Windows.Controls.TextBlock]::new()
  $title.Text = Get-InventoryUiText -Key $LabelKey
  $title.Foreground = New-Brush 242 255 255 255
  $title.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
  $title.FontSize = 12.5
  $title.FontWeight = [System.Windows.FontWeights]::Bold
  $title.TextAlignment = [System.Windows.TextAlignment]::Center
  $title.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

  $hint = [System.Windows.Controls.TextBlock]::new()
  $hint.Text = Get-InventoryUiText -Key "Select"
  $hint.Foreground = New-StyleBrush 210 ([int[]](Get-CosmeticAccentRgb))
  $hint.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
  $hint.FontSize = 9.5
  $hint.FontWeight = [System.Windows.FontWeights]::SemiBold
  $hint.TextAlignment = [System.Windows.TextAlignment]::Center
  $hint.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)

  $panel.Children.Add($title) | Out-Null
  $panel.Children.Add($hint) | Out-Null
  $border.Child = $panel
  $border.Add_MouseLeftButtonUp({
    param($Sender, $EventArgs)
    Show-InventoryPicker -Kind $Kind
    $EventArgs.Handled = $true
  }.GetNewClosure())
  return $border
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

$script:PrimaryBatteryTrack = [System.Windows.Shapes.Rectangle]::new()
$script:PrimaryBatteryTrack.RadiusX = 3
$script:PrimaryBatteryTrack.RadiusY = 3
$script:PrimaryBatteryTrack.StrokeThickness = 1
$script:PrimaryBatteryTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
$script:PrimaryBatteryTrack.Fill = New-StyleBrush ([byte][Math]::Max(8, [Math]::Min(255, [int]$script:Style.TrackOpacity + 12))) ([int[]]$script:Style.TrackRgb)

$script:PrimaryBatteryFill = [System.Windows.Shapes.Rectangle]::new()
$script:PrimaryBatteryFill.RadiusX = 3
$script:PrimaryBatteryFill.RadiusY = 3

$script:PrimaryBatteryCap = [System.Windows.Shapes.Rectangle]::new()
$script:PrimaryBatteryCap.RadiusX = 1.5
$script:PrimaryBatteryCap.RadiusY = 1.5
$script:PrimaryBatteryCap.Fill = New-StyleBrush ([byte][Math]::Max(22, [Math]::Min(255, [int]$script:Style.TrackOpacity + 28))) ([int[]]$script:Style.TrackRgb)

$script:SecondaryBatteryTrack = [System.Windows.Shapes.Rectangle]::new()
$script:SecondaryBatteryTrack.RadiusX = 3
$script:SecondaryBatteryTrack.RadiusY = 3
$script:SecondaryBatteryTrack.StrokeThickness = 1
$script:SecondaryBatteryTrack.Stroke = New-StyleBrush ([byte]$script:Style.TrackOpacity) ([int[]]$script:Style.TrackRgb)
$script:SecondaryBatteryTrack.Fill = New-StyleBrush ([byte][Math]::Max(8, [Math]::Min(255, [int]$script:Style.TrackOpacity + 12))) ([int[]]$script:Style.TrackRgb)

$script:SecondaryBatteryFill = [System.Windows.Shapes.Rectangle]::new()
$script:SecondaryBatteryFill.RadiusX = 3
$script:SecondaryBatteryFill.RadiusY = 3

$script:SecondaryBatteryCap = [System.Windows.Shapes.Rectangle]::new()
$script:SecondaryBatteryCap.RadiusX = 1.5
$script:SecondaryBatteryCap.RadiusY = 1.5
$script:SecondaryBatteryCap.Fill = New-StyleBrush ([byte][Math]::Max(22, [Math]::Min(255, [int]$script:Style.TrackOpacity + 28))) ([int[]]$script:Style.TrackRgb)

$script:PrimaryBatteryLabel = [System.Windows.Controls.TextBlock]::new()
$script:PrimaryBatteryLabel.Text = "5h"
$script:PrimaryBatteryLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:PrimaryBatteryLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:PrimaryBatteryLabel.FontSize = 9.0
$script:PrimaryBatteryLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
$script:PrimaryBatteryLabel.Opacity = 0.86

$script:SecondaryBatteryLabel = [System.Windows.Controls.TextBlock]::new()
$script:SecondaryBatteryLabel.Text = "W"
$script:SecondaryBatteryLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:SecondaryBatteryLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:SecondaryBatteryLabel.FontSize = 9.0
$script:SecondaryBatteryLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
$script:SecondaryBatteryLabel.Opacity = 0.86

$script:BadgeBackground = [System.Windows.Shapes.Rectangle]::new()
$script:BadgeBackground.RadiusX = 13
$script:BadgeBackground.RadiusY = 13
$script:BadgeBackground.StrokeThickness = 1
$script:BadgeBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
$script:BadgeBackground.Stroke = New-StyleBrush ([byte][Math]::Max(20, [Math]::Min(255, [int]$script:Style.TrackOpacity + 34))) ([int[]]$script:Style.TrackRgb)

$script:PrimaryBadgeChip = [System.Windows.Shapes.Rectangle]::new()
$script:PrimaryBadgeChip.RadiusX = 9
$script:PrimaryBadgeChip.RadiusY = 9

$script:SecondaryBadgeChip = [System.Windows.Shapes.Rectangle]::new()
$script:SecondaryBadgeChip.RadiusX = 9
$script:SecondaryBadgeChip.RadiusY = 9

$script:BadgeDivider = [System.Windows.Shapes.Rectangle]::new()
$script:BadgeDivider.RadiusX = 0.5
$script:BadgeDivider.RadiusY = 0.5
$script:BadgeDivider.Fill = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 26))) ([int[]]$script:Style.TrackRgb)

$script:PrimaryBadgeLabel = [System.Windows.Controls.TextBlock]::new()
$script:PrimaryBadgeLabel.Text = "5h --"
$script:PrimaryBadgeLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:PrimaryBadgeLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:PrimaryBadgeLabel.FontSize = 10.0
$script:PrimaryBadgeLabel.FontWeight = [System.Windows.FontWeights]::Bold
$script:PrimaryBadgeLabel.TextAlignment = [System.Windows.TextAlignment]::Center
$script:PrimaryBadgeLabel.Opacity = 0.96

$script:SecondaryBadgeLabel = [System.Windows.Controls.TextBlock]::new()
$script:SecondaryBadgeLabel.Text = "W --"
$script:SecondaryBadgeLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:SecondaryBadgeLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:SecondaryBadgeLabel.FontSize = 10.0
$script:SecondaryBadgeLabel.FontWeight = [System.Windows.FontWeights]::Bold
$script:SecondaryBadgeLabel.TextAlignment = [System.Windows.TextAlignment]::Center
$script:SecondaryBadgeLabel.Opacity = 0.96

$script:GrowthChipBackground = [System.Windows.Shapes.Rectangle]::new()
$script:GrowthChipBackground.RadiusX = 8
$script:GrowthChipBackground.RadiusY = 8
$script:GrowthChipBackground.StrokeThickness = 1
$script:GrowthChipBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
$script:GrowthChipBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 36))) ([int[]]$script:Style.TrackRgb)

$script:GrowthChipAccent = [System.Windows.Shapes.Rectangle]::new()
$script:GrowthChipAccent.RadiusX = 2.5
$script:GrowthChipAccent.RadiusY = 2.5
$script:GrowthChipAccent.Fill = Get-PetGrowthBrush -Condition ([string]$script:PetGrowthState.condition)

$script:GrowthChipLabel = [System.Windows.Controls.TextBlock]::new()
$script:GrowthChipLabel.Text = Get-PetGrowthChipText
$script:GrowthChipLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:GrowthChipLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:GrowthChipLabel.FontSize = 10.5
$script:GrowthChipLabel.FontWeight = [System.Windows.FontWeights]::Bold
$script:GrowthChipLabel.TextAlignment = [System.Windows.TextAlignment]::Left
$script:GrowthChipLabel.Opacity = 0.96
$script:GrowthChipLabel.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

$script:KeyCounterBackground = [System.Windows.Shapes.Rectangle]::new()
$script:KeyCounterBackground.RadiusX = 8
$script:KeyCounterBackground.RadiusY = 8
$script:KeyCounterBackground.StrokeThickness = 1
$script:KeyCounterBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
$script:KeyCounterBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 42))) ([int[]]$script:Style.TrackRgb)

$script:KeyCounterThemeBorder = [System.Windows.Controls.Image]::new()
$script:KeyCounterThemeBorder.Source = New-ActiveThemeBorderImageSource
$script:KeyCounterThemeBorder.Stretch = [System.Windows.Media.Stretch]::Fill
$script:KeyCounterThemeBorder.SnapsToDevicePixels = $true
$script:KeyCounterThemeBorder.UseLayoutRounding = $true
$script:KeyCounterThemeBorder.IsHitTestVisible = $false
$script:KeyCounterThemeBorder.Visibility = [System.Windows.Visibility]::Collapsed
$script:KeyCounterThemeBorder.Opacity = 0.94

$script:KeyCounterAccent = [System.Windows.Shapes.Rectangle]::new()
$script:KeyCounterAccent.RadiusX = 2.5
$script:KeyCounterAccent.RadiusY = 2.5
$script:KeyCounterAccent.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)
$script:KeyCounterAccent.Visibility = [System.Windows.Visibility]::Collapsed

$script:KeyCounterLabel = [System.Windows.Controls.TextBlock]::new()
$script:KeyCounterLabel.Text = Get-KeyCounterText
$script:KeyCounterLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:KeyCounterLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:KeyCounterLabel.FontSize = 20.0
$script:KeyCounterLabel.FontWeight = [System.Windows.FontWeights]::Black
$script:KeyCounterLabel.TextAlignment = [System.Windows.TextAlignment]::Center
$script:KeyCounterLabel.LineHeight = 18.8
$script:KeyCounterLabel.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
$script:KeyCounterLabel.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
$script:KeyCounterLabel.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1.0, 1.0)
$script:KeyCounterLabel.Opacity = 0.96
$script:KeyCounterLabel.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

$script:InventoryBackground = [System.Windows.Shapes.Rectangle]::new()
$script:InventoryBackground.RadiusX = 7
$script:InventoryBackground.RadiusY = 7
$script:InventoryBackground.StrokeThickness = 1
$script:InventoryBackground.Fill = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
$script:InventoryBackground.Stroke = New-StyleBrush ([byte][Math]::Max(24, [Math]::Min(255, [int]$script:Style.TrackOpacity + 36))) ([int[]]$script:Style.TrackRgb)
$script:InventoryBackground.Visibility = [System.Windows.Visibility]::Collapsed

$script:InventoryHoverBorder = [System.Windows.Shapes.Rectangle]::new()
$script:InventoryHoverBorder.RadiusX = 8
$script:InventoryHoverBorder.RadiusY = 8
$script:InventoryHoverBorder.StrokeThickness = 2.0
$script:InventoryHoverBorder.Stroke = New-Brush 236 255 218 0
$script:InventoryHoverBorder.Fill = New-Brush 22 255 218 0
$script:InventoryHoverBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:InventoryIcon = [System.Windows.Controls.Image]::new()
$script:InventoryIcon.Source = New-RewardChestImageSource
$script:InventoryIcon.Stretch = [System.Windows.Media.Stretch]::Uniform
$script:InventoryIcon.SnapsToDevicePixels = $true
$script:InventoryIcon.UseLayoutRounding = $true

$script:InventoryCountBackground = [System.Windows.Shapes.Rectangle]::new()
$script:InventoryCountBackground.RadiusX = 4
$script:InventoryCountBackground.RadiusY = 4
$script:InventoryCountBackground.Fill = New-StyleBrush ([byte]$script:Style.PrimaryOpacity) ([int[]]$script:Style.PrimaryRgb)

$script:InventoryLabel = [System.Windows.Controls.TextBlock]::new()
$script:InventoryLabel.Text = Get-InventoryHudText
$script:InventoryLabel.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:InventoryLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryLabel.FontSize = 7.5
$script:InventoryLabel.FontWeight = [System.Windows.FontWeights]::Bold
$script:InventoryLabel.TextAlignment = [System.Windows.TextAlignment]::Center
$script:InventoryLabel.Opacity = 0.92
$script:InventoryLabel.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

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

$script:GrowthReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:GrowthReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:GrowthReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:GrowthReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:GrowthReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")

$script:InventoryReadoutText = [System.Windows.Controls.TextBlock]::new()
$script:InventoryReadoutText.Text = Get-InventoryReadoutText
$script:InventoryReadoutText.Foreground = New-StyleBrush ([byte]$script:Style.ReadoutTextOpacity) ([int[]]$script:Style.ReadoutTextRgb)
$script:InventoryReadoutText.FontSize = [double]$script:Style.ReadoutFontSize
$script:InventoryReadoutText.LineHeight = [double]$script:Style.ReadoutLineHeight
$script:InventoryReadoutText.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryReadoutText.FontWeight = [System.Windows.FontWeights]::SemiBold
$script:InventoryReadoutText.Visibility = [System.Windows.Visibility]::Collapsed

$script:InventoryReadoutPanel = [System.Windows.Controls.StackPanel]::new()
$script:InventoryReadoutPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
$script:InventoryReadoutPanel.Width = 220.0

$script:InventoryReadoutTitle = [System.Windows.Controls.TextBlock]::new()
$script:InventoryReadoutTitle.Text = Get-InventoryUiText -Key "Title"
$script:InventoryReadoutTitle.Foreground = New-Brush 248 255 255 255
$script:InventoryReadoutTitle.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryReadoutTitle.FontSize = 13.5
$script:InventoryReadoutTitle.FontWeight = [System.Windows.FontWeights]::Bold
$script:InventoryReadoutTitle.Margin = [System.Windows.Thickness]::new(3, 0, 3, 2)

$script:InventoryReadoutHint = [System.Windows.Controls.TextBlock]::new()
$script:InventoryReadoutHint.Text = Get-InventoryUiText -Key "EmptyHint"
$script:InventoryReadoutHint.Foreground = New-Brush 190 220 236 244
$script:InventoryReadoutHint.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryReadoutHint.FontSize = 9.5
$script:InventoryReadoutHint.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
$script:InventoryReadoutHint.Margin = [System.Windows.Thickness]::new(3, 0, 3, 5)

$script:InventoryReadoutGrid = [System.Windows.Controls.Grid]::new()
$script:InventoryReadoutGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 5)
for ($i = 0; $i -lt 2; $i++) {
  $column = [System.Windows.Controls.ColumnDefinition]::new()
  $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
  $script:InventoryReadoutGrid.ColumnDefinitions.Add($column)
}
$row = [System.Windows.Controls.RowDefinition]::new()
$row.Height = [System.Windows.GridLength]::new(58.0)
$script:InventoryReadoutGrid.RowDefinitions.Add($row)

$fontCategoryCell = New-InventoryCategoryCell -Kind "font" -LabelKey "FontCategory"
[System.Windows.Controls.Grid]::SetColumn($fontCategoryCell, 0)
[System.Windows.Controls.Grid]::SetRow($fontCategoryCell, 0)
$themeCategoryCell = New-InventoryCategoryCell -Kind "theme" -LabelKey "ThemeCategory"
[System.Windows.Controls.Grid]::SetColumn($themeCategoryCell, 1)
[System.Windows.Controls.Grid]::SetRow($themeCategoryCell, 0)
$script:InventoryReadoutGrid.Children.Add($fontCategoryCell) | Out-Null
$script:InventoryReadoutGrid.Children.Add($themeCategoryCell) | Out-Null

$script:InventoryReadoutStats = [System.Windows.Controls.TextBlock]::new()
$script:InventoryReadoutStats.Foreground = New-Brush 202 220 236 244
$script:InventoryReadoutStats.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryReadoutStats.FontSize = 9.5
$script:InventoryReadoutStats.FontWeight = [System.Windows.FontWeights]::SemiBold
$script:InventoryReadoutStats.Margin = [System.Windows.Thickness]::new(3, 0, 3, 0)

$script:InventoryReadoutPanel.Children.Add($script:InventoryReadoutTitle) | Out-Null
$script:InventoryReadoutPanel.Children.Add($script:InventoryReadoutHint) | Out-Null
$script:InventoryReadoutPanel.Children.Add($script:InventoryReadoutGrid) | Out-Null
$script:InventoryReadoutPanel.Children.Add($script:InventoryReadoutStats) | Out-Null
$script:InventoryReadoutPanel.Children.Add($script:InventoryReadoutText) | Out-Null
[void](Update-InventoryReadoutContent)

$script:InventoryPickerPanel = [System.Windows.Controls.StackPanel]::new()
$script:InventoryPickerPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
$script:InventoryPickerPanel.Width = 260.0

$script:InventoryPickerTitle = [System.Windows.Controls.TextBlock]::new()
$script:InventoryPickerTitle.Text = Get-InventoryUiText -Key "ThemeCategory"
$script:InventoryPickerTitle.Foreground = New-Brush 248 255 255 255
$script:InventoryPickerTitle.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryPickerTitle.FontSize = 13.0
$script:InventoryPickerTitle.FontWeight = [System.Windows.FontWeights]::Bold
$script:InventoryPickerTitle.Margin = [System.Windows.Thickness]::new(3, 0, 3, 2)

$script:InventoryPickerHint = [System.Windows.Controls.TextBlock]::new()
$script:InventoryPickerHint.Text = Get-InventoryUiText -Key "PickerHintTheme"
$script:InventoryPickerHint.Foreground = New-Brush 190 220 236 244
$script:InventoryPickerHint.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:InventoryPickerHint.FontSize = 9.5
$script:InventoryPickerHint.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
$script:InventoryPickerHint.Margin = [System.Windows.Thickness]::new(3, 0, 3, 5)

$script:InventoryPickerGrid = [System.Windows.Controls.Grid]::new()
$script:InventoryPickerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
for ($i = 0; $i -lt 2; $i++) {
  $column = [System.Windows.Controls.ColumnDefinition]::new()
  $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
  $script:InventoryPickerGrid.ColumnDefinitions.Add($column)
}
for ($i = 0; $i -lt 3; $i++) {
  $row = [System.Windows.Controls.RowDefinition]::new()
  $row.Height = [System.Windows.GridLength]::new(50.0)
  $script:InventoryPickerGrid.RowDefinitions.Add($row)
}
foreach ($itemKey in $CosmeticUnlockKeys) {
  $itemCell = New-InventoryItemCell -ItemKey $itemKey -IconPath $InventoryIconPaths[$itemKey]
  $itemCell.Visibility = [System.Windows.Visibility]::Collapsed
  $script:InventoryPickerGrid.Children.Add($itemCell) | Out-Null
}
$script:InventoryPickerPanel.Children.Add($script:InventoryPickerTitle) | Out-Null
$script:InventoryPickerPanel.Children.Add($script:InventoryPickerHint) | Out-Null
$script:InventoryPickerPanel.Children.Add($script:InventoryPickerGrid) | Out-Null

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

$script:GrowthReadoutBorder = [System.Windows.Controls.Border]::new()
$script:GrowthReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.OuterReadoutBgRgb)
$script:GrowthReadoutBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:GrowthReadoutBorder.Padding = [System.Windows.Thickness]::new(7, 4, 7, 5)
$script:GrowthReadoutBorder.Child = $script:GrowthReadoutText
$script:GrowthReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:InventoryReadoutBorder = [System.Windows.Controls.Border]::new()
$script:InventoryReadoutBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
$script:InventoryReadoutBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:InventoryReadoutBorder.Padding = [System.Windows.Thickness]::new(8, 7, 8, 7)
$script:InventoryReadoutBorder.Child = $script:InventoryReadoutPanel
$script:InventoryReadoutBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:InventoryPickerBorder = [System.Windows.Controls.Border]::new()
$script:InventoryPickerBorder.Background = New-StyleBrush ([byte]$script:Style.ReadoutOpacity) ([int[]]$script:Style.InnerReadoutBgRgb)
$script:InventoryPickerBorder.CornerRadius = [System.Windows.CornerRadius]::new(7)
$script:InventoryPickerBorder.Padding = [System.Windows.Thickness]::new(8, 7, 8, 7)
$script:InventoryPickerBorder.Child = $script:InventoryPickerPanel
$script:InventoryPickerBorder.Visibility = [System.Windows.Visibility]::Collapsed

$script:OuterReadoutWindow = New-ReadoutWindow -Content $script:OuterReadoutBorder
$script:InnerReadoutWindow = New-ReadoutWindow -Content $script:InnerReadoutBorder
$script:GrowthReadoutWindow = New-ReadoutWindow -Content $script:GrowthReadoutBorder
$script:InventoryReadoutWindow = New-ReadoutWindow -Content $script:InventoryReadoutBorder -ClickThrough $false
$script:InventoryPickerWindow = New-ReadoutWindow -Content $script:InventoryPickerBorder -ClickThrough $false

$script:Canvas.Children.Add($script:OuterTrack) | Out-Null
$script:Canvas.Children.Add($script:InnerTrack) | Out-Null
$script:Canvas.Children.Add($script:OuterArc) | Out-Null
$script:Canvas.Children.Add($script:InnerArc) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBatteryTrack) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBatteryFill) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBatteryCap) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBatteryLabel) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBatteryTrack) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBatteryFill) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBatteryCap) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBatteryLabel) | Out-Null
$script:Canvas.Children.Add($script:BadgeBackground) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBadgeChip) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBadgeChip) | Out-Null
$script:Canvas.Children.Add($script:BadgeDivider) | Out-Null
$script:Canvas.Children.Add($script:PrimaryBadgeLabel) | Out-Null
$script:Canvas.Children.Add($script:SecondaryBadgeLabel) | Out-Null
$script:Canvas.Children.Add($script:GrowthChipBackground) | Out-Null
$script:Canvas.Children.Add($script:GrowthChipAccent) | Out-Null
$script:Canvas.Children.Add($script:GrowthChipLabel) | Out-Null
$script:Canvas.Children.Add($script:KeyCounterBackground) | Out-Null
$script:Canvas.Children.Add($script:KeyCounterThemeBorder) | Out-Null
$script:Canvas.Children.Add($script:KeyCounterAccent) | Out-Null
$script:Canvas.Children.Add($script:KeyCounterLabel) | Out-Null
$script:Canvas.Children.Add($script:InventoryBackground) | Out-Null
$script:Canvas.Children.Add($script:InventoryHoverBorder) | Out-Null
$script:Canvas.Children.Add($script:InventoryIcon) | Out-Null
$script:Canvas.Children.Add($script:InventoryCountBackground) | Out-Null
$script:Canvas.Children.Add($script:InventoryLabel) | Out-Null
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

$script:KeyCounterTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:KeyCounterTimer.Interval = [TimeSpan]::FromMilliseconds($KeyCounterPollMs)
$script:KeyCounterTimer.Add_Tick({
  try {
    Update-KeyCounter
  } catch {
    Write-AppLog "Key counter update failed: $($_.Exception.Message)"
  }
})
$script:KeyCounterTimer.Start()

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

$script:LifecycleTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:LifecycleTimer.Interval = [TimeSpan]::FromSeconds(5)
$script:LifecycleTimer.Add_Tick({
  try {
    Stop-WhenCodexDesktopClosed
  } catch {
    Write-AppLog "Lifecycle check failed: $($_.Exception.Message)"
  }
})
$script:LifecycleTimer.Start()

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
      Update-KeyCounterHook
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
  Save-PetGrowthState -Force
  try { [CodexPetLimitRingNative]::UninstallKeyboardCounter() } catch {}
  try { [CodexPetLimitRingNative]::UninstallMouseClickCounter() } catch {}
  foreach ($timer in @($script:FrameTimer, $script:KeyCounterTimer, $script:PetTimer, $script:LifecycleTimer, $script:UsageTimer, $script:SettingsTimer, $script:MaintenanceTimer)) {
    if ($null -ne $timer) {
      try { $timer.Stop() } catch {}
    }
  }
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
