function Get-KXGTAppName {
<#
.SYNOPSIS
Builds a default Application Name for SQL connections (e.g., "KXGT-daniel").

.PARAMETER LoginName
Windows/UPN or simple name; defaults to $env:USERNAME.

.PARAMETER Prefix
Prefix for the app name (default: 'KXGT-'; can be set in config as appNamePrefix).
#>
    [CmdletBinding()]
    param(
        [string] $LoginName = $env:USERNAME,
        [string] $Prefix
    )
    $cfg = Get-KXGTConfig
    if (-not $Prefix) {
        $Prefix = if ($cfg -and $cfg.appNamePrefix) { $cfg.appNamePrefix } else { 'KXGT-' }
    }
    # normalize domain\user -> user
    $simple = ($LoginName -replace '^.*\\','')  # drop domain\
    $simple = $simple -replace '[^\w\-.]','-'   # sanitize
    return "$Prefix$simple"
}

