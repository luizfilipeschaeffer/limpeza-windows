#Requires -RunAsAdministrator
# Limpeza Avancada do Windows v2.0.0
# Autor: Luiz Filipe Schaeffer

$AppVersion = '2.0.0'
$GitHubRepo = 'luizfilipeschaeffer/limpeza-windows'

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Initialize-Console {
    try { chcp 65001 | Out-Null } catch {}
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding  = $utf8
    $global:OutputEncoding    = $utf8
    $Host.UI.RawUI.WindowTitle = "$(E 0x1F9F9) Limpeza Avancada do Windows v2.0"
    Clear-Host
}

function E([int]$CodePoint) {
    [char]::ConvertFromUtf32($CodePoint)
}

function Show-GitHubUpdateNotice {
    param([string]$CurrentVersion = $AppVersion)

    try {
        $release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" `
            -Headers @{ 'User-Agent' = 'LimpezaWindows'; 'Accept' = 'application/vnd.github+json' } `
            -TimeoutSec 8 `
            -UseBasicParsing
        $latest = ($release.tag_name -replace '^v', '').Trim()
        if ([version]$latest -gt [version]$CurrentVersion) {
            Write-Host ''
            Write-Host "   $(E 0x1F4E5) Nova versao disponivel: v$latest (voce usa v$CurrentVersion)" -ForegroundColor Yellow
            Write-Host "       $($release.html_url)" -ForegroundColor DarkCyan
            Write-Host "       Ou execute atualizar.bat na pasta do projeto." -ForegroundColor DarkGray
            Write-Host ''
        }
    }
    catch {
        # Sem rede ou sem releases — segue normalmente
    }
}

function Write-Banner {
    param([string[]]$Lines, [ConsoleColor]$Color = 'Cyan')
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor $Color
    foreach ($line in $Lines) { Write-Host "  $line" -ForegroundColor $Color }
    Write-Host '  ======================================================' -ForegroundColor $Color
    Write-Host ''
}

function Show-IntroAnimation {
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan

    $icons = @(
        (E 0x1F9F9), (E 0x2728), (E 0x1F4BE), (E 0x1F680)
    )
    for ($i = 0; $i -lt 12; $i++) {
        Write-Host -NoNewline "  $($icons[$i % 4]) "
        Start-Sleep -Milliseconds 70
    }
    Write-Host ''
    Write-Host ("        $(E 0x1F9F9)  LIMPEZA AVANCADA DO WINDOWS  $(E 0x1F9F9)") -ForegroundColor Green
    Write-Host ("        $(E 0x2728)  Manutencao e liberacao de espaco  $(E 0x2728)") -ForegroundColor DarkCyan
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''

    Write-Host -NoNewline "  $(E 0x23F3) Preparando "
    1..18 | ForEach-Object {
        Write-Host -NoNewline ([char]0x2588) -ForegroundColor Yellow
        Start-Sleep -Milliseconds 35
    }
    Write-Host " $(E 0x2705)" -ForegroundColor Green
    Write-Host ''
}

