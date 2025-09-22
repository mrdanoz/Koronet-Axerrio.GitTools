function Close-KXGTFeatureBranch {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [int] $FeatureBranchID,
        [ValidateSet('Open','InProgress','InReview','Merged','Closed','Abandoned')] [string] $Status = 'Closed',
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

    if ($PSCmdlet.ShouldProcess("Close FeatureBranchID $FeatureBranchID (Status=$Status)")) {
        $sql = "EXEC dba.usp_FeatureBranch_Close @FeatureBranchID=$FeatureBranchID, @Status=N'$Status', @ModifiedBy=N'$ModifiedBy';"
        Invoke-KXGTSql -ServerInstance $SqlInstance -Database $Database -Query $sql -SqlCredential $SqlCredential -AppName $AppName | Out-Null
    }
}

