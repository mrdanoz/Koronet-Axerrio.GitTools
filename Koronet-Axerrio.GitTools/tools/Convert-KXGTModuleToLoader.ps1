<# 
.SYNOPSIS
  Convert monolithic module to loader pattern with Public/Private folders.

.DESCRIPTION
  - Backs up the existing .psm1
  - Extracts all function definitions from the .psm1 using the PowerShell AST
  - Writes each function to Public\<FunctionName>.ps1 or Private\<FunctionName>.ps1
  - Generates a loader .psm1 that dot-sources Private then Public files and exports Public functions
  - Creates Public\_Aliases.ps1 with Invoke-KXGTGetConfig -> Get-KXGTConfig
  - Optionally normalizes FunctionsToExport/AliasesToExport in the .psd1

.PARAMETER ModuleRoot
  Path to the module root (folder that contains the .psm1/.psd1). Defaults to CWD.

.PARAMETER Force
  Overwrite existing destination files.

.PARAMETER DryRun
  Show what would happen without writing files.

.NOTES
  - PowerShell 7+
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string] $ModuleRoot = (Get-Location).Path,
  [switch] $Force,
  [switch] $DryRun
)

Set-StrictMode -Version Latest

# --- Locate module files
$psm1 = Get-ChildItem -LiteralPath $ModuleRoot -Filter *.psm1 -File | Select-Object -First 1
if (-not $psm1) { throw "No .psm1 found in '$ModuleRoot'." }

$psd1 = Get-ChildItem -LiteralPath $ModuleRoot -Filter *.psd1 -File | Select-Object -First 1
$publicDir  = Join-Path $ModuleRoot 'Public'
$privateDir = Join-Path $ModuleRoot 'Private'

# --- Create folders
foreach ($dir in @($publicDir,$privateDir)) {
  if (-not (Test-Path $dir)) {
    if ($PSCmdlet.ShouldProcess($dir, "Create directory")) {
      if (-not $DryRun) { New-Item -ItemType Directory -Path $dir | Out-Null }
    }
  }
}

# --- Backup original .psm1
$backup = Join-Path $ModuleRoot ("{0}.bak.{1}.psm1" -f [IO.Path]::GetFileNameWithoutExtension($psm1.Name),(Get-Date -Format 'yyyyMMddHHmmss'))
if ($PSCmdlet.ShouldProcess($psm1.FullName, "Backup to $backup")) {
  if (-not $DryRun) { Copy-Item -LiteralPath $psm1.FullName -Destination $backup -Force }
}

# --- Parse functions from .psm1 using AST
$null = [System.Reflection.Assembly]::LoadWithPartialName('System.Management.Automation') | Out-Null
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($psm1.FullName, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
  Write-Warning "Parser reported $($errors.Count) error(s); continuing anyway."
}

$funcAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
if (-not $funcAsts -or $funcAsts.Count -eq 0) {
  throw "No function definitions found in '$($psm1.Name)'."
}

# --- Classify functions as Public vs Private
$explicitPrivate = @(
  'Get-KXGTObjectFilePath',
  'Test-KXGTExe',
  'Write-KXGTObjectToFile'
)

$written = @()

foreach ($f in $funcAsts) {
  $name = $f.Name
  $text = $f.Extent.Text.Trim() + [Environment]::NewLine

  $isPrivate = $explicitPrivate -contains $name
  # If not explicitly private, default to Public
  $targetDir = if ($isPrivate) { $privateDir } else { $publicDir }
  $outPath = Join-Path $targetDir ("{0}.ps1" -f $name)

  if ((Test-Path $outPath) -and -not $Force) {
    Write-Verbose ("Skip (exists): {0}" -f $outPath)
    continue
  }

  if ($PSCmdlet.ShouldProcess($outPath, "Write function $name")) {
    if (-not $DryRun) { $text | Out-File -FilePath $outPath -Encoding UTF8 }
    $written += $outPath
  }
}

# --- Public/_Aliases.ps1 (always safe to (re)write)
$aliasesPath = Join-Path $publicDir '_Aliases.ps1'
$aliasesBody = @'
# Aliases for Koronet-Axerrio.GitTools
Set-Alias -Name Invoke-KXGTGetConfig -Value Get-KXGTConfig -Scope Local
'@.Trim() + [Environment]::NewLine

if ($PSCmdlet.ShouldProcess($aliasesPath, "Write alias file")) {
  if (-not $DryRun) { $aliasesBody | Out-File -FilePath $aliasesPath -Encoding UTF8 -Force }
}

# --- Generate loader .psm1
$loader = @"
# $(Split-Path -Leaf $psm1.FullName) — loader

Set-StrictMode -Version Latest

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
  Write-Verbose "[KXGT] SqlServer module not found; install with: Install-Module SqlServer -Scope CurrentUser"
}

# 1) Private
`$privateDir = Join-Path `$PSScriptRoot 'Private'
if (Test-Path `$privateDir) {
  Get-ChildItem -Path `$privateDir -Filter *.ps1 -File | ForEach-Object { . `$_.FullName }
}

# 2) Public
`$publicDir = Join-Path `$PSScriptRoot 'Public'
`$publicFiles = @()
if (Test-Path `$publicDir) {
  `$publicFiles = Get-ChildItem -Path `$publicDir -Filter *.ps1 -File
  foreach (`$f in `$publicFiles) { . `$f.FullName }
}

# 3) Export (skip _Aliases.ps1)
`$funcs = `$publicFiles.BaseName | Where-Object { `$_ -ne '_Aliases' }
Export-ModuleMember -Function `$funcs -Alias *
"@.Trim() + [Environment]::NewLine

if ($PSCmdlet.ShouldProcess($psm1.FullName, "Replace with loader")) {
  if (-not $DryRun) { $loader | Out-File -FilePath $psm1.FullName -Encoding UTF8 -Force }
}

# --- (Optional) normalize FunctionsToExport/AliasesToExport in .psd1
if ($psd1) {
  $psd1Text = Get-Content -LiteralPath $psd1.FullName -Raw
  $psd1Text2 = $psd1Text
  # Set FunctionsToExport/AliasesToExport to blank arrays so psm1 controls export
  $psd1Text2 = [regex]::Replace($psd1Text2, 'FunctionsToExport\\s*=\\s*[^\\r\\n]+', 'FunctionsToExport = @()')
  $psd1Text2 = [regex]::Replace($psd1Text2, 'AliasesToExport\\s*=\\s*[^\\r\\n]+',   'AliasesToExport   = @()')

  if ($psd1Text2 -ne $psd1Text) {
    if ($PSCmdlet.ShouldProcess($psd1.FullName, "Normalize Functions/Aliases export lists")) {
      if (-not $DryRun) { $psd1Text2 | Out-File -FilePath $psd1.FullName -Encoding UTF8 -Force }
    }
  }
}

# --- Done
"`nConverted '$($psm1.Name)'. Created/updated: $($written.Count) function file(s)."
