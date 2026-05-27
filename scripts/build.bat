@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-limpeza.ps1"
exit /b %errorlevel%
