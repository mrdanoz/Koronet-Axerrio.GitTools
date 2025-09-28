# --- Settings ---
$modName = 'Koronet-Axerrio.GitTools'

# 1) Discover all module roots PS7 uses (and common OneDrive paths)
$roots = @(
  "$HOME\Documents\PowerShell\Modules",
  "$HOME\Documents\WindowsPowerShell\Modules",
  "$env:OneDrive\Documents\PowerShell\Modules",
  "$env:OneDrive\Documents\WindowsPowerShell\Modules",
  "$env:OneDrive\Documenten\PowerShell\Modules",          # Dutch OneDrive
  "$env:OneDrive\Documenten\WindowsPowerShell\Modules"    # Dutch OneDrive (WSH)
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

# 2) Find every installed copy of the module
$instances = foreach ($r in $roots) {
  $p = Join-Path $r $modName
  if (Test-Path $p) { Get-Item $p }
}

$dest = "$HOME\Documents\PowerShell\Modules\$modName"


# Ensure destination parent exists
$destParent = Split-Path $dest
if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }

# 4) If destination missing, copy from the newest instance; then remove all others
if (-not (Test-Path $dest)) {
  $source = $instances | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $source) { throw "No existing $modName found in known paths." }
  Write-Host "Copying from '$($source.FullName)' to '$dest' ..." -ForegroundColor Cyan
  Copy-Item $source.FullName $destParent -Recurse -Force
}

# Remove duplicates elsewhere
foreach ($i in $instances) {
  if ($i.FullName -ne $dest) {
    Write-Host "Removing duplicate: $($i.FullName)" -ForegroundColor Yellow
    Remove-Item $i.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# 5) Make sure PS7 actually searches the chosen parent first
$userModules = $destParent
$paths = $env:PSModulePath -split ';'
if ($paths -notcontains $userModules) {
  $env:PSModulePath = "$userModules;$env:PSModulePath"
}
# Persist this for future PS7 sessions + autoload module on demand
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
$line = 'if (($env:PSModulePath -split '';'') -notcontains "$HOME\Documents\PowerShell\Modules" -and (Test-Path "$HOME\Documents\PowerShell\Modules")) { $env:PSModulePath = "$HOME\Documents\PowerShell\Modules;$env:PSModulePath" }'
$lineOneDriveDoc = 'if (($env:PSModulePath -split '';'') -notcontains "$env:OneDrive\Documenten\PowerShell\Modules" -and (Test-Path "$env:OneDrive\Documenten\PowerShell\Modules")) { $env:PSModulePath = "$env:OneDrive\Documenten\PowerShell\Modules;$env:PSModulePath" }'
$lineOneDriveEn  = 'if (($env:PSModulePath -split '';'') -notcontains "$env:OneDrive\Documents\PowerShell\Modules" -and (Test-Path "$env:OneDrive\Documents\PowerShell\Modules")) { $env:PSModulePath = "$env:OneDrive\Documents\PowerShell\Modules;$env:PSModulePath" }'
foreach ($l in @($line,$lineOneDriveDoc,$lineOneDriveEn)) {
  if (-not (Select-String -Path $PROFILE -SimpleMatch $l -ErrorAction SilentlyContinue)) { Add-Content $PROFILE $l }
}

# 6) Unblock files and import
Get-ChildItem $dest -Recurse | Unblock-File -ErrorAction SilentlyContinue
$psd1 = Get-ChildItem -Path $dest -Filter "$modName.psd1" -Recurse | Select-Object -First 1
if (-not $psd1) { throw "Manifest not found under '$dest'." }
Import-Module $psd1.FullName -Force -Verbose

# 7) Verify
Get-Module $modName -ListAvailable | Select Name,Version,ModuleBase
Get-Command -Module $modName
