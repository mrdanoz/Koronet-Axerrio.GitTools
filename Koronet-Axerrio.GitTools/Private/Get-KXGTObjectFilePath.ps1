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

