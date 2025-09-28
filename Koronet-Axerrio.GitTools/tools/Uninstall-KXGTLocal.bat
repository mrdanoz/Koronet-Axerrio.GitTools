@echo off
setlocal

REM ---------------------------------------------------------------------------
REM Uninstall-KXGTLocal.bat
REM Wrapper to run the PowerShell uninstaller for Koronet-Axerrio.GitTools
REM ---------------------------------------------------------------------------

set "PS_SCRIPT=Uninstall-KXGTLocal.ps1"

if not exist "%~dp0%PS_SCRIPT%" (
  echo ❌ Cannot find "%PS_SCRIPT%" in "%~dp0"
  echo Make sure this BAT file is in the same folder as the PowerShell script.
  exit /b 1
)

REM Prefer PowerShell 7 (pwsh) if available
where /q pwsh.exe
if %ERRORLEVEL%==0 (
  set "PSBIN=pwsh.exe"
) else (
  set "PSBIN=powershell.exe"
)

echo.
echo === Running %PS_SCRIPT% ===
echo Using: %PSBIN%
echo.

"%PSBIN%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0%PS_SCRIPT%" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo ✅ Uninstall complete.
) else (
  echo ❌ Uninstall failed with exit code %RC%.
)

endlocal
