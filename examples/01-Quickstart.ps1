#requires -Version 7.4
param(
  [string]$BranchName   = 'feature/ABI-999',
  [string]$TargetBranch = $null
)

# Friendly runtime check
$min = [Version]'7.4.0'
try { $cur = $PSVersionTable.PSVersion } catch { $cur = $null }
if (-not $cur -or $cur -lt $min) {
    $msg = @"
Koronet-Axerrio.GitTools requires PowerShell $($min) or higher.
Current version: $($cur)

Please install the latest PowerShell 7.x from:
https://github.com/PowerShell/PowerShell/releases
"@
    throw $msg
}

$modulePath = Join-Path $PSScriptRoot '..\Koronet-Axerrio.GitTools.psm1'
Import-Module $modulePath -Force

$cred = Get-Credential -UserName 'axe-dev' -Message 'Shared SQL login'

$cfg = Get-KXGTConfig
if (-not $TargetBranch) {
    if ($cfg.defaultBaseBranch) { $TargetBranch = $cfg.defaultBaseBranch }
    else { $TargetBranch = 'develop' }
}

# 1) Create branch and log to DB (DB logging is always on)
$r = New-KXGTFeatureBranch -BranchName $BranchName `
     -SqlInstance $cfg.auditServer -Database $cfg.auditDatabase -SqlCredential $cred
$r | Format-List

# 2) Push to origin
Invoke-KXGTPush -BranchName $BranchName -SetUpstream

# 3) Open PR and set DB status to InReview
New-KXGTPullRequest -BranchName $BranchName -TargetBranch $TargetBranch -FeatureBranchID $r.FeatureBranchId `
    -SqlInstance $cfg.auditServer -Database $cfg.auditDatabase -SqlCredential $cred
