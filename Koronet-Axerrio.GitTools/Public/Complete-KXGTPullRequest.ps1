function Complete-KXGTPullRequest {
  <#
  .SYNOPSIS
    Complete (merge) the pull request for a given branch (GitHub or Azure DevOps).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Branch,
    [ValidateSet('Auto','GitHub','AzureDevOps')] [string] $Provider = 'Auto',
    [ValidateSet('merge','squash','rebase')] [string] $Method = 'merge',
    [switch] $AutoWhenBlocked,
    [string] $RepoPath
  )

  if (-not (Get-Command Get-KXGTConfig -ErrorAction SilentlyContinue)) { throw "Get-KXGTConfig not found." }
  $cfg = Get-KXGTConfig
  if (-not $RepoPath) { $RepoPath = $cfg.RepoPath }
  if (-not (Test-Path $RepoPath)) { throw ("RepoPath '{0}' does not exist." -f $RepoPath) }

  function Test-KXGTExe { param([Parameter(Mandatory)][string]$Name) $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }

  $providerResolved = switch ($Provider) {
    'GitHub'      { 'GitHub' }
    'AzureDevOps' { 'AzureDevOps' }
    default {
      if (Test-KXGTExe -Name 'gh') { 'GitHub' }
      elseif (Test-KXGTExe -Name 'az') { 'AzureDevOps' } else { 'GitHub' }
    }
  }

  switch ($providerResolved) {
    'GitHub' {
      if (-not (Test-KXGTExe -Name 'gh')) { throw "GitHub CLI (gh) not found." }
      Push-Location $RepoPath
      try {
        $prNum = & gh pr view $Branch --json number --jq '.number'
        if ([string]::IsNullOrWhiteSpace($prNum)) { throw ("No PR found for branch '{0}'." -f $Branch) }
        $args = @('pr','merge',$Branch)
        switch ($Method) { 'merge' { $args += '--merge' } 'squash' { $args += '--squash' } 'rebase' { $args += '--rebase' } }
        if ($AutoWhenBlocked) { $args += '--auto' }
        & gh @args
        if ($LASTEXITCODE -ne 0) { throw "gh pr merge failed." }
      } finally { Pop-Location }
    }
    'AzureDevOps' {
      if (-not (Test-KXGTExe -Name 'az')) { throw "Azure DevOps CLI (az) not found." }
      $list = & az repos pr list --status active --source-branch $Branch --output json | ConvertFrom-Json
      if (-not $list -or $list.Count -eq 0) { throw ("No active PR found for branch '{0}'." -f $Branch) }
      $id = $list[0].pullRequestId
      if ($AutoWhenBlocked) {
        & az repos pr update --id $id --auto-complete true | Out-Null
      } else {
        & az repos pr complete --id $id | Out-Null
      }
      if ($LASTEXITCODE -ne 0) { throw "Azure DevOps PR completion failed." }
    }
  }

  [pscustomobject]@{ Branch=$Branch; Provider=$providerResolved; Merged=$true; AutoWhenBlocked=[bool]$AutoWhenBlocked }
}
