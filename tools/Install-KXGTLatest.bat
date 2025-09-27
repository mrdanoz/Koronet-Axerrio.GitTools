@echo off
setlocal

REM === EDIT this if your repo path changes ===
set "REPO=mrdanoz/Koronet-Axerrio.GitTools"
set "MOD=Koronet-Axerrio.GitTools"

set "PSFILE=%TEMP%\KXGT-InstallFromRelease.ps1"

where /q pwsh.exe
if %ERRORLEVEL%==0 ( set "PSBIN=pwsh.exe" ) else ( set "PSBIN=powershell.exe" )

> "%PSFILE%" echo $ErrorActionPreference = 'Stop'
>>"%PSFILE%" echo $repo  = '%REPO%'
>>"%PSFILE%" echo $mod   = '%MOD%'
>>"%PSFILE%" echo $ua    = @{ 'User-Agent' = 'KXGT-Installer' }
>>"%PSFILE%" echo Write-Host "Installing from latest release of $repo ..." -ForegroundColor Cyan
>>"%PSFILE%" echo try {
>>"%PSFILE%" echo ^  $latest = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers $ua
>>"%PSFILE%" echo } catch {
>>"%PSFILE%" echo ^  if ($_.Exception.Response.StatusCode.value__ -eq 404) {
>>"%PSFILE%" echo ^    Write-Host "No /latest endpoint. Falling back to /releases ..." -ForegroundColor Yellow
>>"%PSFILE%" echo ^    $rels = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=5" -Headers $ua
>>"%PSFILE%" echo ^    if (-not $rels) { throw "No releases found for $repo." }
>>"%PSFILE%" echo ^    $latest = ($rels ^| Where-Object { -not $_.prerelease } ^| Select-Object -First 1)
>>"%PSFILE%" echo ^    if (-not $latest) { $latest = $rels ^| Select-Object -First 1 }
>>"%PSFILE%" echo ^  } else { throw }
>>"%PSFILE%" echo }
>>"%PSFILE%" echo if (-not $latest) { throw "Unable to resolve a release for $repo." }
>>"%PSFILE%" echo $tag = ($latest.tag_name ?? $latest.name)
>>"%PSFILE%" echo Write-Host "Using release: $tag"
>>"%PSFILE%" echo $asset = $latest.assets ^| Where-Object { $_.name -match "^$mod-.*\.zip$" } ^| Select-Object -First 1
>>"%PSFILE%" echo if (-not $asset) { throw "No ZIP asset named like '$mod-*.zip' on release $tag." }
>>"%PSFILE%" echo $zip  = Join-Path $env:TEMP $asset.name
>>"%PSFILE%" echo Write-Host "Downloading $($asset.name) ..." -ForegroundColor Cyan
>>"%PSFILE%" echo Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers $ua
>>"%PSFILE%" echo Unblock-File -Path $zip -ErrorAction SilentlyContinue
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Extract to a temp work dir
>>"%PSFILE%" echo $work = Join-Path $env:TEMP "KXGT_Extract_$([Guid]::NewGuid().ToString('N'))"
>>"%PSFILE%" echo New-Item -ItemType Directory -Path $work ^| Out-Null
>>"%PSFILE%" echo Expand-Archive -Path $zip -DestinationPath $work -Force
>>"%PSFILE%" echo Remove-Item $zip -Force
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Find the actual module .psd1 anywhere inside the ZIP contents
>>"%PSFILE%" echo $psd1 = Get-ChildItem -Path $work -Recurse -Filter "$mod.psd1" -ErrorAction SilentlyContinue ^| Select-Object -First 1
>>"%PSFILE%" echo if (-not $psd1) {
>>"%PSFILE%" echo ^  throw "Could not find $mod.psd1 inside the archive. Structure unexpected. WorkDir: $work"
>>"%PSFILE%" echo }
>>"%PSFILE%" echo $moduleBaseCandidate = $psd1.DirectoryName
>>"%PSFILE%" echo Write-Host "Module base found: $moduleBaseCandidate"
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Decide target modules root (user-scope)
>>"%PSFILE%" echo $modulesRoot = if ($PSVersionTable.PSEdition -eq 'Core') {
>>"%PSFILE%" echo ^  Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'
>>"%PSFILE%" echo } else {
>>"%PSFILE%" echo ^  Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
>>"%PSFILE%" echo }
>>"%PSFILE%" echo if (-not (Test-Path $modulesRoot)) { New-Item -ItemType Directory -Path $modulesRoot ^| Out-Null }
>>"%PSFILE%" echo $dest = Join-Path $modulesRoot $mod
>>"%PSFILE%" echo Write-Host "Installing to: $dest" -ForegroundColor Cyan
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Clean any previous install at dest
>>"%PSFILE%" echo if (Test-Path $dest) {
>>"%PSFILE%" echo ^  try { Remove-Item -LiteralPath $dest -Recurse -Force } catch { }
>>"%PSFILE%" echo }
>>"%PSFILE%" echo New-Item -ItemType Directory -Path $dest ^| Out-Null
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Copy module files from whatever nested folder to the exact dest
>>"%PSFILE%" echo Copy-Item -Path (Join-Path $moduleBaseCandidate '*') -Destination $dest -Recurse -Force
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Cleanup the temp extraction
>>"%PSFILE%" echo Remove-Item -LiteralPath $work -Recurse -Force
>>"%PSFILE%" echo
>>"%PSFILE%" echo # Import from exact path so we don't depend on PSModulePath immediately
>>"%PSFILE%" echo $psd1Dest = Join-Path $dest "$mod.psd1"
>>"%PSFILE%" echo if (-not (Test-Path -LiteralPath $psd1Dest)) {
>>"%PSFILE%" echo ^  throw "Installed module missing psd1 at $psd1Dest"
>>"%PSFILE%" echo }
>>"%PSFILE%" echo Import-Module $psd1Dest -Force
>>"%PSFILE%" echo Write-Host "Installed and imported: $mod" -ForegroundColor Green
>>"%PSFILE%" echo Get-Command -Module $mod ^| Select-Object Name, Version ^| Format-Table -Auto

echo.
echo Repo:  %REPO%
echo Using: %PSBIN%
echo.

"%PSBIN%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
set "RC=%ERRORLEVEL%"
del "%PSFILE%" >nul 2>&1

echo.
if "%RC%"=="0" (
  echo ✅ Install complete.
) else (
  echo ❌ Install failed with exit code %RC%.
)

endlocal
