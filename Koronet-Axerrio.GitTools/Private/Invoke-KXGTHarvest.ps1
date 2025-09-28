function Invoke-KXGTHarvest {
    <#
    .SYNOPSIS
      Harvest audited DDL for Branch + AppName (database-first).
      CREATE/ALTER → (re)script object file; DROP → delete file.

    .NOTES
      - PowerShell 7+
      - Requires: SqlServer module (Invoke-Sqlcmd + SMO types)
      - Reads defaults from Get-KXGTConfig (ServerInstance, Database, RepoPath, ProjectLayout)
      - Optionally narrows audit by current developer via dba.Developer (git identity)
      - Honors -WhatIf / -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)] [string] $AppName,
        [Parameter(Mandatory)] [string] $Branch,

        # Optional overrides (else from config)
        [string] $RepoPath,
        [ValidateSet('SSDT','Flat')] [string] $ProjectLayout,

        # Report options
        [switch] $WriteSqlBundle,
        [switch] $WriteJson,
        [switch] $WriteCsv,

        # Side-effects
        [switch] $ApplyDrops,                       # actually delete files for DROP
        [bool]   $ScriptCreatesAndAlters = $true    # (re)script CREATE/ALTER into repo
    )

    # --- Helpers: path mapping ---
    function Get-KXGTObjectFilePath {
        <#
        .SYNOPSIS
        Map a SQL object (type/schema/name) to a repo file path (schema.object.sql).
        Supports DBForge, SSDT, and Flat repo layouts.

        .PARAMETER Layout
        DBForge | SSDT | Flat   (set your config ProjectLayout to 'DBForge')

        .PARAMETER TriggerScope
        Optional hint for TRIGGER: 'Database' or 'Table'.
        - Database → Programmability\Database Triggers (DBForge)
        - Table    → returns $null (table triggers are scripted with the table)

        .PARAMETER UserTypeKind
        Optional hint for TYPE: 'Data' or 'Table' (DBForge splits user types).
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [string] $RepoRoot,
            [Parameter(Mandatory)] [ValidateSet('DBForge','SSDT','Flat')] [string] $Layout,
            [Parameter(Mandatory)] [string] $ObjectType,   # TABLE | VIEW | PROCEDURE | FUNCTION | TRIGGER | SEQUENCE | SYNONYM | DEFAULT | TYPE | ...
            [Parameter(Mandatory)] [string] $SchemaName,
            [Parameter(Mandatory)] [string] $ObjectName,

            [ValidateSet('Database','Table')] [string] $TriggerScope,
            [ValidateSet('Data','Table')]     [string] $UserTypeKind
        )

        # Normalize + safe filename
        $type     = $ObjectType.ToUpperInvariant()
        $safeName = [regex]::Replace("$SchemaName.$ObjectName", '[\\/:*?\"<>|]', '_')
        $baseName = "$safeName.sql"

        switch ($Layout) {
            'DBForge' {
                # Top-level: Tables, Views, Synonyms, Programmability\{...}
                switch ($type) {
                    'TABLE'        { $folder = 'Tables' }
                    'VIEW'         { $folder = 'Views' }
                    'SYNONYM'      { $folder = 'Synonyms' }
                    'PROCEDURE'    { $folder = 'Programmability\Procedures' }
                    'FUNCTION'     { $folder = 'Programmability\Functions' }
                    'SEQUENCE'     { $folder = 'Programmability\Sequences' }
                    'DEFAULT'      { $folder = 'Programmability\Defaults' }
                    'TRIGGER'      {
                        if ($TriggerScope -eq 'Database') { $folder = 'Programmability\Database Triggers' }
                        else { return $null } # table triggers live with the table script in DBForge
                    }
                    'TYPE' {
                        if ($UserTypeKind -eq 'Table') { $folder = 'Programmability\User Types\Table Types' }
                        else                           { $folder = 'Programmability\User Types\Data Types' } # default
                    }
                    default { return $null }
                }
            }

            'SSDT' {
                $map = @{
                    'TABLE'     = 'Tables'
                    'VIEW'      = 'Views'
                    'SYNONYM'   = 'Synonyms'
                    'PROCEDURE' = 'Programmability\Stored Procedures'
                    'FUNCTION'  = 'Programmability\Functions'
                    'TRIGGER'   = 'Programmability\Triggers'
                    'SEQUENCE'  = 'Programmability\Sequences'
                    'TYPE'      = 'Programmability\Types'
                    'DEFAULT'   = $null
                }
                $folder = $map[$type]; if (-not $folder) { return $null }
            }

            'Flat' {
                $map = @{
                    'TABLE'     = 'Tables'
                    'VIEW'      = 'Views'
                    'SYNONYM'   = 'Synonyms'
                    'PROCEDURE' = 'Procs'
                    'FUNCTION'  = 'Functions'
                    'TRIGGER'   = 'Triggers'
                    'SEQUENCE'  = 'Sequences'
                    'TYPE'      = 'Types'
                    'DEFAULT'   = 'Defaults'
                }
                $folder = $map[$type]; if (-not $folder) { return $null }
            }
        }

        return (Join-Path (Join-Path $RepoRoot $folder) $baseName)
    }

    function Find-KXGTObjectFileFallback { param([string]$RepoRoot,[string]$SchemaName,[string]$ObjectName)
        $needle = "$SchemaName.$ObjectName.sql"
        Get-ChildItem -Path $RepoRoot -Recurse -File -Filter $needle -ErrorAction SilentlyContinue
    }

    # --- Load config ---
    if (-not (Get-Command Get-KXGTConfig -ErrorAction SilentlyContinue)) {
        throw "Get-KXGTConfig not found. Ensure the helper is exported by the module."
    }
    $cfg = Get-KXGTConfig
    $ServerInstance = $cfg.ServerInstance
    $Database       = $cfg.Database
    if (-not $RepoPath)      { $RepoPath = $cfg.RepoPath }
    if (-not $ProjectLayout) { $ProjectLayout = if ($cfg -and $cfg.ProjectLayout) { $cfg.ProjectLayout } else { 'SSDT' } }


    # --- Gate: branch must exist and have open users ---
    $varsGate = @("app=$($AppName.Replace("'", "''"))","branch=$($Branch.Replace("'", "''"))")
    $sqlGate = @'
