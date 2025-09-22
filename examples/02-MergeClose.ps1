#requires -Version 7.4
param([Parameter(Mandatory)][int]$FeatureBranchID)

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

$cfg = Get-KXGTConfig
$cred = Get-Credential -UserName 'axe-dev' -Message 'Shared SQL login'

Merge-KXGTFeatureBranch -FeatureBranchID $FeatureBranchID `
    -SqlInstance $cfg.auditServer -Database $cfg.auditDatabase -SqlCredential $cred
