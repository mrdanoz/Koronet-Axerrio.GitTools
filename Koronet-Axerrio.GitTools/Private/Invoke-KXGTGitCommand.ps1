function Invoke-KXGTGitCommand {
<#
.SYNOPSIS
Executes a git command and returns a hashtable with ExitCode, StdOut, StdErr.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $GitArgs,
        [string] $RepoPath,
        [switch] $NoThrow
    )

    $orig = Get-Location
    if ($RepoPath) {
        if (-not (Test-Path $RepoPath)) { throw "RepoPath '$RepoPath' does not exist." }
        Set-Location $RepoPath
    }

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new("git", ($GitArgs -join ' '))
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false

        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $exit = $p.ExitCode

        if ($RepoPath) { Set-Location $orig }

        if ($exit -ne 0 -and -not $NoThrow) {
            throw "git exited with code $exit`n$stderr"
        }
        return @{ ExitCode=$exit; StdOut=$stdout; StdErr=$stderr }
    } catch {
        if ($RepoPath) { Set-Location $orig }
        throw
    }
}

