function Find-KXGTObjectFileFallback { param([string]$RepoRoot,[string]$SchemaName,[string]$ObjectName)
        $needle = "$SchemaName.$ObjectName.sql"
        Get-ChildItem -Path $RepoRoot -Recurse -File -Filter $needle -ErrorAction SilentlyContinue
    }

