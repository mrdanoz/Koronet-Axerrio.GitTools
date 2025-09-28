@echo off
setlocal

REM -----------------------------------------------------------------------------
REM Install-KXGTLatest.bat
REM - Calls the KXGT-Bootstrap.ps1 script (local if present, otherwise download).
REM - No inline PowerShell runner; we always execute the bootstrap script file.
REM -----------------------------------------------------------------------------

REM ====== EDIT DEFAULTS HERE IF NEEDED ======
set "REPO=mrdanoz/Koronet-Axerrio.GitTools"
set "BOOTSTRAP_REL=tools\KXGT-Bootstrap.ps1"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/%REPO%/main/tools/KXGT-Bootstrap.ps1"
REM You can add default flags here, e.g.: set "BOOTSTRAP_FLAGS=-Repo %REPO%"
set "BOOTSTRAP_FLAGS=-Repo %REPO%"
REM ==========================================

REM Choose PowerShell: prefer pwsh (7+) if available
where /q pwsh.exe
if %ERRORLEVEL%==0 (
  set "PSBIN=pwsh.exe"
) else (
  set "PSBIN=powershell.exe"
)

REM Resolve script location
set "HERE=%~dp0"
set "LOCAL_BOOTSTRAP=%HERE%%BOOTSTRAP_REL%"
set "TEMP_BOOTSTRAP=%TEMP%\KXGT-Bootstrap.ps1"

echo.
echo === Installing Koronet-Axerrio.GitTools (latest) ===
echo Using:   %PSBIN%
echo Repo:    %REPO%
echo.

REM 1) Prefer local bootstrap next to this BAT
if exist "%LOCAL_BOOTSTRAP%" (
  echo Found local bootstrap: "%LOCAL_BOOTSTRAP%"
  "%PSBIN%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_BOOTSTRAP%" %BOOTSTRAP_FLAGS% %*
  goto :done
)

REM 2) Otherwise download bootstrap to temp, then execute it
echo Local bootstrap not found at "%LOCAL_BOOTSTRAP%"
echo Downloading bootstrap from:
echo   %BOOTSTRAP_URL%
echo.

"%PSBIN%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "Invoke-WebRequest -Uri '%BOOTSTRAP_URL%' -OutFile '%TEMP_BOOTSTRAP%';" ^
  "Unblock-File -Path '%TEMP_BOOTSTRAP%' -ErrorAction SilentlyContinue;"

if not exist "%TEMP_BOOTSTRAP%" (
  echo ❌ Failed to download bootstrap to "%TEMP_BOOTSTRAP%"
  exit /b 1
)

"%PSBIN%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TEMP_BOOTSTRAP%" %BOOTSTRAP_FLAGS% %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo ✅ Install complete.
) else (
  echo ❌ Install failed with exit code %RC%.
)

:done
endlocal
