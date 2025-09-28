# Minimal interactive launcher for New-KXGTFeatureBranch (PowerShell 5.1 compatible)
$ErrorActionPreference = 'Stop'

# 0) Ensure module is available and import it
if (-not (Get-Module -ListAvailable Koronet-Axerrio.GitTools)) {
  Write-Error "Koronet-Axerrio.GitTools not found. Please install/run the bootstrap first."
  exit 1
}
Import-Module Koronet-Axerrio.GitTools -Force -ErrorAction Stop

# 1) Try to load config (non-fatal if unavailable)
$cfg = $null
try {
  $cfg = Get-KXGTConfig -ForceReload -Interactive -ErrorAction Stop
} catch {
  try { $cfg = Get-KXGTConfig -ErrorAction SilentlyContinue } catch { $cfg = $null }
}

# 2) Helpers
function Sanitize-BranchName {
  param([Parameter(Mandatory=$true)][string]$Name)
  $n = $Name.Trim()
  # replace invalid chars with '-', collapse repeats, trim ends
  $n = ($n -replace '[^\w\.\-\/]+','-') -replace '-{2,}','-'
  $n = $n.Trim('-')
  if ([string]::IsNullOrWhiteSpace($n)) { throw "Branch name becomes empty after sanitization." }
  return $n
}

# 3) UI (only essential prompts)
Write-Host ""
Write-Host "=== Start a Feature Branch ===" -ForegroundColor Cyan

$prefix = Read-Host "Prefix [feat]"
if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'feat' }

$short  = Read-Host "Short name (e.g. customer-filters)"
if ([string]::IsNullOrWhiteSpace($short)) { throw "Short name is required." }

# Base default from config if present, else 'dev'
$baseDefault = 'dev'
if ($cfg -and ($cfg.PSObject.Properties.Name -contains 'BaseBranch') -and $cfg.BaseBranch) {
  $baseDefault = [string]$cfg.BaseBranch
}
$base = Read-Host ("Base branch [{0}]" -f $baseDefault)
if ([string]::IsNullOrWhiteSpace($base)) { $base = $baseDefault }

# OwnerLoginName default -> current Windows user; override as needed
$ownerDefault = $env:USERNAME
if ($cfg -and ($cfg.PSObject.Properties.Name -contains 'OwnerLoginName') -and $cfg.OwnerLoginName) {
  $ownerDefault = [string]$cfg.OwnerLoginName
}
$owner = Read-Host ("OwnerLoginName [{0}]" -f $ownerDefault)
if ([string]::IsNullOrWhiteSpace($owner)) { $owner = $ownerDefault }

# Build final branch name
$branch = Sanitize-BranchName "$prefix/$short"

# 4) Prepare parameters (only Branch + Base + OwnerLoginName)
$cmd = Get-Command -Name New-KXGTFeatureBranch -ErrorAction Stop
$allowed = $cmd.Parameters.Keys
$params  = @{}

function Add-IfAllowed {
  param([string[]]$Names,[object]$Value)
  foreach ($n in $Names) {
    if ($Value -and ($allowed -contains $n)) { $params[$n] = $Value; return }
  }
}

# Map to the names your cmdlet actually exposes
Add-IfAllowed @('Branch','BranchName','Name') $branch
Add-IfAllowed @('BaseBranch','Base','From')   $base
Add-IfAllowed @('OwnerLoginName','LoginName','Owner','DeveloperLogin') $owner

# 5) Show exactly what will be passed
Write-Host ""
Write-Host "About to run:" -ForegroundColor Yellow
$preview = ($params.GetEnumerator() | ForEach-Object { '-{0} "{1}"' -f $_.Key, $_.Value }) -join ' '
Write-Host ("New-KXGTFeatureBranch {0}" -f $preview)

$ok = Read-Host "Proceed? (Y/N)"
if ($ok -ne 'Y' -and $ok -ne 'y') { Write-Host "Canceled."; exit 2 }

# 6) Execute
try {
  $result = New-KXGTFeatureBranch @params
  if ($result) { $result | Format-List * }
  Write-Host "Done." -ForegroundColor Green
  exit 0
} catch {
  Write-Error ("New-KXGTFeatureBranch failed: {0}" -f $_.Exception.Message)
  Write-Host "`nThe command accepts these parameters:" -ForegroundColor DarkYellow
  $allowed | Sort-Object | ForEach-Object { "  -$_" } | Write-Host
  exit 3
}
