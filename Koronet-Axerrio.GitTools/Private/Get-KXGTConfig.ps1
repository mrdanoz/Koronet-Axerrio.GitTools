# Private/Get-KXGTConfig.ps1
# PS5.1-safe. Per-user config with first-run bootstrap using Read-Host.
# Canonical schema (no back-compat):
#   - defaultRepoPath
#   - remoteRepoUrl
#   - defaultBaseBranch
#   - auditServer
#   - auditDatabase
#   - auditSchema
#   - projectLayout  (dbForge | SSDT)
#
# Notes:
# - The per-user config lives under %APPDATA%\KXGT\config.json
# - Repo-scoped config (under .kxgt\kxgt.config.json) is read ONLY if -AllowRepoConfig is passed.
# - We intentionally do NOT use older keys like RepoPath/ServerInstance/Database.

# Cache for this session
$Script:KxgtConfigCache = $null

function Get-KXGTConfig {
    [CmdletBinding()]
    param(
        [string]$RepoPath,        # Optional: working tree path (used to seed defaultRepoPath or find repo config)
        [switch]$ForceReload,     # Re-read from disk and refresh cache
        [switch]$Interactive,     # Force prompts if host is interactive and file missing
        [switch]$AllowRepoConfig  # Only then read .kxgt/kxgt.config.json from the repo
    )

    if ($Script:KxgtConfigCache -and -not $ForceReload) {
        return $Script:KxgtConfigCache
    }

    # --- helpers -------------------------------------------------------------
    function _KXGT-ReadJson([string]$path) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
        try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
    }

    function _KXGT-WriteJson([hashtable]$obj, [string]$path) {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $path -Encoding UTF8
    }

    function _KXGT-IsInteractive { return $Host.UI -and $Host.UI.RawUI -and $Interactive }

    function _KXGT-Prompt([string]$label, [string]$default = '', [switch]$Required) {
        $prompt = if ($default) { "$label [$default]" } else { $label }
        while ($true) {
            $val = Read-Host $prompt
            if ([string]::IsNullOrWhiteSpace($val)) { $val = $default }
            if ($Required -and [string]::IsNullOrWhiteSpace($val)) {
                Write-Host "Value required." -ForegroundColor Red
            } else {
                return $val
            }
        }
    }

    function _KXGT-UserCfgPath {
        $root = Join-Path $env:APPDATA 'KXGT'
        if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
        return (Join-Path $root 'config.json')
    }

    function _KXGT-RepoCfgPath([string]$rp) {
        if (-not $rp) { return $null }
        $kxgtDir = Join-Path $rp '.kxgt'
        return (Join-Path $kxgtDir 'kxgt.config.json')
    }

    # --- locate sources ------------------------------------------------------
    $userCfg  = _KXGT-UserCfgPath
    $repoCfg  = if ($AllowRepoConfig -and $RepoPath -and (Test-Path -LiteralPath $RepoPath)) { _KXGT-RepoCfgPath $RepoPath } else { $null }
    $moduleCfg = $null  # Reserved for future use (e.g., default template under $PSScriptRoot)

    $json = $null
    $sourcePath = $null

    foreach ($p in @($repoCfg, $userCfg, $moduleCfg)) {
        if ($p) {
            $j = _KXGT-ReadJson $p
            if ($j) { $json = $j; $sourcePath = $p; break }
        }
    }

    # --- first run: create per-user config (never inside the repo) -----------
    if (-not $json) {
        $seedRepoPath   = if     ($RepoPath -and $RepoPath.Trim() -ne '') { $RepoPath }
                          elseif ($env:KXGT_REPOPATH   -and $env:KXGT_REPOPATH.Trim()   -ne '') { $env:KXGT_REPOPATH } else { 'C:\Dev\db-repo' }
        $seedRemoteUrl  = if ($env:KXGT_REMOTEURL      -and $env:KXGT_REMOTEURL.Trim()  -ne '') { $env:KXGT_REMOTEURL } else { '' }
        $seedBaseBranch = if ($env:KXGT_BASEBRANCH     -and $env:KXGT_BASEBRANCH.Trim() -ne '') { $env:KXGT_BASEBRANCH } else { 'develop' }
        $seedServer     = if ($env:KXGT_AUDIT_SERVER   -and $env:KXGT_AUDIT_SERVER.Trim()   -ne '') { $env:KXGT_AUDIT_SERVER } else { 'SQLDEV01' }
        $seedDatabase   = if ($env:KXGT_AUDIT_DATABASE -and $env:KXGT_AUDIT_DATABASE.Trim() -ne '') { $env:KXGT_AUDIT_DATABASE } else { 'ABSDEV_GIT_TEST' }
        $seedSchema     = if ($env:KXGT_AUDIT_SCHEMA   -and $env:KXGT_AUDIT_SCHEMA.Trim()   -ne '') { $env:KXGT_AUDIT_SCHEMA } else { 'dba' }
        $seedLayout     = if ($env:KXGT_PROJECT_LAYOUT -and $env:KXGT_PROJECT_LAYOUT.Trim() -ne '') { $env:KXGT_PROJECT_LAYOUT } else { 'dbForge' }

        if (_KXGT-IsInteractive) {
            Write-Host ""
            Write-Host "KXGT first-time setup — creating per-user config" -ForegroundColor Cyan
            Write-Host "(will be saved under $userCfg)`n"
            # Gather values
            while ($true) {
                $seedRepoPath = _KXGT-Prompt 'Default repo path' $seedRepoPath -Required
                if (Test-Path -LiteralPath $seedRepoPath) { break }
                $mk = Read-Host "Path '$seedRepoPath' does not exist. Create it? [Y/N]"
                if ($mk.ToUpperInvariant() -eq 'Y') {
                    try { New-Item -ItemType Directory -Path $seedRepoPath -Force | Out-Null; break } catch { Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red }
                }
            }
            $seedRemoteUrl  = _KXGT-Prompt 'Remote repo URL (https://...)' $seedRemoteUrl
            $seedBaseBranch = _KXGT-Prompt 'Default base branch' $seedBaseBranch -Required
            $seedServer     = _KXGT-Prompt 'Audit SQL Server instance' $seedServer -Required
            $seedDatabase   = _KXGT-Prompt 'Audit database' $seedDatabase -Required
            $seedSchema     = _KXGT-Prompt 'Audit schema' $seedSchema -Required
            while ($true) {
                $tmp = _KXGT-Prompt 'Project layout (dbForge/SSDT)' $seedLayout -Required
                if (@('DBFORGE','SSDT') -contains $tmp.ToUpperInvariant()) { $seedLayout = $tmp; break }
                Write-Host "Please enter 'dbForge' or 'SSDT'." -ForegroundColor Red
            }
        }

        $json = [ordered]@{
            defaultRepoPath   = $seedRepoPath
            remoteRepoUrl     = $seedRemoteUrl
            defaultBaseBranch = $seedBaseBranch
            auditServer       = $seedServer
            auditDatabase     = $seedDatabase
            auditSchema       = $seedSchema
            projectLayout     = $seedLayout
        }

        # Persist per-user file
        _KXGT-WriteJson $json $userCfg
        $sourcePath = $userCfg
    }

    # --- validate minimal expectations ---------------------------------------
    $notes = @()
    if (-not $json.defaultRepoPath -or [string]::IsNullOrWhiteSpace([string]$json.defaultRepoPath)) { $notes += 'defaultRepoPath missing/empty' }
    if (-not $json.defaultBaseBranch -or [string]::IsNullOrWhiteSpace([string]$json.defaultBaseBranch)) { $notes += 'defaultBaseBranch missing/empty' }
    if (-not $json.auditServer -or [string]::IsNullOrWhiteSpace([string]$json.auditServer)) { $notes += 'auditServer missing/empty' }
    if (-not $json.auditDatabase -or [string]::IsNullOrWhiteSpace([string]$json.auditDatabase)) { $notes += 'auditDatabase missing/empty' }
    if (-not $json.auditSchema -or [string]::IsNullOrWhiteSpace([string]$json.auditSchema)) { $notes += 'auditSchema missing/empty' }
    if (-not $json.projectLayout -or @('dbForge','SSDT') -notcontains [string]$json.projectLayout) { $notes += 'projectLayout invalid (dbForge/SSDT)' }

    if ($notes.Count -gt 0) {
        throw "Invalid KXGT config at '$sourcePath': $($notes -join '; ')"
    }

    # --- final object to return ---------------------------------------------
    $cfg = [ordered]@{
        defaultRepoPath   = [string]$json.defaultRepoPath
        remoteRepoUrl     = [string]$json.remoteRepoUrl
        defaultBaseBranch = [string]$json.defaultBaseBranch
        auditServer       = [string]$json.auditServer
        auditDatabase     = [string]$json.auditDatabase
        auditSchema       = [string]$json.auditSchema
        projectLayout     = [string]$json.projectLayout
        # Uncomment if you want trace info:
        # SourcePath      = $sourcePath
    }

    $Script:KxgtConfigCache = $cfg
    return [pscustomobject]$cfg
}
