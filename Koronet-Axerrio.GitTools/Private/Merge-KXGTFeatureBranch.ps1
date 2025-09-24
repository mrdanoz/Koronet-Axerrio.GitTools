function Merge-KXGTFeatureBranch {
<#
.SYNOPSIS
Marks a feature branch as Merged in DB and closes the record.
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [int] $FeatureBranchID,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $ModifiedBy = $env:USERNAME,
        [string] $AppName
    )
    $cfg = Get-KXGTConfig
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $AppName)     { $AppName     = Get-KXGTAppName }

    Set-KXGTFeatureBranchStatus -FeatureBranchID $FeatureBranchID -Status Merged -SqlInstance $SqlInstance -Database $Database -SqlCredential $SqlCredential -AppName $AppName -WhatIf:$false
    Close-KXGTFeatureBranch     -FeatureBranchID $FeatureBranchID -Status Merged -SqlInstance $SqlInstance -Database $Database -SqlCredential $SqlCredential -AppName $AppName -WhatIf:$false
}

