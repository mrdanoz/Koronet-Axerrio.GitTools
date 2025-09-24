function New-KXGTFeatureBranch {
<#
.SYNOPSIS
Creates a new git feature branch and logs it in the DB (status 'Open').
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [string] $BranchName,
        [string] $BaseBranch = 'develop',
        [string] $RepoPath,
        [switch] $Checkout,
        # DB
        [switch] $EnableDbLogging,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [int] $OwnerDeveloperID,
        [string] $OwnerLoginName,
        [string] $OwnerGitHandle,
        [string] $CreatedBy = $env:USERNAME,
        [string] $AppName
    )

    $cfg = Get-KXGTConfig
    if (-not $RepoPath -and $cfg -and $cfg.defaultRepoPath) { $RepoPath = $cfg.defaultRepoPath }
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $EnableDbLogging.IsPresent -and $cfg -and $cfg.enableDbLogging) { $EnableDbLogging = $true }
    if (-not $AppName) { $AppName = Get-KXGTAppName -LoginName ($OwnerLoginName ?? $env:USERNAME) }

    # Resolve owner and repo path
    if (-not $OwnerDeveloperID -or -not $RepoPath) {
        $dev = $null
        try { $dev = Resolve-KXGTDeveloper -LoginName $OwnerLoginName -GitHandle $OwnerGitHandle -SqlInstance $SqlInstance -Database $Database -SqlCredential $SqlCredential -AppName $AppName } catch {}
        if (-not $OwnerDeveloperID -and $dev -and $dev.DeveloperID) { $OwnerDeveloperID = [int]$dev.DeveloperID }
        if (-not $RepoPath -and $dev -and $dev.RepoPath) { $RepoPath = $dev.RepoPath }
    }

    if ($PSCmdlet.ShouldProcess("Create branch '$BranchName' from '$BaseBranch' in repo '$RepoPath'")) {
        Invoke-KXGTGitCommand -Args @('fetch','--all')            -RepoPath $RepoPath
        Invoke-KXGTGitCommand -Args @('checkout', $BaseBranch)    -RepoPath $RepoPath
        Invoke-KXGTGitCommand -Args @('pull','origin',$BaseBranch) -RepoPath $RepoPath
        Invoke-KXGTGitCommand -Args @('checkout','-b',$BranchName) -RepoPath $RepoPath
        if (-not $Checkout) { Invoke-KXGTGitCommand -Args @('checkout',$BaseBranch) -RepoPath $RepoPath }

        $featureBranchId = $null
        if ($EnableDbLogging) {
            if (-not $SqlInstance -or -not $Database) {
                Write-Warning "DB logging enabled, but SqlInstance/Database not provided."
            } else {
                $sql = @"
DECLARE @FeatureBranchID int;
EXEC dba.usp_FeatureBranch_Open
    @BranchName       = N'$BranchName',
    @OwnerDeveloperID = $(if ($OwnerDeveloperID) { $OwnerDeveloperID } else { 'NULL' }),
    @Status           = N'Open',
    @CreatedBy        = N'$CreatedBy',
    @FeatureBranchID  = @FeatureBranchID OUTPUT;
SELECT FeatureBranchID = @FeatureBranchID;
"@
                try {
                    $res = Invoke-KXGTSql -ServerInstance $SqlInstance -Database $Database -Query $sql -SqlCredential $SqlCredential -AppName $AppName
                    if ($res -and $res[0].FeatureBranchID) { $featureBranchId = [int]$res[0].FeatureBranchID }
                } catch {
                    Write-Warning "Failed to log FeatureBranch Open: $($_.Exception.Message)"
                }
            }
        }

        return [pscustomobject]@{
            Branch          = $BranchName
            Base            = $BaseBranch
            RepoPath        = $RepoPath
            CreatedAt       = (Get-Date).ToString('s')
            OwnerDeveloperID= $OwnerDeveloperID
            FeatureBranchId = $featureBranchId
            DbLogged        = [bool]$EnableDbLogging
            AppName         = $AppName
        }
    }
}

