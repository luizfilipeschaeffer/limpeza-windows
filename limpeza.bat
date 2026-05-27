@echo off
setlocal

:: Launcher: executa dist\LimpezaWindows.exe ou src\limpeza.ps1
set "SCRIPT_DIR=%~dp0"
set "APP_EXE=%SCRIPT_DIR%dist\LimpezaWindows.exe"
set "PS_SCRIPT=%SCRIPT_DIR%src\limpeza.ps1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

chcp 65001 >nul 2>&1

if exist "%APP_EXE%" (
    net session >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo   Solicitando elevacao para LimpezaWindows.exe...
        timeout /t 1 >nul
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%APP_EXE%' -Verb RunAs -WorkingDirectory '%SCRIPT_DIR%'"
        exit /b 0
    )
    start "" "%APP_EXE%"
    exit /b 0
)

if not exist "%PS_SCRIPT%" (
    echo.
    echo   [ERRO] Nenhum executavel ou script encontrado em:
    echo          %SCRIPT_DIR%
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
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%PS_EXE%' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%PS_SCRIPT%\"') -Verb RunAs -WorkingDirectory '%SCRIPT_DIR%'"
    exit /b 0
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
exit /b %errorlevel%
