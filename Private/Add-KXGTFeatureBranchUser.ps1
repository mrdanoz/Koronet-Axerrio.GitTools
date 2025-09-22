function Add-KXGTFeatureBranchUser {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [int] $FeatureBranchID,
        [int] $DeveloperID,
        [string] $LoginName,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $AddedBy = $env:USERNAME,
        [string] $AppName
    )

    $cfg = Get-KXGTConfig
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $AppName)     { $AppName     = Get-KXGTAppName }

    if (-not $DeveloperID -and $LoginName) {
        $dev = Resolve-KXGTDeveloper -LoginName $LoginName -SqlInstance $SqlInstance -Database $Database -SqlCredential $SqlCredential -AppName $AppName
        if ($dev -and $dev.DeveloperID) { $DeveloperID = [int]$dev.DeveloperID }
    }

    if (-not $DeveloperID -and -not $LoginName) { throw "Provide at least -DeveloperID or -LoginName." }

    $sql = @"
EXEC dba.usp_FeatureBranchUser_Open
    @FeatureBranchID = $FeatureBranchID,
    @DeveloperID     = $(if ($PSBoundParameters.ContainsKey('DeveloperID') -and $DeveloperID) { $DeveloperID } else { 'NULL' }),
    @LoginName       = $(if ($PSBoundParameters.ContainsKey('LoginName')   -and $LoginName)   { "N'$LoginName'" } else { 'NULL' }),
    @AddedBy         = N'$AddedBy';
"@

    if ($PSCmdlet.ShouldProcess("FeatureBranchID $FeatureBranchID → add user (DeveloperID=$DeveloperID, LoginName='$LoginName')")) {
        Invoke-KXGTSql -ServerInstance $SqlInstance -Database $Database -Query $sql -SqlCredential $SqlCredential -AppName $AppName | Out-Null
    }
}

