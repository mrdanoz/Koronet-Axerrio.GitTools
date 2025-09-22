function Remove-KXGTFeatureBranchUser {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [int] $FeatureBranchID,
        [int] $DeveloperID,
        [string] $LoginName,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $RemovedBy = $env:USERNAME,
        [string] $AppName
    )

    $cfg = Get-KXGTConfig
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $AppName)     { $AppName     = Get-KXGTAppName }

    if (-not $DeveloperID -and -not $LoginName) { throw "Provide at least -DeveloperID or -LoginName." }

    $sql = @"
EXEC dba.usp_FeatureBranchUser_Close
    @FeatureBranchID = $FeatureBranchID,
    @DeveloperID     = $(if ($PSBoundParameters.ContainsKey('DeveloperID') -and $DeveloperID) { $DeveloperID } else { 'NULL' }),
    @LoginName       = $(if ($PSBoundParameters.ContainsKey('LoginName')   -and $LoginName)   { "N'$LoginName'" } else { 'NULL' }),
    @RemovedBy       = N'$RemovedBy';
"@

    if ($PSCmdlet.ShouldProcess("FeatureBranchID $FeatureBranchID → remove user (DeveloperID=$DeveloperID, LoginName='$LoginName')")) {
        Invoke-KXGTSql -ServerInstance $SqlInstance -Database $Database -Query $sql -SqlCredential $SqlCredential -AppName $AppName | Out-Null
    }
}

