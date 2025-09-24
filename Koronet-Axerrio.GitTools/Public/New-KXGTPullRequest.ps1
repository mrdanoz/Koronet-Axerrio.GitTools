function New-KXGTPullRequest {
<#
.SYNOPSIS
Creates a pull request (via GitHub CLI if available) and sets DB status to 'InReview'.
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [string] $BranchName,
        [string] $Title,
        [string] $Body,
        [string] $RepoPath,
        [string] $TargetBranch = 'develop',
        [int] $FeatureBranchID,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $AppName
    )
    $cfg = Get-KXGTConfig
    if (-not $RepoPath -and $cfg -and $cfg.defaultRepoPath) { $RepoPath = $cfg.defaultRepoPath }
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $AppName)     { $AppName     = Get-KXGTAppName }

    if ($PSCmdlet.ShouldProcess("Create PR for '$BranchName' -> '$TargetBranch'")) {
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            $prArgs = @('pr','create','--base',$TargetBranch,'--head',$BranchName)
            if ($Title) { $prArgs += @('--title',$Title) }
            if ($Body)  { $prArgs += @('--body',$Body) }
            Invoke-Expression ("gh " + ($prArgs -join ' '))
            Write-Host "PR created with gh"
        } else {
            try {
                $remote = Invoke-KXGTGitCommand -Args @('remote','get-url','origin') -RepoPath $RepoPath
                $url = $remote.StdOut.Trim()
                if ($url -match 'git@([^:]+):(.+)\.git') {
                    $githost = $matches[1]; $path = $matches[2]
                    $prUrl = "https://$githost/$path/pull/new/$BranchName"
                    Start-Process $prUrl
                    Write-Host "Opened browser to create PR: $prUrl"
                } else {
                    Write-Warning "Unsupported remote URL format for PR fallback: $url"
                }
            } catch { Write-Warning "Could not open PR automatically: $($_.Exception.Message)" }
        }

        if ($FeatureBranchID) {
            try {
                Set-KXGTFeatureBranchStatus -FeatureBranchID $FeatureBranchID -Status InReview -SqlInstance $SqlInstance -Database $Database -SqlCredential $SqlCredential -AppName $AppName -WhatIf:$false
            } catch { Write-Warning "Failed to set status InReview: $($_.Exception.Message)" }
        }
    }
}

