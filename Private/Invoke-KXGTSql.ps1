function Invoke-KXGTSql {
<#
.SYNOPSIS
Executes T-SQL with optional Application Name on the connection.

.DESCRIPTION
If -AppName is provided (or present in config as defaultAppName), the function will build a
full connection string and call Invoke-Sqlcmd with -ConnectionString so that PROGRAM_NAME()
inside SQL Server equals your AppName (e.g., 'KXGT-daniel'). This enables the DDL audit trigger
to resolve Developer via dba.Developer.AppName even when using a shared SQL login.

.PARAMETER ServerInstance
SQL Server instance (e.g., SQLDEV01).

.PARAMETER Database
Database name (e.g., ABSDEV).

.PARAMETER Query
T-SQL to execute.

.PARAMETER SqlCredential
PSCredential for SQL Authentication (shared login like 'axe-dev').

.PARAMETER AppName
Application Name for the connection string. If omitted, tries config.defaultAppName; if still empty, uses Get-KXGTAppName().
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ServerInstance,
        [Parameter(Mandatory)] [string] $Database,
        [string] $Query,
        [System.Management.Automation.PSCredential] $SqlCredential,
        [string] $AppName
    )

    $cfg = Get-KXGTConfig
    if (-not $AppName) { $AppName = if ($cfg) { $cfg.defaultAppName } else { $null } }
    if (-not $AppName) { $AppName = Get-KXGTAppName }

    $conn = "Server=$ServerInstance;Database=$Database;Application Name=$AppName;Encrypt=False;TrustServerCertificate=True;"
    if ($SqlCredential) {
        $user = $SqlCredential.UserName
        $pass = $SqlCredential.GetNetworkCredential().Password
        $conn += "User ID=$user;Password=$pass;"
    } else {
        $conn += "Trusted_Connection=True;"
    }

    $common = @{ ErrorAction = 'Stop' }
    if ($PSBoundParameters.ContainsKey('Query')) {
        return Invoke-Sqlcmd -ConnectionString $conn -Query $Query @common
    } else {
        return Invoke-Sqlcmd -ConnectionString $conn @common
    }
}

