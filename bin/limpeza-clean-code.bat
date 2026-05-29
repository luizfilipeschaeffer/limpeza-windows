@echo off
setlocal

:: Launcher Clean Code: dist\LimpezaWindows-CleanCode.exe ou src\limpeza.ps1
set "ROOT_DIR=%~dp0..\"
set "APP_EXE=%ROOT_DIR%dist\LimpezaWindows-CleanCode.exe"
set "PS_SCRIPT=%ROOT_DIR%src\limpeza.ps1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

chcp 65001 >nul 2>&1

if exist "%APP_EXE%" (
    net session >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo   Solicitando elevacao para LimpezaWindows-CleanCode.exe...
        timeout /t 1 >nul
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%APP_EXE%' -Verb RunAs -WorkingDirectory '%ROOT_DIR%dist'"
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
    echo   Solicitando elevacao...
    timeout /t 2 >nul
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:LIMPEZA_PRODUCT_EDITION='CleanCode'; Start-Process -FilePath '%PS_EXE%' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%PS_SCRIPT%\"') -Verb RunAs -WorkingDirectory '%ROOT_DIR%'"
    exit /b 0
)

set "LIMPEZA_PRODUCT_EDITION=CleanCode"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
exit /b %errorlevel%
