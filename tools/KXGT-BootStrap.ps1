<# KXGT-Bootstrap.ps1
   One-shot installer/updater for Koronet-Axerrio.GitTools from GitHub Releases.
   - Installs for current user (no admin)
   - Works with public or private repos (token via -PrivateRepo or $env:GITHUB_TOKEN)
#>

[CmdletBinding()]
param(
  [string]$Repo = 'Koronet-Axerrio/Koronet-Axerrio.GitTools',  # owner/repo
  [string]$ModuleName = 'Koronet-Axerrio.GitTools',
  [switch]$PrivateRepo,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Info([string]$m){ if(-not $Quiet){ Write-Host $m -ForegroundColor Cyan } }
function Write-Ok  ([string]$m){ if(-not $Quiet){ Write-Host $m -ForegroundColor Green } }
function Write-Wrn ([string]$m){ if(-not $Quiet){ Write-Warning $m } }

# --- Auth header: use it if -PrivateRepo OR a token is already present ---
$headers = @{ 'User-Agent' = 'KXGT-Bootstrap' }
if ($PrivateRepo -or $env:GITHUB_TOKEN) {
  if (-not $env:GITHUB_TOKEN) {
    Write-Info "Enter a GitHub PAT with repo read access."
    $sec = Read-Host -AsSecureString "GitHub PAT"
    $env:GITHUB_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN"
}

function Get-LatestRelease {
  param([string]$Repo,[hashtable]$Headers)
  Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/releases/latest" -f $Repo) -Headers $Headers -UseBasicParsing
}

function Get-InstalledVersion { param([string]$Name)
  $m = Get-Module $Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
  if ($m) { [Version]$m.Version } else { [Version]'0.0.0' }
}

function Get-UserModulePaths {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  @(
    (Join-Path $docs 'WindowsPowerShell\Modules'),  # PS 5.1
    (Join-Path $docs 'PowerShell\Modules')          # PS 7+
  )
}

function Install-ModuleFromZip {
  param([string]$ZipUrl,[string]$AssetName,[hashtable]$Headers,[string]$Name)

  $tmp = Join-Path $env:TEMP ("{0}-{1:yyyyMMddHHmmss}" -f $Name,(Get-Date))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp $AssetName

  Invoke-WebRequest -Uri $ZipUrl -Headers $Headers -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath $tmp -Force

  # Find the folder that actually contains <Name>.psd1
  $root = Join-Path $tmp $Name
  if (-not (Test-Path (Join-Path $root "$Name.psd1"))) {
    $cand = Get-ChildItem $tmp -Directory -Recurse |
      Where-Object { Test-Path (Join-Path $_.FullName "$Name.psd1") } |
      Select-Object -First 1
    if ($cand) { $root = $cand.FullName } else { throw "Could not find $Name.psd1 in ZIP" }
  }

  foreach ($destRoot in (Get-UserModulePaths)) {
    if (-not (Test-Path $destRoot)) { New-Item -ItemType Directory -Path $destRoot | Out-Null }
    $dest = Join-Path $destRoot $Name

    # Ensure destination *exists* before copying contents
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest | Out-Null

    # Copy the CONTENTS of the module root (psd1/psm1/Public/Private/…)
    Copy-Item -Path (Join-Path $root '*') -Destination $dest -Recurse -Force
    Write-Info "Installed to $dest"
  }

  try { Remove-Item $tmp -Recurse -Force } catch {}
}

Write-Info "Checking latest release for $Repo ..."
$rel = Get-LatestRelease -Repo $Repo -Headers $headers
$asset = $rel.assets | Where-Object { $_.name -like "$ModuleName-*.zip" } | Select-Object -First 1
if (-not $asset) { throw "No '$ModuleName-*.zip' asset found on latest release." }

$latest    = [Version]($rel.tag_name.TrimStart('v'))
$installed = Get-InstalledVersion -Name $ModuleName

if ($installed -lt $latest) {
  Write-Info "Updating $ModuleName $installed -> $latest ..."
  Install-ModuleFromZip -ZipUrl $asset.browser_download_url -AssetName $asset.name -Headers $headers -Name $ModuleName
  Write-Ok "$ModuleName $latest installed."
} else {
  Write-Ok "$ModuleName is up to date ($installed)."
}

# Import by *path* so we don't depend on PSModulePath quirks/OneDrive redirects
$moduleDirs = Get-UserModulePaths | ForEach-Object { Join-Path $_ $ModuleName }
$installBase = $moduleDirs | Where-Object { Test-Path (Join-Path $_ "$ModuleName.psd1") } | Select-Object -First 1

if ($installBase) {
  Import-Module (Join-Path $installBase "$ModuleName.psd1") -Force
  Write-Ok "$ModuleName loaded from $installBase"
} else {
  # Fallback: try by name after adding user paths
  foreach ($p in (Get-UserModulePaths)) {
    if ($env:PSModulePath -notlike "*$p*") { $env:PSModulePath += ";$p" }
  }
  Import-Module $ModuleName -Force
  Write-Ok "$ModuleName loaded (by name)"
}
