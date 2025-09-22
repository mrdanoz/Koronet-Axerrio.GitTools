function Repair-KXGTRepoLayout {
    <#
    .SYNOPSIS
      Create missing folders in the SQL repo based on the configured layout (SSDT | Flat).

    .DESCRIPTION
      - Loads config via Get-KXGTConfig (RepoPath + ProjectLayout).
      - Optionally override layout with -Layout.
      - Creates any missing folders; supports -WhatIf / -Confirm.
      - Can drop a .gitkeep into each created folder (use -GitKeep).

    .OUTPUTS
      PSCustomObject:
        RepoPath       : string
        Layout         : string
        CreatedFolders : string[]
        SkippedFolders : string[]
        Notes          : string
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param(
        # Optional explicit repo (otherwise taken from Get-KXGTConfig)
        [string] $RepoPath,

        # Force a specific layout instead of config.ProjectLayout
        [ValidateSet('SSDT','Flat')]
        [string] $Layout,

        # Create .gitkeep in each newly created folder
        [switch] $GitKeep
    )

    if (-not (Get-Command Get-KXGTConfig -ErrorAction SilentlyContinue)) {
        throw "Get-KXGTConfig not found. Add it to the module before running Repair-KXGTRepoLayout."
    }

    $cfg = if ($RepoPath) { Get-KXGTConfig -RepoPath $RepoPath } else { Get-KXGTConfig }
    $root   = $cfg.RepoPath
    $layout = if ($Layout) { $Layout } else { $cfg.ProjectLayout }

    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
        throw "RepoPath '$root' does not exist (from config or parameter)."
    }

    # Expected folders per layout
    $expected = switch ($layout) {
        'SSDT' {
            @(
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
            @('Tables','Views','Procs','Functions','Triggers','Sequences','Types','Synonyms')
        }
        default { @() }
    }

    $created = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]

    foreach ($rel in $expected) {
        $path = Join-Path $root $rel
        if (Test-Path $path) {
            Write-Verbose "Exists: $rel"
            $skipped.Add($rel) | Out-Null
            continue
        }

        if ($PSCmdlet.ShouldProcess($path, "Create folder")) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            $created.Add($rel) | Out-Null

            if ($GitKeep) {
                $keep = Join-Path $path '.gitkeep'
                if ($PSCmdlet.ShouldProcess($keep, "Create .gitkeep")) {
                    '' | Out-File -FilePath $keep -Encoding ascii
                }
            }
            Write-Verbose "Created: $rel"
        }
    }

    [pscustomobject]@{
        RepoPath       = $root
        Layout         = $layout
        CreatedFolders = $created.ToArray()
        SkippedFolders = $skipped.ToArray()
        Notes          = if ($created.Count -eq 0) { "Nothing to create." } else { "Created $($created.Count) folder(s)." }
    }
}
