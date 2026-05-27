@echo off
setlocal
chcp 65001 >nul 2>&1
echo.
echo   Baixando ultima versao do GitHub...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-latest-release.ps1"
echo.
pause
exit /b %errorlevel%
