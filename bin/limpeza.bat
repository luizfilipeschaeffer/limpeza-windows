@echo off
setlocal

:: Launcher: prefer C:\Windows\LimpezaWindows.exe, senao dist\ ou src\
set "ROOT_DIR=%~dp0..\"
set "APP_EXE=%SystemRoot%\LimpezaWindows.exe"
set "FALLBACK_EXE=%ROOT_DIR%dist\LimpezaWindows.exe"
set "PS_SCRIPT=%ROOT_DIR%src\limpeza.ps1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

chcp 65001 >nul 2>&1

if not exist "%APP_EXE%" set "APP_EXE=%FALLBACK_EXE%"

if exist "%APP_EXE%" (
    net session >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo   Solicitando elevacao para LimpezaWindows.exe...
        timeout /t 1 >nul
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%APP_EXE%' -Verb RunAs -WorkingDirectory '%SystemRoot%'"
        exit /b 0
    )
    start "" "%APP_EXE%"
    exit /b 0
)

if not exist "%PS_SCRIPT%" (
    echo.
    echo   [ERRO] Nenhum executavel ou script encontrado em:
    echo          %ROOT_DIR%
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ======================================================
    echo        PERMISSAO DE ADMINISTRADOR NECESSARIA
    echo   ======================================================
    echo.
    echo   Este script precisa ser executado como Administrador.
    echo.
    echo   [i] Uma janela PowerShell sera aberta apos o UAC.
    echo   [i] Esta janela fechara automaticamente - isso e normal.
    echo.
    echo   Solicitando elevacao...
    timeout /t 2 >nul
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%PS_EXE%' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%PS_SCRIPT%\"') -Verb RunAs -WorkingDirectory '%ROOT_DIR%'"
    exit /b 0
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
exit /b %errorlevel%
