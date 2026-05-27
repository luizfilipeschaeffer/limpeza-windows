#Requires -RunAsAdministrator
# Limpeza Avancada do Windows v2.0.1
# Autor: Luiz Filipe Schaeffer

$AppVersion = '2.0.1'
$GitHubRepo = 'luizfilipeschaeffer/limpeza-windows'

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Initialize-Console {
    try { chcp 65001 | Out-Null } catch {}
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding  = $utf8
    $global:OutputEncoding    = $utf8
    $Host.UI.RawUI.WindowTitle = "$(E 0x1F9F9) Limpeza Avancada do Windows v$AppVersion"
    Clear-Host
}

function E([int]$CodePoint) {
    [char]::ConvertFromUtf32($CodePoint)
}

$script:GitHubApiHeaders = @{
    'User-Agent' = 'LimpezaWindows'
    'Accept'     = 'application/vnd.github+json'
}
$script:UpdateAssetName = 'LimpezaWindows.exe'

function Get-AppInstallInfo {
    $runningExe = $PSCommandPath -match '\.exe$'
    if ($runningExe) {
        $exePath = $PSCommandPath
        $version = $AppVersion
        if (Test-Path $exePath) {
            $fileVersion = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
            if ($fileVersion) {
                $parts = $fileVersion.Split('.')
                $version = if ($parts.Count -ge 3) {
                    "$($parts[0]).$($parts[1]).$($parts[2])"
                } else {
                    $fileVersion
                }
            }
        }
        return [PSCustomObject]@{
            Mode             = 'exe'
            ExecutablePath   = $exePath
            InstallDirectory = Split-Path $exePath -Parent
            CurrentVersion   = $version
        }
    }

    $projectRoot = Split-Path $PSScriptRoot -Parent
    $exePath = Join-Path $projectRoot "dist\$script:UpdateAssetName"
    return [PSCustomObject]@{
        Mode             = 'script'
        ExecutablePath   = $exePath
        InstallDirectory = $projectRoot
        CurrentVersion   = $AppVersion
    }
}

function Get-GitHubLatestRelease {
    $uri = "https://api.github.com/repos/$GitHubRepo/releases/latest"
    $release = Invoke-RestMethod -Uri $uri -Headers $script:GitHubApiHeaders -TimeoutSec 12 -UseBasicParsing
    $version = ($release.tag_name -replace '^v', '').Trim()
    $asset = $release.assets | Where-Object { $_.name -eq $script:UpdateAssetName } | Select-Object -First 1
    if (-not $asset) {
        throw "Arquivo '$($script:UpdateAssetName)' nao encontrado na release $($release.tag_name)."
    }
    [PSCustomObject]@{
        Version      = $version
        Tag          = $release.tag_name
        DownloadUrl  = $asset.browser_download_url
        ReleaseUrl   = $release.html_url
        PublishedAt  = $release.published_at
    }
}

function Read-UpdateChoice {
    while ($true) {
        Write-Host ''
        Write-Host "   $(E 0x2753)  [S] Sim — baixar e reiniciar com a nova versao" -ForegroundColor White
        Write-Host "   $(E 0x23ED)  [N] Nao — continuar a limpeza agora" -ForegroundColor White
        Write-Host ''
        Write-Host -NoNewline '   Digite S ou N e pressione Enter: ' -ForegroundColor Yellow

        $answer = (Read-Host).Trim().ToUpperInvariant()
        if ($answer -in @('S', 'SIM', 'Y', 'YES')) { return $true }
        if ($answer -in @('N', 'NAO', 'NÃO', 'NO')) { return $false }
        Write-Host '   Opcao invalida. Use S para atualizar ou N para continuar.' -ForegroundColor Red
    }
}

function Start-AppUpdateAndRestart {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Release,

        [Parameter(Mandatory = $true)]
        [object]$Install
    )

    $targetExe = $Install.ExecutablePath
    $targetDir = $Install.InstallDirectory
    New-Item -ItemType Directory -Path (Split-Path $targetExe -Parent) -Force | Out-Null

    $stagingExe = Join-Path $env:TEMP "LimpezaWindows-$([guid]::NewGuid().ToString('N')).exe"
    Write-Host ''
    Write-Host "   $(E 0x1F4E5) Baixando $($script:UpdateAssetName) v$($Release.Version)..." -ForegroundColor Cyan
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $stagingExe -UseBasicParsing
    }
    finally {
        $ProgressPreference = $prevProgress
    }

    if (-not (Test-Path $stagingExe)) {
        throw 'Download da atualizacao falhou.'
    }

    $pidAtStart = $PID
    $helperPs1 = Join-Path $env:TEMP "limpeza-updater-$([guid]::NewGuid().ToString('N')).ps1"
    $helperContent = @"
`$ErrorActionPreference = 'Stop'
`$staging = '$($stagingExe.Replace("'", "''"))'
`$target = '$($targetExe.Replace("'", "''"))'
`$workDir = '$($targetDir.Replace("'", "''"))'
`$parentPid = $pidAtStart

try {
    Wait-Process -Id `$parentPid -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Seconds 2

if (Test-Path `$target) {
    Remove-Item -LiteralPath `$target -Force -ErrorAction SilentlyContinue
    `$retries = 0
    while ((Test-Path `$target) -and (`$retries -lt 15)) {
        Start-Sleep -Milliseconds 400
        `$retries++
    }
}
Move-Item -LiteralPath `$staging -Destination `$target -Force
Start-Process -FilePath `$target -WorkingDirectory `$workDir
"@
    Set-Content -Path $helperPs1 -Value $helperContent -Encoding UTF8

    Write-Host "   $(E 0x2705) Download concluido. Reiniciando com v$($Release.Version)..." -ForegroundColor Green
    Write-Host '   A limpeza iniciara automaticamente na nova versao.' -ForegroundColor DarkGray
    Write-Host ''

    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $helperPs1) `
        -WindowStyle Hidden

    exit 0
}

function Invoke-AppUpdateCheck {
    if ($env:LIMPEZA_SKIP_UPDATE -eq '1') { return }

    $install = Get-AppInstallInfo
    $currentVersion = $install.CurrentVersion

    try {
        $release = Get-GitHubLatestRelease
    }
    catch {
        Write-Host ''
        Write-Host "   $(E 0x26A0) Nao foi possivel verificar atualizacoes. Continuando..." -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if ([version]$release.Version -le [version]$currentVersion) {
        return
    }

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Yellow
    Write-Host "   $(E 0x1F4E5)  ATUALIZACAO DISPONIVEL" -ForegroundColor Yellow
    Write-Host '  ======================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "   Versao instalada : v$currentVersion" -ForegroundColor White
    Write-Host "   Versao no GitHub : v$($release.Version) ($($release.Tag))" -ForegroundColor Green
    Write-Host "   Publicada em     : $($release.PublishedAt)" -ForegroundColor DarkGray
    Write-Host "   Detalhes         : $($release.ReleaseUrl)" -ForegroundColor DarkCyan

    if (Read-UpdateChoice) {
        try {
            Start-AppUpdateAndRestart -Release $release -Install $install
        }
        catch {
            Write-Host ''
            Write-Host "   $(E 0x274C) Falha ao atualizar: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '   Continuando com a versao atual...' -ForegroundColor DarkYellow
            Write-Host ''
        }
    }
    else {
        Write-Host ''
        Write-Host "   $(E 0x25B6) Continuando com v$currentVersion..." -ForegroundColor DarkCyan
        Write-Host ''
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
Invoke-AppUpdateCheck

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
