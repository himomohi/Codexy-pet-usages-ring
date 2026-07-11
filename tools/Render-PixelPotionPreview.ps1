param(
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$runtimePath = Join-Path $root "src\CodexPetLimitRings.ps1"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $root "qa\runtime-pixel-potion-preview.png"
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors)
if ($errors) { throw "Runtime parser errors: $($errors -join '; ')" }

function Get-RuntimeFunctionText {
  param([string]$Name)
  $definition = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
  }, $true)
  if ($null -eq $definition) { throw "Runtime function not found: $Name" }
  return $definition.Extent.Text
}

foreach ($functionName in @(
  "New-Brush",
  "New-StyleBrush",
  "Format-Percent",
  "New-FrozenBitmapImage",
  "New-PixelPotionTextBlock",
  "New-PixelPotionVisual",
  "Set-PixelPotionVisual"
)) {
  Invoke-Expression (Get-RuntimeFunctionText $functionName)
}

$framePath = Join-Path $root "assets\runtime\potion-pixel-frame.png"
$maskPath = Join-Path $root "assets\runtime\potion-pixel-mask.png"
$script:PotionPixelFrameBitmap = New-FrozenBitmapImage -Path $framePath
$script:PotionPixelMaskBitmap = New-FrozenBitmapImage -Path $maskPath
$script:PotionPixelMaskBrush = [System.Windows.Media.ImageBrush]::new($script:PotionPixelMaskBitmap)
$script:PotionPixelMaskBrush.Stretch = [System.Windows.Media.Stretch]::Fill
$script:PotionPixelMaskBrush.Freeze()

$surface = [System.Windows.Controls.Canvas]::new()
$surface.Width = 329.0
$surface.Height = 178.0
$surface.Background = New-StyleBrush 255 @(39, 38, 37)
$surface.SnapsToDevicePixels = $true
$surface.UseLayoutRounding = $true

$leftPotion = New-PixelPotionVisual -Label "5H"
$rightPotion = New-PixelPotionVisual -Label "WK"
$surface.Children.Add($leftPotion.Container) | Out-Null
$surface.Children.Add($rightPotion.Container) | Out-Null

Set-PixelPotionVisual -Visual $leftPotion -Remaining 60 -LiquidBrush (New-StyleBrush 255 @(190, 48, 26)) -Scale 1.0 -Left 12.0 -Top 82.0
Set-PixelPotionVisual -Visual $rightPotion -Remaining 91 -LiquidBrush (New-StyleBrush 255 @(43, 139, 219)) -Scale 1.0 -Left 249.0 -Top 82.0

$surface.Measure([System.Windows.Size]::new(329.0, 178.0))
$surface.Arrange([System.Windows.Rect]::new(0.0, 0.0, 329.0, 178.0))
$surface.UpdateLayout()

$bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
  329,
  178,
  96.0,
  96.0,
  [System.Windows.Media.PixelFormats]::Pbgra32
)
$bitmap.Render($surface)
$encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
$stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
try {
  $encoder.Save($stream)
} finally {
  $stream.Dispose()
}

Write-Host "Rendered pixel potion preview: $OutputPath"
