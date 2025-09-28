@echo off
setlocal EnableExtensions
set "HERE=%~dp0"
set "PS1=%HERE%New-KXGTFeatureBranch.wrapper.ps1"

where pwsh >nul 2>&1 && (
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
) || (
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
)
exit /b %ERRORLEVEL%
