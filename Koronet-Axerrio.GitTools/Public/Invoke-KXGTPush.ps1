function Invoke-KXGTPush {
<#
.SYNOPSIS
Pushes a branch to origin (optionally sets upstream).
#>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] [string] $BranchName,
        [string] $RepoPath,
        [switch] $SetUpstream
    )
    $cfg = Get-KXGTConfig
    if (-not $RepoPath -and $cfg -and $cfg.defaultRepoPath) { $RepoPath = $cfg.defaultRepoPath }

    if ($PSCmdlet.ShouldProcess("Push branch '$BranchName' to origin")) {
        if ($SetUpstream) { Invoke-KXGTGitCommand -Args @('push','-u','origin',$BranchName) -RepoPath $RepoPath }
        else              { Invoke-KXGTGitCommand -Args @('push','origin',$BranchName)      -RepoPath $RepoPath }
        Write-Host "Pushed $BranchName to origin"
    }
}

