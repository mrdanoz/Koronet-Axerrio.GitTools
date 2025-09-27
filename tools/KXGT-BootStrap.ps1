<# 
KXGT-Bootstrap.ps1
- Installs/updates Koronet-Axerrio.GitTools from the latest GitHub release
- Forces install to LOCAL Documents\PowerShell\Modules (avoids OneDrive redirection)
- Works in PowerShell 7 and Windows PowerShell 5.1
#>

[CmdletBinding()]
param(
    # Change default if you move the repo
    [string]$Repo = 'mrdanoz/Koronet-Axerrio.GitTools',

    # Prefer pre-releases when selecting the latest
    [switch]$PreRelease,

    # Skip first-run config initialization
    [switch]$NoConfigInit
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$moduleName = 'Koronet-Axerrio.GitTools'
$ua = @{ 'User-Agent' = 'KXGT-Bootstrap' }

Write-Host "Installing/Updating $moduleName from $Repo ..." -ForegroundColor Cyan

function Get-LocalUserModulesRoot {
    # Always prefer LOCAL Documents (not OneDrive) for PS7 and PS5.1
    $localRoot  = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'
    #$oneDriveEn = if ($env:OneDrive) { Join-Path $env:OneDrive 'Documents\PowerShell\Modules' }
    #$oneDriveNl = if ($env:OneDrive) { Join-Path $env:OneDrive 'Documenten\PowerShell\Modules' }

    # Ensure local path exists and is first in PSModulePath
    if (-not (Test-Path $localRoot)) { New-Item -ItemType Directory -Path $localRoot -Force | Out-Null }

    $paths = $env:PSModulePath -split ';'
    if ($paths -notcontains $localRoot) {
        $env:PSModulePath = "$localRoot;$env:PSModulePath"
        Write-Host "Prepended user modules path: $localRoot" -ForegroundColor DarkCyan
    }

    # If OneDrive module dirs exist, leave them alone; we simply install to LOCAL
    return $localRoot
}

function Get-LatestRelease {
    param([string]$repo, [switch]$pre)
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers $ua
        if (-not $pre -and $rel.prerelease) {
            # If /latest happens to point at a prerelease and we didn't ask for it, fall back to list
            throw "Latest is prerelease but -PreRelease not specified."
        }
        return $rel
    } catch {
        Write-Host "Falling back to releases list..." -ForegroundColor Yellow
        $rels = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=10" -Headers $ua
        if (-not $rels) { throw "No releases found for $repo." }
        if ($pre) {
            return ($rels | Select-Object -First 1)
        } else {
            $stable = $rels | Where-Object { -not $_.prerelease } | Select-Object -First 1
            if ($stable) { return $stable }
            return ($rels | Select-Object -First 1)
        }
    }
}

function Get-AssetZip {
    param($release)
    # Prefer assets named like module zip; otherwise any .zip
    $asset = $release.assets | Where-Object { $_.name -match "^$moduleName-.*\.zip$" } | Select-Object -First 1
    if (-not $asset) { $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1 }
    if (-not $asset) { throw "No .zip asset found on release '$($release.tag_name ?? $release.name)'." }
    return $asset
}

# 1) Resolve install root (LOCAL Documents)
$modulesRoot = Get-LocalUserModulesRoot
$dest = Join-Path $modulesRoot $moduleName

# 2) Get latest release + asset
Write-Host "Checking latest release for $Repo ..." -ForegroundColor DarkCyan
$latest = Get-LatestRelease -repo $Repo -pre:$PreRelease
$tag    = $latest.tag_name ?? $latest.name
Write-Host "Using release: $tag" -ForegroundColor Green
$asset  = Get-AssetZip -release $latest

# 3) Download + extract to temp, then copy to the canonical module folder
$tempZip = Join-Path $env:TEMP $asset.name
$tempDir = Join-Path $env:TEMP ("KXGT_" + [Guid]::NewGuid().ToString('N'))

Write-Host "Downloading $($asset.name) ..." -ForegroundColor DarkCyan
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -Headers $ua
Unblock-File -Path $tempZip -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $tempDir | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
Remove-Item $tempZip -Force

# Find the *.psd1 inside the extracted content (handle nested folder layouts)
$psd1 = Get-ChildItem -Path $tempDir -Recurse -Filter "$moduleName.psd1" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $psd1) { throw "Could not find $moduleName.psd1 in the archive (release $tag)." }
$moduleBaseSource = Split-Path -Parent $psd1.FullName
Write-Host "Module base found in archive: $moduleBaseSource" -ForegroundColor DarkCyan

# Replace existing install
if (Test-Path $dest) {
    Write-Host "Removing existing install: $dest" -ForegroundColor DarkYellow
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $dest | Out-Null

Write-Host "Copying module files to: $dest" -ForegroundColor DarkCyan
Copy-Item -Path (Join-Path $moduleBaseSource '*') -Destination $dest -Recurse -Force

# Cleanup temp
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# 4) Unblock + import
Get-ChildItem $dest -Recurse | Unblock-File -ErrorAction SilentlyContinue
$psd1Dest = Join-Path $dest "$moduleName.psd1"
if (-not (Test-Path $psd1Dest)) { throw "Installed module missing manifest at $psd1Dest" }

Write-Host "Importing module..." -ForegroundColor DarkCyan
Import-Module $psd1Dest -Force

Write-Host "Installed and imported: $moduleName ($tag)" -ForegroundColor Green

# 5) First-run config helper
if (-not $NoConfigInit) {
    try {
        Get-KXGTConfig | Out-Null
    } catch {
        Write-Host "No local config found. Running Initialize-KXGTConfig..." -ForegroundColor Yellow
        Initialize-KXGTConfig
    }
}

# 6) Summary: show exported commands
Get-Command -Module $moduleName | Select-Object Name, Version | Format-Table -AutoSize