SELECT
  EXISTS (SELECT 1 FROM dba.FeatureBranch fb WHERE fb.Branch = N'$(branch)' AND fb.AppName = N'$(app)') AS ExistsBranch,
  EXISTS (
    SELECT 1
    FROM dba.FeatureBranch fb
    JOIN dba.FeatureBranchUser fbu ON fbu.FeatureBranchID = fb.FeatureBranchID
    WHERE fb.Branch = N'$(branch)' AND fb.AppName = N'$(app)' AND fbu.ClosedAt IS NULL
  ) AS HasOpenUsers;
'@
    try {
        $g = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $sqlGate -Variable $varsGate -ErrorAction Stop
    } catch { throw "Harvest gate check failed: $($_.Exception.Message)" }
    if (-not [bool]$g.ExistsBranch) { throw "Harvest aborted: Feature branch '$Branch' for app '$AppName' does not exist in the database." }
    if (-not [bool]$g.HasOpenUsers) { throw "Harvest aborted: No active users linked to '$Branch' (FeatureBranchUser.ClosedAt IS NULL required)." }

    # --- Resolve current developer (optional narrowing by login) ---
    $ResolvedLogin = ''
    try {
        $gitEmail=$null;$gitUser=$null
        if ($RepoPath) { Push-Location $RepoPath; try { $gitEmail = (& git config --get user.email 2>$null); $gitUser = (& git config --get user.name 2>$null) } finally { Pop-Location } }
        if (-not $gitEmail) { $gitEmail = (& git config --global --get user.email 2>$null) }
        if (-not $gitUser)  { $gitUser  = (& git config --global --get user.name  2>$null) }
        if ($gitEmail -or $gitUser) {
            $emailVal = (if ($gitEmail) { $gitEmail } else { '' }).Replace("'", "''")
            $userVal  = (if ($gitUser) { $gitUser } else { '' }).Replace("'", "''")
            $dev = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query @"
SELECT TOP (1) LoginName, RepoPath
FROM dba.Developer WITH (NOLOCK)
WHERE (Email = N'$emailVal' AND LEN('$emailVal') > 0)
   OR (GitHandle = N'$userVal' AND LEN('$userVal') > 0);
"@ -ErrorAction Stop
            if ($dev) {
                if (-not $RepoPath -and $dev.RepoPath) { $RepoPath = [string]$dev.RepoPath }
                if ($dev.LoginName) { $ResolvedLogin = [string]$dev.LoginName }
                Write-Verbose "Resolved developer: Login='$ResolvedLogin'; RepoPath='${RepoPath}'"
            } else {
                Write-Verbose "Developer not found in dba.Developer for git identity '$gitUser' / '$gitEmail'. Harvesting for all linked users."
            }
        } else {
            Write-Verbose "No git identity found; harvesting for all linked users."
        }
    } catch {
        Write-Warning "Developer resolution failed: $($_.Exception.Message). Proceeding without narrowing by Login."
    }

    # --- Reports output dir (under repo if available) ---
    $ts = (Get-Date).ToString('yyyyMMddHHmmss')
    $OutDir = $null
    if ($RepoPath) {
        $OutDir = Join-Path $RepoPath (Join-Path '_harvest' (Join-Path $Branch $ts))
        New-Item -ItemType Directory -Path $OutDir -ErrorAction SilentlyContinue | Out-Null
    }

    # --- Pull audit rows for Branch+App (optionally narrowed by Login) ---
    $vars = @(
        "branch=$($Branch.Replace("'", "''"))",
        "app=$($AppName.Replace("'", "''"))",
        "login=$($ResolvedLogin.Replace("'", "''"))"
    )
    $tsql = @'
