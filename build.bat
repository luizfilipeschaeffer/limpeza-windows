@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-limpeza.ps1"
exit /b %errorlevel%
