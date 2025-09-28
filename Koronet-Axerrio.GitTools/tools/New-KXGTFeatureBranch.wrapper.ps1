# Interactive launcher for New-KXGTFeatureBranch
$ErrorActionPreference = 'Stop'

# 0) Sanity: module installed?
if (-not (Get-Module -ListAvailable Koronet-Axerrio.GitTools)) {
  Write-Error "Koronet-Axerrio.GitTools not found. Run your installer/bootstrap first."
  exit 1
}

# 1) Import the module
Import-Module Koronet-Axerrio.GitTools -Force -ErrorAction Stop

# 2) Load config (prompt-friendly if your function supports it)
$cfg = $null
try {
  $cfg = Get-KXGTConfig -ForceReload -Interactive -ErrorAction Stop
} catch {
  $cfg = Get-KXGTConfig -ErrorAction SilentlyContinue
}

# 3) Helpers
function Sanitize-BranchName {
  param([Parameter(Mandatory)][string]$Name)
  $n = $Name.Trim()
  # Replace spaces & invalid chars with dashes; collapse repeats; trim dashes
  $n = $n -replace '[^\w\.\-\/]+','-'
  $n = $n -replace '-{2,}','-'
  $n = $n.Trim('-')
  # Guard against empty or only separators
  if ([string]::IsNullOrWhiteSpace($n)) { throw "Branch name becomes empty after sanitization." }
  return $n
}

function Choose-Prefix {
  $choices = @('feat','fix','chore','docs','refactor','test')
  Write-Host ""
  Write-Host "Prefix options: " -NoNewline
  Write-Host ($choices -join ' | ') -ForegroundColor Cyan
  $p = Read-Host "Prefix [feat]"
  if ([string]::IsNullOrWhiteSpace($p)) { $p = 'feat' }
  return $p
}

# 4) UI
Write-Host ""
Write-Host "=== Start a Feature Branch ===" -ForegroundColor Cyan

$prefix = Choose-Prefix
$short  = Read-Host "Short name (e.g. customer-filters)"
if ([string]::IsNullOrWhiteSpace($short)) { throw "A branch short name is required." }

$baseDefault = if ($cfg -and $cfg.PSObject.Properties.Name -contains 'BaseBranch' -and $cfg.BaseBranch) { $cfg.BaseBranch } else { 'dev' }
$base = Read-Host "Base branch [$baseDefault]"
if ([string]::IsNullOrWhiteSpace($base)) { $base = $baseDefault }

$tick = Read-Host "Ticket/Work item (optional)"
$titl = Read-Host "Title (optional)"

# Build final branch name
$rawBranch = "$prefix/$short"
$branch = Sanitize-BranchName $rawBranch

Write-Host ""
Write-Host "About to create branch:" -ForegroundColor Yellow
Write-Host ("  Branch : {0}" -f $branch)
Write-Host ("  Base   : {0}" -f $base)
if ($tick) { Write-Host ("  Ticket : {0}" -f $tick) }
if ($titl) { Write-Host ("  Title  : {0}" -f $titl) }

$ok = Read-Host "Proceed? (Y/N)"
if ($ok -notin @('Y','y')) { Write-Host "Canceled."; exit 2 }

# 5) Build parameters supported by the cmdlet
$cmd = Get-Command -Name New-KXGTFeatureBranch -ErrorAction Stop
$allowed = $cmd.Parameters.Keys
$params  = @{}

# Candidate values (only pass those the cmdlet actually supports)
$trySet = {
  param($name,$value)
  if ($value -and ($allowed -contains $name)) { $params[$name] = $value }
}

& $trySet 'Branch'        $branch
& $trySet 'BranchName'    $branch
& $trySet 'Name'          $branch
& $trySet 'Base'          $base
& $trySet 'BaseBranch'    $base
& $trySet 'From'          $base
& $trySet 'Ticket'        $tick
& $trySet 'WorkItem'      $tick
& $trySet 'Title'         $titl

# From config (if your cmdlet supports them)
if ($cfg) {
  & $trySet 'RepoPath'       $cfg.RepoPath
  & $trySet 'GitHandle'      $cfg.GitHandle
  & $trySet 'ServerInstance' $cfg.ServerInstance
  & $trySet 'Database'       $cfg.Database
}

# 6) Execute
try {
  Write-Host ""
  Write-Host "Running: New-KXGTFeatureBranch $($params.Keys | ForEach-Object { '-' + $_ } -join ' ')" -ForegroundColor Green
  $result = New-KXGTFeatureBranch @params
  if ($result) {
    Write-Host ""
    $result | Format-List *  # show any returned info
  }
  Write-Host "Done." -ForegroundColor Green
} catch {
  Write-Error "New-KXGTFeatureBranch failed: $($_.Exception.Message)"
  Write-Host "`nThe command accepts these parameters:" -ForegroundColor DarkYellow
  ($allowed | Sort-Object) | ForEach-Object { "  -$_" } | Write-Host
  exit 3
}
