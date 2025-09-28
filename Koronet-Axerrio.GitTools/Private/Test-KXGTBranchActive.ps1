function Test-KXGTBranchActive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $AppName,
        [Parameter(Mandatory)][string] $Branch,
        [string] $ServerInstance,
        [string] $Database
    )

    if (-not (Get-Command Get-KXGTConfig -ErrorAction SilentlyContinue)) {
        throw "Get-KXGTConfig not found."
    }
    if (-not $ServerInstance -or -not $Database) {
        $cfg = Get-KXGTConfig
        if ($null -eq $ServerInstance) { $ServerInstance = $cfg.ServerInstance }
        if ($null -eq $Database) { $Database = $cfg.Database }
    }

    $vars = @(
        "app=$($AppName.Replace("'", "''"))",
        "branch=$($Branch.Replace("'", "''"))"
    )

    $sql = @'
SELECT
  EXISTS (
      SELECT 1
      FROM dba.FeatureBranch fb
      WHERE fb.Branch = N'$(branch)' AND fb.AppName = N'$(app)'
  ) AS ExistsBranch,
  EXISTS (
      SELECT 1
      FROM dba.FeatureBranch fb
      JOIN dba.FeatureBranchUser fbu ON fbu.FeatureBranchID = fb.FeatureBranchID
      WHERE fb.Branch = N'$(branch)'
        AND fb.AppName = N'$(app)'
        AND fbu.ClosedAt IS NULL
  ) AS HasOpenUsers;
'@

    $res = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $sql -Variable $vars -ErrorAction Stop
    $exists  = [bool]$res.ExistsBranch
    $open    = [bool]$res.HasOpenUsers

    [pscustomobject]@{
        Exists       = $exists
        HasOpenUsers = $open
        Allowed      = ($exists -and $open)
        Server       = $ServerInstance
        Database     = $Database
        AppName      = $AppName
        Branch       = $Branch
    }
}

