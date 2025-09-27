param([switch]$RemoveConfig)

$ErrorActionPreference = 'Stop'
$moduleName = 'Koronet-Axerrio.GitTools'
Write-Host "=== Cleaning $moduleName ===" -ForegroundColor Cyan

# 1) Unload from session (both PS 5.1 and PS 7)
$loaded = Get-Module $moduleName
if ($loaded) {
  Write-Host "Unloading module from memory..."
  Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
}

# 2) Candidate roots (NO Join-Path; plain strings)
$roots = @()
if ($env:ProgramFiles) { 
  $roots += "$env:ProgramFiles\WindowsPowerShell\Modules"
  $roots += "$env:ProgramFiles\PowerShell\Modules"
}
if ($env:USERPROFILE) {
  $roots += "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
  $roots += "$env:USERPROFILE\Documents\PowerShell\Modules"
}

# Keep only existing, unique
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

Write-Host "Scanning roots:" -ForegroundColor DarkCyan
$roots | ForEach-Object { Write-Host "  $_" }

# 3) Remove module folders
$targets = foreach ($r in $roots) {
  $p = "$r\$moduleName"
  if (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
}

if (-not $targets) {
  Write-Host "No existing module folders found." -ForegroundColor Yellow
} else {
  foreach ($t in $targets) {
    Write-Host "Removing: $($t.FullName)" -ForegroundColor Red
    try {
      if (($t.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Host "  (Symlink/junction detected; removing link)"
        Remove-Item -LiteralPath $t.FullName -Force
      } else {
        Remove-Item -LiteralPath $t.FullName -Recurse -Force
      }
    } catch {
      Write-Warning "Failed to remove $($t.FullName): $_"
    }
  }
}

# 4) Optional: remove local config (adjust if your module uses another path)
if ($RemoveConfig) {
  $cfgs = @(
    "$env:APPDATA\Koronet-Axerrio.GitTools\Config.json",
    "$env:LOCALAPPDATA\Koronet-Axerrio.GitTools\Config.json"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($c in $cfgs) {
    try {
      Write-Host "Removing config: $c"
      Remove-Item -LiteralPath $c -Force
    } catch {
	Write-Warning ("Failed to remove config {0}: {1}" -f $c, $_)
    }
  }
}
$mod = 'Koronet-Axerrio.GitTools'

# Search every module path PowerShell actually uses (covers OneDrive redirects)
$paths = ($env:PSModulePath -split ';') |
         Where-Object { $_ -and (Test-Path $_) } |
         Select-Object -Unique

foreach ($root in $paths) {
  $p = Join-Path $root $mod
  if (Test-Path -LiteralPath $p) {
    try {
      $item = Get-Item -LiteralPath $p
      Write-Host "Removing: $($item.FullName)"
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $item.FullName -Force
      } else {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
      }
    } catch {
      Write-Warning ("Failed to remove {0}: {1}" -f $p, $_)
    }
  }
}

# Bonus: common OneDrive fallbacks (personal & business)
$extra = @(
  "$env:OneDrive\Documents\WindowsPowerShell\Modules\$mod",
  "$env:OneDrive\Documents\PowerShell\Modules\$mod",
  "$env:OneDriveCommercial\Documents\WindowsPowerShell\Modules\$mod",
  "$env:OneDriveCommercial\Documents\PowerShell\Modules\$mod"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

foreach ($p in $extra) {
  try {
    Write-Host "Removing: $p"
    $it = Get-Item -LiteralPath $p
    if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      Remove-Item -LiteralPath $p -Force
    } else {
      Remove-Item -LiteralPath $p -Recurse -Force
    }
  } catch {
    Write-Warning ("Failed to remove {0}: {1}" -f $p, $_)
  }
}

# Verify
$still = Get-Module -ListAvailable $mod
if ($still) { $still | Select Name,Version,ModuleBase | Format-Table -Auto }
else { Write-Host "All versions removed." -ForegroundColor Green }

# 5) Verify
$still = Get-Module -ListAvailable $moduleName
if (-not $still) {
  Write-Host "`nAll versions removed successfully." -ForegroundColor Green
} else {
  Write-Warning "Some instances still detected:"
  $still | Select-Object Name, Version, ModuleBase | Format-Table -AutoSize
}

Write-Host "`nCleanup complete."
