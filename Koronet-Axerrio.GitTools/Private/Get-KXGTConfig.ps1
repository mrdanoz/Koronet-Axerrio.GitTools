# Private/Get-KXGTConfig.ps1
# PS5.1-safe. Per-user config with first-run bootstrap.
# Repo-scoped config is opt-in (AllowRepoConfig), so configs don't end up in Git.

# Cache for this session
$Script:KxgtConfigCache = $null

function Get-KXGTConfig {
    [CmdletBinding()]
    param(
        [string]$RepoPath,        # Optional: working tree path (used for seeding/override)
        [switch]$ForceReload,     # Re-read from disk and refresh cache
        [switch]$Interactive,     # Force prompts if host is interactive
        [switch]$AllowRepoConfig  # Only then read .kxgt/kxgt.config.json from the repo
    )

    if ($Script:KxgtConfigCache -and -not $ForceReload) {
        return $Script:KxgtConfigCache
    }

    # --- helpers -------------------------------------------------------------
    function _KXGT-ReadJson([string]$path) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
        try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { Write-Verbose "KXGT: Failed to parse '$path' : $_"; return $null }
    }

    function _KXGT-EnsureUserDir() {
        if ($env:APPDATA -and (Test-Path Env:\APPDATA)) {
            $dir = Join-Path $env:APPDATA 'KXGT'
        } else {
            $dir = Join-Path $HOME '.config/kxgt'
        }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        return $dir
    }

    function _KXGT-WriteUserConfig([hashtable]$obj) {
        $dir  = _KXGT-EnsureUserDir
        $path = Join-Path $dir 'kxgt.config.json'
        ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }

    function _KXGT-Prompt([string]$label, [string]$current) {
        if (-not $current) { $current = '' }
        $prompt = if ($current -ne '') { "$label [$current]" } else { $label }
        $v = Read-Host $prompt
        if ($v -and ($v.Trim() -ne '')) { return $v } else { return $current }
    }

    function _KXGT-IsInteractive() {
        if ($PSBoundParameters.ContainsKey('Interactive') -and $Interactive.IsPresent) { return $true }
        return ($Host.Name -match 'ConsoleHost|Visual Studio|VSCode|Windows Terminal')
    }
    # ------------------------------------------------------------------------

    # Module root (this file lives in ...\Private\)
    $moduleRoot = try { Split-Path -Parent $PSScriptRoot } catch { $PSScriptRoot }

    # Candidate config paths (repo only when explicitly allowed)
    $userCfg   = Join-Path (_KXGT-EnsureUserDir) 'kxgt.config.json'
    $moduleCfg = Join-Path $moduleRoot 'kxgt.config.json'

    $repoCfg = $null
    if ($AllowRepoConfig) {
        $repoRoot = $null
        if ($RepoPath -and $RepoPath.Trim() -ne '') {
            $repoRoot = $RepoPath
        } elseif ($env:KXGT_REPOPATH -and $env:KXGT_REPOPATH.Trim() -ne '') {
            $repoRoot = $env:KXGT_REPOPATH
        }
        if ($repoRoot) { $repoCfg = Join-Path (Join-Path $repoRoot '.kxgt') 'kxgt.config.json' }
    }

    # Try in order: repo (opt-in) -> user -> module
    $json = $null
    $sourcePath = $null
    foreach ($p in @($repoCfg, $userCfg, $moduleCfg)) {
        if ($p) {
            $j = _KXGT-ReadJson $p
            if ($j) { $json = $j; $sourcePath = $p; break }
        }
    }

    # FIRST RUN: create a per-user config (never inside the repo)
    if (-not $json) {
        $seedRepo   = if     ($RepoPath -and $RepoPath.Trim() -ne '') { $RepoPath }
                       elseif ($env:KXGT_REPOPATH -and $env:KXGT_REPOPATH.Trim() -ne '') { $env:KXGT_REPOPATH }
                       else { 'C:\Working\Repo' }
        $seedServer = if ($env:KXGT_SERVER   -and $env:KXGT_SERVER.Trim()   -ne '') { $env:KXGT_SERVER }   else { 'SQLDEV01' }
        $seedDb     = if ($env:KXGT_DATABASE -and $env:KXGT_DATABASE.Trim() -ne '') { $env:KXGT_DATABASE } else { 'ABSDEV' }
        $seedLayout = if ($env:KXGT_LAYOUT   -and $env:KXGT_LAYOUT.Trim()   -ne '') { $env:KXGT_LAYOUT }   else { 'dbForge' }

        if (_KXGT-IsInteractive) {
            Write-Host ""
            Write-Host "KXGT first-time setup — creating per-user config" -ForegroundColor Cyan
            Write-Host "(will be saved under $userCfg)`n"
            $seedRepo   = _KXGT-Prompt 'Local repo path (e.g., C:\Working\ABS)' $seedRepo
            $seedServer = _KXGT-Prompt 'SQL Server instance (e.g., SQLDEV01)'   $seedServer
            $seedDb     = _KXGT-Prompt 'Database name (e.g., ABSDEV)'           $seedDb
            $seedLayout = _KXGT-Prompt 'Project layout (dbForge/Flat/Loose)'     $seedLayout
        }

        $json = [ordered]@{
            ServerInstance = $seedServer
            Database       = $seedDb
            RepoPath       = $seedRepo
            ProjectLayout  = $seedLayout
        }

        $sourcePath = _KXGT-WriteUserConfig $json
        Write-Verbose "KXGT: created per-user config at '$sourcePath'."
    }

    # Env var overrides and parameter precedence (env > param > file)
    $server = if ($env:KXGT_SERVER   -and $env:KXGT_SERVER.Trim()   -ne '') { $env:KXGT_SERVER }   else { [string]$json.ServerInstance }
    $db     = if ($env:KXGT_DATABASE -and $env:KXGT_DATABASE.Trim() -ne '') { $env:KXGT_DATABASE } else { [string]$json.Database }
    $repo   = if ($env:KXGT_REPOPATH -and $env:KXGT_REPOPATH.Trim() -ne '') { $env:KXGT_REPOPATH }
              elseif ($RepoPath -and $RepoPath.Trim() -ne '')               { $RepoPath }
              else                                                           { [string]$json.RepoPath }
    $layout = if ($env:KXGT_LAYOUT   -and $env:KXGT_LAYOUT.Trim()   -ne '') { $env:KXGT_LAYOUT }   else { [string]$json.ProjectLayout }

    if (-not $layout -or $layout.Trim() -eq '') { $layout = 'SSDT' }
    switch -Regex ($layout) {
        '^(?i)ssdt$'   { $layout = 'SSDT' ; break }
        '^(?i)flyway$' { $layout = 'dbForge' ; break }
        '^(?i)loose$'  { $layout = 'Flat' ; break }
        default        { $layout = 'dbForge' }
    }

    # Validate; if missing, prompt (interactive) or fill safe defaults (non-interactive)
    $missing = @()
    if (-not $server -or $server.Trim() -eq '') { $missing += 'ServerInstance' }
    if (-not $db     -or $db.Trim()     -eq '') { $missing += 'Database' }
    if (-not $repo   -or $repo.Trim()   -eq '') { $missing += 'RepoPath' }

    if ($missing.Count -gt 0) {
        if (_KXGT-IsInteractive) {
            if ($missing -contains 'RepoPath')       { $repo   = _KXGT-Prompt 'Local repo path (e.g., C:\Working\ABS)' 'C:\Working\Repo' }
            if ($missing -contains 'ServerInstance') { $server = _KXGT-Prompt 'SQL Server instance (e.g., SQLDEV01)'   'SQLDEV01' }
            if ($missing -contains 'Database')       { $db     = _KXGT-Prompt 'Database name (e.g., ABSDEV)'           'ABSDEV' }
            # Persist repaired values to user config only (never to repo/module files)
            $persist = [ordered]@{
                ServerInstance = $server
                Database       = $db
                RepoPath       = $repo
                ProjectLayout  = $layout
            }
            $null = _KXGT-WriteUserConfig $persist
            Write-Verbose "KXGT: repaired config and saved to user config."
        } else {
            if ($missing -contains 'RepoPath')       { $repo   = 'C:\Working\Repo' }
            if ($missing -contains 'ServerInstance') { $server = 'SQLDEV01' }
            if ($missing -contains 'Database')       { $db     = 'ABSDEV' }
        }
    }

    # Final object
    $cfg = [ordered]@{
        ServerInstance = $server
        Database       = $db
        RepoPath       = $repo
        ProjectLayout  = $layout
        # Uncomment if you want trace info:
        # SourcePath   = $sourcePath
    }

    $Script:KxgtConfigCache = $cfg
    return $cfg
}
