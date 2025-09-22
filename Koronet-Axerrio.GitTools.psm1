# Koronet-Axerrio.GitTools.psm1 — loader (exports only 3 public commands)

Set-StrictMode -Version Latest

# Soft hint: SqlServer module is handy but not required to import
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
  Write-Verbose "[KXGT] Tip: Install-Module SqlServer -Scope CurrentUser"
}

# 1) Dot-source Private first
$privateDir = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privateDir) {
  Get-ChildItem -Path $privateDir -Filter *.ps1 -File | ForEach-Object { . $_.FullName }
}

# 2) Dot-source Public next
$publicDir = Join-Path $PSScriptRoot 'Public'
$publicFiles = @()
if (Test-Path $publicDir) {
  $publicFiles = Get-ChildItem -Path $publicDir -Filter *.ps1 -File
  foreach ($f in $publicFiles) { . $f.FullName }
}

# 3) Determine which functions came from the Public folder (robust; not relying on filenames)
$publicFuncInfos = Get-ChildItem function:\ | Where-Object {
  $_.ScriptBlock -and $_.ScriptBlock.File -and (
    (Split-Path $_.ScriptBlock.File -Parent) -like ($publicDir + '*')
  )
}

$haveNames = $publicFuncInfos.Name

# We only want these three to be public:
$wantNames = @('New-KXGTFeatureBranch','New-KXGTPullRequest','Complete-KXGTPullRequest')

# Export the intersection (and nothing else)
$exportNames = $wantNames | Where-Object { $haveNames -contains $_ }

Export-ModuleMember -Function $exportNames
