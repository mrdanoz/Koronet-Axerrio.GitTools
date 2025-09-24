# Koronet-Axerrio.GitTools.psm1
# Loads Private/ then Public/ scripts and exports functions by filename.
# Works even if executed outside true module context (dev convenience).

# Resolve module root robustly
$Script:ModuleRoot = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($PSCommandPath) {
    Split-Path -Parent $PSCommandPath
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

# --- Load Private helpers first ---
$privateDir = Join-Path $Script:ModuleRoot 'Private'
if (Test-Path $privateDir) {
    Get-ChildItem -Path $privateDir -Filter *.ps1 -File | ForEach-Object {
        try {
            . $_.FullName
        } catch {
            throw "Failed to load private script '$($_.Name)': $($_.Exception.Message)"
        }
    }
}

# --- Load Public functions and collect names to export ---
$exportList = @()
$publicDir  = Join-Path $Script:ModuleRoot 'Public'
if (Test-Path $publicDir) {
    $publicFiles = Get-ChildItem -Path $publicDir -Filter *.ps1 -File | Sort-Object Name
    foreach ($file in $publicFiles) {
        try {
            . $file.FullName
            $exportList += [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        } catch {
            throw "Failed to load public script '$($file.Name)': $($_.Exception.Message)"
        }
    }
}

# Fallback: if no Public/*.ps1 were found, export the known commands (best-effort)
#if (-not $exportList -or $exportList.Count -eq 0) {
#    $exportList = @('New-KXGTFeatureBranch','New-KXGTPullRequest','Complete-KXGTPullRequest','Get-KXGTConfig')
#}

# --- Export only the intended public functions ---
# (The manifest can also restrict exports; this keeps runtime aligned with your Public folder.)
Export-ModuleMember -Function @(
  'New-KXGTFeatureBranch',
  'Invoke-KXGTPush',
  'New-KXGTPullRequest',
  # include these only if you want them public:
  'Get-KXGTConfig'
  # 'Initialize-KXGTUserConfig',
  # 'Set-KXGTConfig',
  # 'Show-KXGTConfig'
) -Alias @()