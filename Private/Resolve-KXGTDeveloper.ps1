function Resolve-KXGTDeveloper {
<#
.SYNOPSIS
Resolves a developer via dba.usp_Developer_Resolve (by LoginName or GitHandle).
#>
    [CmdletBinding()]
    param(
        [string] $LoginName = $env:USERNAME,
        [string] $GitHandle,
        [string] $SqlInstance,
        [string] $Database,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $AppName
    )
    $cfg = Get-KXGTConfig
    if (-not $SqlInstance) { $SqlInstance = $cfg.auditServer }
    if (-not $Database)    { $Database    = $cfg.auditDatabase }
    if (-not $AppName)     { $AppName     = Get-KXGTAppName -LoginName $LoginName }

    $loginLit = if ($LoginName) { "N'$LoginName'" } else { 'NULL' }
    $gitLit   = if ($GitHandle) { "N'$GitHandle'" } else { 'NULL' }

    $sql = @"
EXEC dba.usp_Developer_Resolve
    @LoginName = $loginLit,
    @GitHandle = $gitLit;
"@
    try {
        $r = Invoke-KXGTSql -ServerInstance $SqlInstance -Database $Database -Query $sql -SqlCredential $SqlCredential -AppName $AppName
        return $r | Select-Object -First 1
    } catch {
        Write-Warning "Resolve-KXGTDeveloper failed: $($_.Exception.Message)"
        return $null
    }
}

