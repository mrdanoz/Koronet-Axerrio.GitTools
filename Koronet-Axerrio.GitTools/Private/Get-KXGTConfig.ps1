function Get-KXGTConfig {
    <#
    .SYNOPSIS
      Load Koronet-Axerrio GitTools configuration with sensible fallbacks and env overrides.

    .DESCRIPTION
      Resolution order (first hit wins):
        1) Repo-scoped:   <RepoPath>\.kxgt\kxgt.config.json   (if a repo path is detectable or passed)
        2) User-scoped:   $env:APPDATA\KXGT\kxgt.config.json  (Windows)  OR  ~/.config/kxgt/kxgt.config.json (Linux/macOS)
        3) Module-scoped: <module folder>\kxgt.config.json

      Then apply environment overrides (if set):
        KXGT_SERVER, KXGT_DATABASE, KXGT_REPOPATH, KXGT_LAYOUT

    .OUTPUTS
      PSCustomObject with keys: ServerInstance, Database, RepoPath, ProjectLayout

    .NOTES
      - Keep file keys in PascalCase to stay consistent across tools.
    #>
    [CmdletBinding()]
    param(
        # Optional explicit repo root (skips auto-detection)
        [string] $RepoPath
    )

    # --- Helper: compute user config path cross-platform ---
    function _GetUserConfigPath {
        if ($IsWindows) {
            $base = Join-Path $env:APPDATA 'KXGT'
        } else {
            $thishome = $env:HOME
            $base = Join-Path (Join-Path $thishome '.config') 'kxgt'
        }
        if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -ErrorAction SilentlyContinue | Out-Null }
        return (Join-Path $base 'kxgt.config.json')
    }

    # --- Try detect repo root if not provided ---
    if (-not $RepoPath) {
        try {
            # Walk up from current location looking for a .git folder
            $here = Get-Location
            $dir  = Get-Item -LiteralPath $here.Path
            while ($dir -and -not (Test-Path (Join-Path $dir.FullName '.git'))) {
                $dir = $dir.Parent
            }
            if ($dir) { $RepoPath = $dir.FullName }
        } catch {
            # ignore
        }
    }

    # --- Candidate config files in priority order ---
    $candidates = @()

    if ($RepoPath) {
        $repoCfg = Join-Path (Join-Path $RepoPath '.kxgt') 'kxgt.config.json'
        $candidates += $repoCfg
    }

    $userCfg = (_GetUserConfigPath)
    $candidates += $userCfg

    # Module-scoped: where this function lives
    $moduleRoot = Split-Path -Parent $PSCommandPath
    $moduleCfg  = Join-Path $moduleRoot 'kxgt.config.json'
    $candidates += $moduleCfg

    # --- Pick first existing config ---
    $configPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $configPath) {
        throw "No configuration file found. You can create one with Initialize-KXGTConfig."
    }

    # --- Load JSON ---
    try {
        $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse config '$configPath': $($_.Exception.Message)"
    }

    # --- Materialize with env overrides ---
    $cfg = [pscustomobject]@{
        ServerInstance = $env:KXGT_SERVER    ?? $json.ServerInstance
        Database       = $env:KXGT_DATABASE  ?? $json.Database
        RepoPath       = $env:KXGT_REPOPATH  ?? ($RepoPath ?? $json.RepoPath)
        ProjectLayout  = $env:KXGT_LAYOUT    ?? ($json.ProjectLayout ?? 'SSDT')
    }

    # Basic validation
    foreach ($k in 'ServerInstance','Database','ProjectLayout') {
        if (-not ($cfg.$k) -or [string]::IsNullOrWhiteSpace($cfg.$k)) {
            throw "Config key '$k' is missing or empty in '$configPath'."
        }
    }

    return $cfg
}