;WITH Users AS (
    SELECT fbu.LoginName
    FROM dba.FeatureBranchUser AS fbu
    JOIN dba.FeatureBranch      AS fb  ON fb.FeatureBranchID = fbu.FeatureBranchID
    WHERE fb.Branch  = N'$(branch)'
      AND fb.AppName = N'$(app)'
      AND (fbu.ClosedAt IS NULL)
)
SELECT
    a.AuditID, a.PostTime, a.EventType, a.ObjectType,
    a.SchemaName, a.ObjectName, a.DatabaseName, a.TSQL,
    a.LoginName, a.OriginalLoginName, a.AppName, a.HostName,
    a.SessionID, a.Succeeded
FROM dba.DDL_Audit AS a
WHERE a.AppName = N'$(app)'
  AND a.Succeeded = 1
  AND ( $(login) = N'' OR a.LoginName = N'$(login)' )
  AND a.LoginName IN (SELECT LoginName FROM Users)
ORDER BY a.PostTime;
'@
    try {
        $rows = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $tsql -Variable $vars -ErrorAction Stop
    } catch { throw "SQL error: $($_.Exception.Message)" }

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Verbose "No changes found for Branch '$Branch' and App '$AppName'."
        return [pscustomobject]@{
            Changes       = @()
            Scripted      = @()
            DropDeletions = @()
            OutDir        = $OutDir
            RepoPath      = $RepoPath
            Server        = $ServerInstance
            Database      = $Database
            ResolvedLogin = $ResolvedLogin
        }
    }

    # --- Reduce to latest change per object (ObjectType+Schema+ObjectName) ---
    $latest = $rows | Group-Object ObjectType,SchemaName,ObjectName | ForEach-Object {
        $_.Group | Sort-Object PostTime | Select-Object -Last 1
    }

    # --- Prepare SMO for scripting (once) ---
    $scripted      = New-Object System.Collections.Generic.List[object]
    $dropDeletions = New-Object System.Collections.Generic.List[object]
    $srv=$null;$db=$null;$scripter=$null
    if ($ScriptCreatesAndAlters) {
        try {
            $srv = New-Object Microsoft.SqlServer.Management.Smo.Server($ServerInstance)
            $db = $srv.Databases[$Database]
            if ($null -eq $db) { throw "Database '$Database' not found on $ServerInstance." }

            $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($srv)
            $o = $scripter.Options
            $o.ToFileOnly            = $false
            $o.IncludeIfNotExists    = $true
            $o.SchemaQualify         = $true
            $o.IncludeHeaders        = $false
            $o.WithDependencies      = $false
            $o.DriAll                = $true   # keys/constraints
            $o.Triggers              = $true
            $o.Indexes               = $true
            $o.Permissions           = $true
            $o.AnsiPadding           = $true
            $o.NoIdentities          = $false
            $o.ScriptBatchTerminator = $true
        } catch {
            Write-Warning "SMO initialization failed; CREATE/ALTER scripting disabled. $($_.Exception.Message)"
            $ScriptCreatesAndAlters = $false
        }
    }

    # --- Process each latest change ---
    foreach ($row in $latest) {
        $otype  = $row.ObjectType
        $schema = $row.SchemaName
        $name   = $row.ObjectName

        if ($row.EventType -eq 'DROP') {
            if (-not $RepoPath) { Write-Verbose "DROP for $schema.$name but RepoPath not set; skipping deletion."; continue }
            $target = Get-KXGTObjectFilePath -RepoRoot $RepoPath -Layout $ProjectLayout -ObjectType $otype -SchemaName $schema -ObjectName $name
            $files=@()
            if ($target -and (Test-Path $target)) { $files = ,(Get-Item -LiteralPath $target) }
            else {
                $hits = Find-KXGTObjectFileFallback -RepoRoot $RepoPath -SchemaName $schema -ObjectName $name
                if ($hits) { $files = $hits }
            }
            if (-not $files -or $files.Count -eq 0) { Write-Verbose "DROP: no file found for $schema.$name in '$RepoPath'."; continue }

            foreach ($file in $files) {
                $rec = [pscustomobject]@{ ObjectType=$otype; SchemaName=$schema; ObjectName=$name; File=$file.FullName; Deleted=$false }
                if ($ApplyDrops) {
                    if ($PSCmdlet.ShouldProcess($file.FullName, "Remove file for DROP of $schema.$name")) {
                        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $rec.Deleted=$true; Write-Verbose "Removed: $($file.FullName)" }
                        catch { Write-Warning "Could not remove '$($file.FullName)': $($_.Exception.Message)" }
                    }
                } else {
                    Write-Verbose "Would remove: $($file.FullName) (use -ApplyDrops to actually delete)."
                }
                $dropDeletions.Add($rec) | Out-Null
            }
            continue
        }

        # CREATE / ALTER → (re)script from live DB
        if ($ScriptCreatesAndAlters) {
            if (-not $RepoPath) { Write-Verbose "CREATE/ALTER for $schema.$name but RepoPath not set; skipping scripting."; continue }
            try {
                $obj = switch ($otype.ToUpperInvariant()) {
                    'TABLE'        { $db.Tables[$name,$schema] }
                    'VIEW'         { $db.Views[$name,$schema] }
                    'PROCEDURE'    { $db.StoredProcedures[$name,$schema] }
                    'FUNCTION'     { $db.UserDefinedFunctions[$name,$schema] }
                    'SEQUENCE'     { $db.Sequences[$name,$schema] }
                    'SYNONYM'      { $db.Synonyms[$name,$schema] }
                    'TRIGGER'      {
                        # Try table triggers (object triggers)
                        $tbl = $db.Tables | Where-Object { $_.Schema -eq $schema -and $_.Triggers[$name] }
                        if ($tbl) { $tbl.Triggers[$name] } else { $null }
                    }
                    default { $null }
                }
                if (-not $obj) { Write-Warning "SMO object not found for $otype $schema.$name; skipping."; continue }

                $script = ($scripter.Script($obj) -join [Environment]::NewLine).Trim()
                $path   = Get-KXGTObjectFilePath -RepoRoot $RepoPath -Layout $ProjectLayout -ObjectType $otype -SchemaName $schema -ObjectName $name
                if (-not $path) { Write-Warning "No mapped path for $otype $schema.$name; adjust mapping in Get-KXGTObjectFilePath."; continue }

                $dir = Split-Path -Parent $path
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

                if ($PSCmdlet.ShouldProcess($path, "Write scripted definition for $otype $schema.$name")) {
                    [IO.File]::WriteAllText($path, $script + [Environment]::NewLine, [Text.Encoding]::UTF8)
                    $scripted.Add([pscustomobject]@{ ObjectType=$otype; SchemaName=$schema; ObjectName=$name; File=$path }) | Out-Null
                    Write-Verbose "Scripted to: $path"
                }
            } catch {
                Write-Warning ("Scripting failed for {0} {1}.{2}: {3}" -f $otype, $schema, $name, $_.Exception.Message)
            }
        }
    }

    # --- Optional reports from raw audit (all rows) ---
    if ($OutDir) {
        if ($WriteSqlBundle) {
            $sqlPath = Join-Path $OutDir "changes_$($Branch)_$ts.sql"
            $sb = [System.Text.StringBuilder]::new()
            foreach ($r in $rows) {
                $tsql = if ($r.TSQL) { $r.TSQL } else { '' }
                $null = $sb.AppendLine($tsql.Trim())
                $null = $sb.AppendLine('GO')
            }

            [IO.File]::WriteAllText($sqlPath, $sb.ToString(), [Text.Encoding]::UTF8)
            Write-Verbose "Wrote SQL bundle: $sqlPath"
        }
        if ($WriteJson) {
            $jsonPath = Join-Path $OutDir "changes_$($Branch)_$ts.json"
            $rows | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8
            Write-Verbose "Wrote JSON: $jsonPath"
        }
        if ($WriteCsv) {
            $csvPath = Join-Path $OutDir "changes_$($Branch)_$ts.csv"
            $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            Write-Verbose "Wrote CSV: $csvPath"
        }
    }

    # --- Return summary ---
    [pscustomobject]@{
        Changes       = $rows
        Scripted      = $scripted.ToArray()
        DropDeletions = $dropDeletions.ToArray()
        OutDir        = $OutDir
        RepoPath      = $RepoPath
        Server        = $ServerInstance
        Database      = $Database
        ResolvedLogin = $ResolvedLogin
    }
}

