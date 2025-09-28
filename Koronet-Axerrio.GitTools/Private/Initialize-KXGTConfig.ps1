function Initialize-KXGTConfig {
    <#
    .SYNOPSIS
      Create a new kxgt.config.json at repo-, user-, or module-scope.

    .DESCRIPTION
      Writes a minimal JSON with keys:
        - ServerInstance
        - Database
        - RepoPath
        - ProjectLayout  (SSDT | Flat)

      Scopes:
        Repo   -> <RepoPath>\.kxgt\kxgt.config.json
        User   -> %APPDATA%\KXGT\kxgt.config.json  or  ~/.config/kxgt/kxgt.config.json
        Module -> <module folder>\kxgt.config.json

    .PARAMETER Scope
      Where to store the file: Repo | User | Module

    .PARAMETER Force
      Overwrite existing file.

    .PARAMETER OpenInEditor
      Open the file after creation using default editor (Windows: notepad, else: $env:EDITOR or 'vi').

    .EXAMPLE
      Initialize-KXGTConfig -Scope Repo -RepoPath 'V:\Working\ABS\database' -ServerInstance 'sql-dev\inst1' -Database 'ABSDEV' -ProjectLayout SSDT

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Repo','User','Module')]
        [string] $Scope,

        [Parameter(Mandatory)]
        [string] $ServerInstance,

        [Parameter(Mandatory)]
        [string] $Database,

        [Parameter()]
        [ValidateSet('SSDT','Flat')]
        [string] $ProjectLayout = 'SSDT',

        # Required when Scope = Repo; optional otherwise
        [string] $RepoPath,

        [switch] $Force,
        [switch] $OpenInEditor
    )
    $isWin = $env:OS -like '*Windows*'
    # --- Determine target path ---
    switch ($Scope) {
        'Repo' {
            if (-not $RepoPath) { throw "RepoPath is required when Scope=Repo." }
            if (-not (Test-Path $RepoPath)) { throw "RepoPath '$RepoPath' does not exist." }
            $dir  = Join-Path $RepoPath '.kxgt'
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
            $target = Join-Path $dir 'kxgt.config.json'
        }
        'User' {
            
            if ($isWin) {
                $base = Join-Path $env:APPDATA 'KXGT'
            } else {
                $base = Join-Path (Join-Path $env:HOME '.config') 'kxgt'
            }
            if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
            $target = Join-Path $base 'kxgt.config.json'
        }
        'Module' {
            $moduleRoot = Split-Path -Parent $PSCommandPath
            $target     = Join-Path $moduleRoot 'kxgt.config.json'
        }
    }

    # --- Compose payload ---
    $payload = [ordered]@{
        ServerInstance = $ServerInstance
        Database       = $Database
        RepoPath       = $RepoPath
        ProjectLayout  = $ProjectLayout
    }

    $json = ($payload | ConvertTo-Json -Depth 4)

    # --- Write (with -WhatIf/-Confirm support) ---
    if ((Test-Path $target) -and -not $Force) {
        throw "Config already exists: $target (use -Force to overwrite)."
    }

    if ($PSCmdlet.ShouldProcess($target, "Write kxgt.config.json")) {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $json | Out-File -FilePath $target -Encoding UTF8
    }

    # --- Optional: open in editor ---
    if ($OpenInEditor) {
        if ($isWin) {
            Start-Process notepad.exe $target | Out-Null
        } else {
            $editor = $env:EDITOR
            if ([string]::IsNullOrWhiteSpace($editor)) { $editor = 'vi' }
            Start-Process $editor $target | Out-Null
        }
    }

    Write-Verbose "Config written to: $target"

    # Return a typed object like Get-KXGTConfig would
    [pscustomobject]@{
        Path           = $target
        ServerInstance = $payload.ServerInstance
        Database       = $payload.Database
        RepoPath       = $payload.RepoPath
        ProjectLayout  = $payload.ProjectLayout
    }
}

