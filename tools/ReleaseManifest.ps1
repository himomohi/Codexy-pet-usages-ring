$script:CodexPetReleaseItems = @(
  "Install.bat",
  "Start.bat",
  "Stop.bat",
  "Status.bat",
  "Settings.bat",
  "Uninstall.bat",
  "bin",
  "src",
  "assets",
  "docs",
  "tools",
  "settings",
  "settings.defaults.json",
  "README.md",
  "README.ko.md",
  "README.ja.md",
  "README.zh.md",
  "LICENSE",
  "NOTICE.md",
  "CHANGELOG.md",
  "SECURITY.md",
  "VERSION"
)

$script:CodexPetRequiredFreshFiles = @(
  "settings/index.html",
  "assets/runtime/reward-chest.png",
  "assets/runtime/inventory-snack.png",
  "assets/runtime/inventory-gem.png",
  "assets/runtime/inventory-ticket.png",
  "assets/runtime/inventory-patch.png",
  "assets/runtime/unlock-font-pixel.png",
  "assets/runtime/unlock-font-terminal.png",
  "assets/runtime/unlock-theme-arcane.png",
  "assets/runtime/unlock-theme-royal.png",
  "assets/runtime/theme-forest-border.png",
  "assets/runtime/theme-arcane-border.png",
  "assets/runtime/theme-royal-border.png",
  "assets/runtime/theme-cyber-border.png",
  "assets/runtime/theme-celestial-border.png",
  "settings.defaults.json",
  "bin/powershell/Settings.ps1",
  "src/CodexyPetUsagesRing.ps1",
  "README.md",
  "README.ko.md",
  "README.ja.md",
  "README.zh.md",
  "CHANGELOG.md",
  "VERSION"
)

function Test-CodexPetReleasePathExcluded {
  param([string]$RelativePath)
  $normalized = ($RelativePath -replace '\\', '/').TrimStart("/")
  $leaf = Split-Path -Leaf $normalized
  if ($normalized -in @(
    ".gitignore",
    "gamification.json",
    "settings.json",
    "assets/runtime/inventory-items-source.png",
    "assets/runtime/cosmetic-unlocks-source.png",
    "assets/runtime/theme-forest-border-source.png",
    "assets/runtime/theme-arcane-border-source.png",
    "assets/runtime/theme-royal-border-source.png",
    "assets/runtime/theme-cyber-border-source.png",
    "assets/runtime/theme-celestial-border-source.png",
    "docs/assets/current-pet-usage-capture.png",
    "docs/assets/imagegen-hero-background.png"
  )) { return $true }
  if ($normalized -like "dist/*" -or $normalized -eq "dist") { return $true }
  if ($normalized -like "logs/*" -or $normalized -eq "logs") { return $true }
  if ($normalized -like "qa/*" -or $normalized -eq "qa") { return $true }
  if ($normalized -like "*.log" -or $normalized -like "*.tmp" -or $normalized -like "*.bak" -or $normalized -like "*.zip") { return $true }
  if ($leaf -eq ".DS_Store" -or $leaf -eq "Thumbs.db") { return $true }
  return $false
}
