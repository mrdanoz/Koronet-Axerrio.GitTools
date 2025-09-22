function Test-KXGTConfig {
    <#
    .SYNOPSIS
      Validate Koronet-Axerrio GitTools configuration, connectivity, and repo structure.

    .DESCRIPTION
      - Loads config via Get-KXGTConfig (optionally with -RepoPath override).
      - Tests SQL connectivity with a lightweight SELECT 1.
      - Validates RepoPath exists.
      - Optionally validates expected folder layout (SSDT | Flat).

    .OUTPUTS
      PSCustomObject:
        Ok              : [bool]
        ServerOk        : [bool]
        RepoOk          : [bool]
        LayoutOk        : [bool]
        ServerInstance  : [string]
        Database        : [string]
        RepoPath        : [string]
        ProjectLayout   : [string]
        MissingFolders  : [string[]]
        Notes           : [string]

    .NOTES
      - PowerShell 7+
      - Requires SqlServer module for SQL check
    #>
    [CmdletBinding()]
    param(
        # Optional: override repo root for Get-KXGTConfig resolution
        [string] $RepoPath,

        # When true, repo must exist; otherwise RepoOk=false will make Ok=false
        [switch] $RequireRepo,

        # Validate folder structure for the configured (or overridden) layout
        [switch] $CheckRepoLayout,

        # Override layout used for structural check (defaults to config.ProjectLayout)
        [ValidateSet('SSDT','Flat')]
        [string] $ExpectedLayout,

        # SQL test timeout (seconds)
        [int] $SqlTimeoutSeconds = 10
    )

    # ---- Load config
    if (-not (Get-Command Get-KXGTConfig -ErrorAction SilentlyContinue)) {
        throw "Get-KXGTConfig not found. Add it to the module before running Test-KXGTConfig."
    }

    $cfg = $null
    try {
        $cfg = if ($RepoPath) { Get-KXGTConfig -RepoPath $RepoPath } else { Get-KXGTConfig }
    }
    catch {
        throw "Failed to load configuration: $($_.Exception.Message)"
    }

    $server  = $cfg.ServerInstance
    $db      = $cfg.Database
    $root    = $cfg.RepoPath
    $layout  = if ($ExpectedLayout) { $ExpectedLayout } else { $cfg.ProjectLayout }

    Write-Verbose "Config → Server='$server' Database='$db' RepoPath='${root}' Layout='$layout'"

    # ---- Test SQL connectivity
    $serverOk = $false
    try {
        $null = Invoke-Sqlcmd -ServerInstance $server -Database $db -Query "SELECT 1 AS Ok" -QueryTimeout $SqlTimeoutSeconds -ErrorAction Stop
        $serverOk = $true
        Write-Verbose "SQL connectivity OK."
    }
    catch {
        Write-Warning "SQL connectivity failed: $($_.Exception.Message)"
        $serverOk = $false
    }

    # ---- Repo existence
    $repoOk = $true
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
        $msg = if ([string]::IsNullOrWhiteSpace($root)) { "RepoPath is empty in config." } else { "RepoPath '$root' does not exist." }
        if ($RequireRepo) {
            Write-Warning $msg
            $repoOk = $false
        } else {
            Write-Verbose $msg
            $repoOk = $false
        }
    } else {
        Write-Verbose "RepoPath exists: $root"
    }

    # ---- Layout check
    $layoutOk = $true
    $missing  = @()

    if ($CheckRepoLayout -and $repoOk) {
        switch ($layout) {
            'SSDT' {
                $expected = @(
                    'Tables',
                    'Views',
                    'Programmability\Stored Procedures',
                    'Programmability\Functions',
                    'Programmability\Triggers',
                    'Programmability\Sequences',
                    'Programmability\Types',
                    'Synonyms'
                )
            }
            'Flat' {
                $expected = @(
                    'Tables','Views','Procs','Functions','Triggers','Sequences','Types','Synonyms'
                )
            }
            default {
                $expected = @()
            }
        }

        foreach ($rel in $expected) {
            $p = Join-Path $root $rel
            if (-not (Test-Path $p)) {
                $missing += $rel
            }
        }

        if ($missing.Count -gt 0) {
            $layoutOk = $false
            Write-Verbose ("Missing folders for layout {0}: {1}" -f $layout, ($missing -join ', '))
        } else {
            Write-Verbose "Repo folder layout matches '$layout'."
        }
    }

    # ---- Aggregate result
    $ok = $serverOk -and ($RequireRepo ? $repoOk : $true) -and ($CheckRepoLayout ? $layoutOk : $true)

    $notes = @()
    if (-not $serverOk)   { $notes += "SQL connectivity failed." }
    if ($RequireRepo -and -not $repoOk) { $notes += "RepoPath missing." }
    if ($CheckRepoLayout -and -not $layoutOk) { $notes += "Repo folder layout incomplete." }

    [pscustomobject]@{
        Ok             = $ok
        ServerOk       = $serverOk
        RepoOk         = $repoOk
        LayoutOk       = $layoutOk
        ServerInstance = $server
        Database       = $db
        RepoPath       = $root
        ProjectLayout  = $layout
        MissingFolders = $missing
        Notes          = ($notes -join ' ')
    }
}