function Show-Spinner {
    param([string]$Message)
    $frames = @('|', '/', '-', '\')
    for ($i = 0; $i -lt 12; $i++) {
        Write-Host -NoNewline ("`r       $($frames[$i % 4]) $Message...")
        Start-Sleep -Milliseconds 90
    }
    Write-Host ("`r" + (' ' * 60) + "`r") -NoNewline
}

function Write-StepHeader {
    param(
        [int]$Number,
        [int]$Total,
        [int]$Icon,
        [string]$Title
    )
    Write-Host ''
    Write-Host "   $(E $Icon)  [$Number/$Total] $Title"
    Write-Host '        ----------------------------------------'
}

function Write-StepResult {
    param(
        [int]$ExitCode,
        [string]$WarningMessage = 'Alguns arquivos nao puderam ser removidos.'
    )
    if ($ExitCode -ge 8) {
        Write-Host "       $(E 0x26A0)  [AVISO] $WarningMessage" -ForegroundColor Yellow
    }
    else {
        Write-Host "       $(E 0x2705) [OK] Concluido" -ForegroundColor Green
    }
}

function Invoke-RobocopyClean {
    param([string]$TargetPath)
    $empty = Join-Path $env:TEMP 'EMPTY_FOLDER'
    if (-not (Test-Path $empty)) {
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
    }
    & robocopy $empty $TargetPath /MIR /R:0 /W:0 | Out-Null
    return $LASTEXITCODE
}

function Get-DriveCFreeBytes {
    (Get-PSDrive C).Free
}

function Show-FinalResult {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter,
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    $culture = [cultureinfo]::GetCultureInfo('pt-BR')
    $gained  = [math]::Max(0, $FreeAfter - $FreeBefore)

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ("           $(E 0x1F389)  RESULTADO FINAL  $(E 0x1F389)") -ForegroundColor Green
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("  $(E 0x1F4C9) Antes  : {0} GB livres" -f (($FreeBefore / 1GB).ToString('N2', $culture))) -ForegroundColor DarkYellow
    Write-Host ("  $(E 0x1F4C8) Depois : {0} GB livres" -f (($FreeAfter / 1GB).ToString('N2', $culture))) -ForegroundColor Green
    Write-Host ''

    if ($gained -gt 0) {
        Write-Host ("  $(E 0x1F680) Espaco livre com a limpeza: +{0} GB" -f (($gained / 1GB).ToString('N2', $culture))) -ForegroundColor Green
    }
    else {
        Write-Host ("  $(E 0x1F4CA) Espaco ganho com a limpeza: {0} GB" -f (($gained / 1GB).ToString('N2', $culture))) -ForegroundColor DarkGray
        Write-Host "  $(E 0x1F4A1) (nenhum ganho mensuravel — arquivos em uso ou disco ja limpo)" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "       $(E 0x1F464) Autor   : Luiz Filipe Schaeffer"
    Write-Host "       $(E 0x1F4CC) Versao  : $AppVersion"
    Write-Host ("       $(E 0x1F550) Inicio  : {0}" -f $StartTime.ToString('dd/MM/yyyy HH:mm:ss'))
    Write-Host ("       $(E 0x1F3C1) Termino : {0}" -f $EndTime.ToString('dd/MM/yyyy HH:mm:ss'))
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host "   $(E 0x1F44B) Pressione qualquer tecla para sair..."
    Write-Host ''
}

# --- Execucao principal ---

Initialize-Console
Show-IntroAnimation
Show-GitHubUpdateNotice

$startTime  = Get-Date
$freeBefore = Get-DriveCFreeBytes
$gbFree     = [math]::Round($freeBefore / 1GB, 2)
$drive      = Get-PSDrive C
$total      = $drive.Used + $drive.Free
$percentFree = if ($total -gt 0) { [math]::Round(($freeBefore / $total) * 100, 1) } else { 0 }

Write-Host "       $(E 0x1F464) Autor   : Luiz Filipe Schaeffer"
Write-Host "       $(E 0x1F4CC) Versao  : $AppVersion"
Write-Host ("       $(E 0x1F550) Inicio  : {0}" -f $startTime.ToString('dd/MM/yyyy HH:mm:ss'))
Write-Host ''
Write-Host "   $(E 0x1F4BF) Disco C:"
Write-Host "     $(E 0x1F4CA) Livre agora : $gbFree GB  ($percentFree% livre)"
Write-Host ''

$emptyFolder = Join-Path $env:TEMP 'EMPTY_FOLDER'
if (-not (Test-Path $emptyFolder)) {
    New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null
}

# [1/6] TEMP do Windows
Write-StepHeader -Number 1 -Total 6 -Icon 0x1F5D1 -Title 'TEMP do Windows'
Show-Spinner 'Varrendo arquivos temporarios'
$code = Invoke-RobocopyClean -TargetPath "$env:windir\Temp"
Write-StepResult -ExitCode $code

# [2/6] TEMP do usuario
Write-StepHeader -Number 2 -Total 6 -Icon 0x1F4C1 -Title 'TEMP do usuario'
Show-Spinner 'Limpando pasta TEMP do usuario'
$code = Invoke-RobocopyClean -TargetPath $env:TEMP
Write-StepResult -ExitCode $code

# [3/6] Prefetch
Write-StepHeader -Number 3 -Total 6 -Icon 0x26A1 -Title 'Prefetch'
Show-Spinner 'Otimizando cache Prefetch'
$code = Invoke-RobocopyClean -TargetPath "$env:windir\Prefetch"
Write-StepResult -ExitCode $code

# [4/6] Windows Installer
Write-StepHeader -Number 4 -Total 6 -Icon 0x1F4E6 -Title 'Windows Installer (agressivo)'
Show-Spinner 'Removendo residuos do Installer'
$installer = Join-Path $env:windir 'Installer'
& takeown /f $installer /r /d y 2>$null | Out-Null
& icacls $installer /grant administrators:F /t 2>$null | Out-Null
& attrib -h -r -s "$installer\*.*" /s /d 2>$null | Out-Null
Get-ChildItem -Path $installer -Recurse -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-StepResult -ExitCode 0

# [5/6] DISM
Write-StepHeader -Number 5 -Total 6 -Icon 0x1F527 -Title 'Componentes do Windows (DISM)'
Show-Spinner 'Analisando repositorio de componentes'
$dismOut = & Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
if ($dismOut -match 'Limpeza do Repositorio de Componentes Recomendada\s*:\s*Sim') {
    Write-Host "       $(E 0x1F525) Limpeza recomendada. Executando..." -ForegroundColor Yellow
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
}
else {
    Write-Host "       $(E 0x2728) Nenhuma limpeza necessaria no momento." -ForegroundColor DarkGray
}
Write-StepResult -ExitCode $LASTEXITCODE

# [6/6] cleanmgr
Write-StepHeader -Number 6 -Total 6 -Icon 0x1F4BF -Title 'Limpeza de Disco (cleanmgr)'
Write-Host "       $(E 0x1FA9F) Abrindo o assistente..."
Write-Host ''
& cleanmgr /sagerun:1
Write-StepResult -ExitCode $LASTEXITCODE

$freeAfter = Get-DriveCFreeBytes
$endTime   = Get-Date

Show-FinalResult -FreeBefore $freeBefore -FreeAfter $freeAfter -StartTime $startTime -EndTime $endTime

if (Test-Path $emptyFolder) {
    Remove-Item -Path $emptyFolder -Recurse -Force -ErrorAction SilentlyContinue
}

$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
