<# KXGT-Bootstrap.ps1
   One-shot installer/updater for Koronet-Axerrio.GitTools from GitHub Releases.
   - Installs for current user (no admin)
   - Works with public or private repos (set -PrivateRepo or $env:GITHUB_TOKEN)
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
function Write-Ok([string]$m){ if(-not $Quiet){ Write-Host $m -ForegroundColor Green } }
function Write-Wrn([string]$m){ if(-not $Quiet){ Write-Warning $m } }

$headers = @{ 'User-Agent' = 'KXGT-Bootstrap' }
if ($PrivateRepo) {
  if (-not $env:GITHUB_TOKEN) {
    Write-Info "Private repo selected. Enter a GitHub PAT with repo read access."
    $sec = Read-Host -AsSecureString "GitHub PAT"
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    $env:GITHUB_TOKEN = $plain
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
  @(
    Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules';
    Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'
  )
}
function Install-ModuleFromZip {
  param([string]$ZipUrl,[string]$AssetName,[hashtable]$Headers,[string]$Name)
  $tmp = Join-Path $env:TEMP ("{0}-{1:yyyyMMddHHmmss}" -f $Name,(Get-Date))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp $AssetName
  Invoke-WebRequest -Uri $ZipUrl -Headers $Headers -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $root = Join-Path $tmp $Name
  if (-not (Test-Path (Join-Path $root "$Name.psd1"))) {
    $cand = Get-ChildItem $tmp -Directory -Recurse |
      Where-Object { Test-Path (Join-Path $_.FullName "$Name.psd1") } | Select-Object -First 1
    if ($cand) { $root = $cand.FullName } else { throw "Could not find $Name.psd1 in ZIP" }
  }
  foreach ($destRoot in (Get-UserModulePaths)) {
    if (-not (Test-Path $destRoot)) { New-Item -ItemType Directory -Path $destRoot | Out-Null }
    $dest = Join-Path $destRoot $Name
    Remove-Module $Name -ErrorAction SilentlyContinue
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $root -Destination $dest -Recurse -Force
  }
  try { Remove-Item $tmp -Recurse -Force } catch {}
}

Write-Info "Checking latest release for $Repo ..."
$rel = Get-LatestRelease -Repo $Repo -Headers $headers
$asset = $rel.assets | Where-Object { $_.name -like "$ModuleName-*.zip" } | Select-Object -First 1
if (-not $asset) { throw "No '$ModuleName-*.zip' asset found on latest release." }

$latest = [Version]($rel.tag_name.TrimStart('v'))
$installed = Get-InstalledVersion -Name $ModuleName

if ($installed -lt $latest) {
  Write-Info "Updating $ModuleName $installed -> $latest ..."
  Install-ModuleFromZip -ZipUrl $asset.browser_download_url -AssetName $asset.name -Headers $headers -Name $ModuleName
  Write-Ok "$ModuleName $latest installed."
} else {
  Write-Ok "$ModuleName is up to date ($installed)."
}

Import-Module $ModuleName -Force
Write-Ok "$ModuleName loaded."
