@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM --- CONFIG ---
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/<org>/<repo>/main/KXGT-bootstrap.ps1"
set "BOOTSTRAP_NAME=KXGT-bootstrap.ps1"

REM --- Choose shell: prefer pwsh (PS7), else Windows PowerShell ---
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  set "PS_EXEC=pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command"
) else (
  where powershell >nul 2>&1
  if %ERRORLEVEL%==0 (
    set "PS_EXEC=powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command"
  ) else (
    echo [ERR] Neither pwsh nor powershell found on PATH.
    exit /b 1
  )
)

REM --- Decide temp path ---
if not defined TEMP set "TEMP=%USERPROFILE%\AppData\Local\Temp"
if not exist "%TEMP%" md "%TEMP%" >nul 2>&1

set "BOOTSTRAP_PATH=%TEMP%\%BOOTSTRAP_NAME%"
echo [INF] Downloading bootstrap to: "%BOOTSTRAP_PATH%"
echo [INF] From: %BOOTSTRAP_URL%

REM --- Download with forced TLS 1.2 and robust error handling ---
%PS_EXEC% ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12;" ^
  "$u='%BOOTSTRAP_URL%';" ^
  "$o='%BOOTSTRAP_PATH%';" ^
  "try { Invoke-WebRequest -Uri $u -UseBasicParsing -OutFile $o } catch { Write-Error ('DOWNLOAD_FAIL: ' + $_.Exception.Message); exit 9 }" 
if %ERRORLEVEL% NEQ 0 (
  echo [ERR] Failed to download bootstrap to "%BOOTSTRAP_PATH%".
  echo [TIP] On Windows Server 2012 R2 this is usually missing TLS 1.2 or a proxy blocking HTTPS.
  exit /b %ERRORLEVEL%
)

REM --- Sanity check ---
if not exist "%BOOTSTRAP_PATH%" (
  echo [ERR] Download reported success but file is missing: "%BOOTSTRAP_PATH%"
  exit /b 2
)

REM --- Execute bootstrap with PS7 if available (same shell as chosen above) ---
echo [INF] Running bootstrap...
%PS_EXEC% ^
  "$ErrorActionPreference='Stop';" ^
  "& '%BOOTSTRAP_PATH%'" 
set ERR=%ERRORLEVEL%
if %ERR% NEQ 0 (
  echo [ERR] Bootstrap execution failed with exit code %ERR%.
  exit /b %ERR%
)

echo [OK] KXGT bootstrap completed successfully.
exit /b 0
