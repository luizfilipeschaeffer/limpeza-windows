#Requires -RunAsAdministrator

param(
    [switch]$ScheduledRun
)

# Limpeza Avancada do Windows v2.0.7
# Autor: Luiz Filipe Schaeffer

$AppVersion = '2.0.7'
$GitHubRepo = 'luizfilipeschaeffer/limpeza-windows'

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Initialize-SilentScheduledRun {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LimpezaNativeConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@ -ErrorAction Stop
        $hwnd = [LimpezaNativeConsole]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][LimpezaNativeConsole]::ShowWindow($hwnd, 0)
        }
    }
    catch {
        # Sem console ou ambiente restrito — segue em silencio
    }
}

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
$script:ShortcutFileName = 'Limpeza Avancada do Windows.lnk'
$script:ScheduledTaskName = 'Limpeza Avancada do Windows'

function Get-ScheduleTimeOptions {
    0..7 | ForEach-Object {
        $hour = $_ * 3
        [PSCustomObject]@{
            Index = $_ + 1
            Value = '{0:D2}:00' -f $hour
        }
    }
}

function Get-ScheduleTimeLabel {
    param([string]$Time)

    switch ($Time) {
        '00:00' { return '00:00 (meia-noite)' }
        '03:00' { return '03:00 (madrugada)' }
        '06:00' { return '06:00 (manha)' }
        '09:00' { return '09:00 (manha)' }
        '12:00' { return '12:00 (meio-dia)' }
        '15:00' { return '15:00 (tarde)' }
        '18:00' { return '18:00 (tarde)' }
        '21:00' { return '21:00 (noite)' }
        default  { return $Time }
    }
}

function Get-SystemInstallPath {
    Join-Path $env:SystemRoot $script:UpdateAssetName
}

function Test-SameFilePath {
    param(
        [string]$PathA,
        [string]$PathB
    )

    if (-not $PathA -or -not $PathB) { return $false }
    try {
        return [System.IO.Path]::GetFullPath($PathA).Equals(
            [System.IO.Path]::GetFullPath($PathB),
            [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-ExecutableSourcePath {
    if ($PSCommandPath -match '\.exe$' -and (Test-Path -LiteralPath $PSCommandPath)) {
        return $PSCommandPath
    }

    $distExe = Join-Path (Split-Path $PSScriptRoot -Parent) "dist\$script:UpdateAssetName"
    if (Test-Path -LiteralPath $distExe) {
        return $distExe
    }

    $systemExe = Get-SystemInstallPath
    if (Test-Path -LiteralPath $systemExe) {
        return $systemExe
    }

    return $null
}

function Get-FileVersionLabel {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $AppVersion }
    $fileVersion = (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
    if (-not $fileVersion) { return $AppVersion }

    $parts = $fileVersion.Split('.')
    if ($parts.Count -ge 3) {
        return "$($parts[0]).$($parts[1]).$($parts[2])"
    }
    return $fileVersion
}

function Set-DesktopShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { return }

    $shortcutPath = Join-Path $desktop $script:ShortcutFileName
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $env:SystemRoot
    $shortcut.Description = 'Limpeza Avancada do Windows'
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
}

function Test-ShouldCopyExecutable {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) { return $true }

    $sourceItem = Get-Item -LiteralPath $SourcePath
    $destItem = Get-Item -LiteralPath $DestinationPath
    if ($sourceItem.LastWriteTimeUtc -gt $destItem.LastWriteTimeUtc) { return $true }
    if ($sourceItem.Length -ne $destItem.Length) { return $true }

    $sourceVersion = $sourceItem.VersionInfo.ProductVersion
    $destVersion = $destItem.VersionInfo.ProductVersion
    return $sourceVersion -ne $destVersion
}

function Invoke-SystemInstallAndShortcut {
    $sourcePath = Get-ExecutableSourcePath
    if (-not $sourcePath) { return }

    $systemPath = Get-SystemInstallPath
    $runningFromSystem = ($PSCommandPath -match '\.exe$') -and (Test-SameFilePath $PSCommandPath $systemPath)
    $needsCopy = Test-ShouldCopyExecutable -SourcePath $sourcePath -DestinationPath $systemPath

    if ($needsCopy -and -not (Test-SameFilePath $sourcePath $systemPath)) {
        $prevError = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            Copy-Item -LiteralPath $sourcePath -Destination $systemPath -Force
        }
        catch {
            Write-Host ''
            Write-Host "   $(E 0x26A0) Nao foi possivel copiar para $systemPath : $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host ''
            $ErrorActionPreference = $prevError
            return
        }
        $ErrorActionPreference = $prevError
    }

    try {
        Set-DesktopShortcut -TargetPath $systemPath
    }
    catch {
        Write-Host "   $(E 0x26A0) Atalho na Area de Trabalho nao foi criado: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    if ($needsCopy -and -not $runningFromSystem -and ($PSCommandPath -match '\.exe$')) {
        Write-Host ''
        Write-Host "   $(E 0x1F4E6) Instalado em $systemPath" -ForegroundColor DarkCyan
        Write-Host "   $(E 0x1F517) Atalho criado na Area de Trabalho." -ForegroundColor DarkCyan
        Write-Host '   Reiniciando a partir da instalacao do sistema...' -ForegroundColor DarkGray
        Write-Host ''
        Start-Process -FilePath $systemPath -WorkingDirectory $env:SystemRoot
        exit 0
    }

    if ($PSCommandPath -match '\.ps1$' -and (Test-Path -LiteralPath $systemPath) -and -not $runningFromSystem) {
        Write-Host ''
        Write-Host "   $(E 0x1F4E6) Executavel disponivel em $systemPath" -ForegroundColor DarkCyan
        Write-Host "   $(E 0x1F517) Atalho criado na Area de Trabalho." -ForegroundColor DarkCyan
        Write-Host '   Iniciando versao instalada...' -ForegroundColor DarkGray
        Write-Host ''
        Start-Process -FilePath $systemPath -WorkingDirectory $env:SystemRoot
        exit 0
    }
}

function Get-AppInstallInfo {
    $systemPath = Get-SystemInstallPath
    $runningExe = $PSCommandPath -match '\.exe$'
    $executablePath = if (Test-Path -LiteralPath $systemPath) {
        $systemPath
    }
    elseif ($runningExe) {
        $PSCommandPath
    }
    else {
        Join-Path (Split-Path $PSScriptRoot -Parent) "dist\$script:UpdateAssetName"
    }

    return [PSCustomObject]@{
        Mode             = if ($runningExe) { 'exe' } else { 'script' }
        ExecutablePath   = $executablePath
        InstallDirectory = $env:SystemRoot
        CurrentVersion   = Get-FileVersionLabel -Path $executablePath
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
        [object]$Install,

        [string]$RestartArgument = ''
    )

    $targetExe = Get-SystemInstallPath
    $targetDir = $env:SystemRoot
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    $stagingExe = Join-Path $env:TEMP "LimpezaWindows-$([guid]::NewGuid().ToString('N')).exe"
    if (-not $ScheduledRun) {
        Write-Host ''
        Write-Host "   $(E 0x1F4E5) Baixando $($script:UpdateAssetName) v$($Release.Version)..." -ForegroundColor Cyan
    }
    $prevProgress = $ProgressPreference
    $ProgressPreference = if ($ScheduledRun) { 'SilentlyContinue' } else { 'Continue' }
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
    $shortcutName = $script:ShortcutFileName.Replace("'", "''")
    $systemRoot = $env:SystemRoot.Replace("'", "''")
    $launchLine = if ($RestartArgument) {
        "Start-Process -FilePath `$target -ArgumentList '$($RestartArgument.Replace("'", "''"))' -WorkingDirectory '$systemRoot'"
    } else {
        "Start-Process -FilePath `$target -WorkingDirectory '$systemRoot'"
    }
    $helperContent = @"
`$ErrorActionPreference = 'Stop'
`$staging = '$($stagingExe.Replace("'", "''"))'
`$target = '$($targetExe.Replace("'", "''"))'
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

`$desktop = [Environment]::GetFolderPath('Desktop')
if (`$desktop) {
    `$shortcutPath = Join-Path `$desktop '$shortcutName'
    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = `$target
    `$shortcut.WorkingDirectory = '$systemRoot'
    `$shortcut.Description = 'Limpeza Avancada do Windows'
    `$shortcut.IconLocation = "`$target,0"
    `$shortcut.Save()
}

$launchLine
"@
    Set-Content -Path $helperPs1 -Value $helperContent -Encoding UTF8

    if ($ScheduledRun) {
        Write-Host "   $(E 0x2705) Atualizacao v$($Release.Version) aplicada. Reiniciando limpeza agendada..." -ForegroundColor DarkCyan
        Write-Host ''
    }
    else {
        Write-Host "   $(E 0x2705) Download concluido. Reiniciando com v$($Release.Version)..." -ForegroundColor Green
        Write-Host '   A limpeza iniciara automaticamente na nova versao.' -ForegroundColor DarkGray
        Write-Host ''
    }

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
        if (-not $ScheduledRun) {
            Write-Host ''
            Write-Host "   $(E 0x26A0) Nao foi possivel verificar atualizacoes. Continuando..." -ForegroundColor DarkYellow
            Write-Host ''
        }
        return
    }

    if ([version]$release.Version -le [version]$currentVersion) {
        return
    }

    if ($ScheduledRun) {
        Write-Host "   $(E 0x1F4E5) Nova versao v$($release.Version) detectada (atual: v$currentVersion). Atualizando automaticamente..." -ForegroundColor Cyan
        Write-Host ''
        try {
            Start-AppUpdateAndRestart -Release $release -Install $install -RestartArgument '-ScheduledRun'
        }
        catch {
            Write-Host "   $(E 0x26A0) Falha na atualizacao automatica. Continuando com v$currentVersion..." -ForegroundColor DarkYellow
            Write-Host ''
        }
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

    if ($ScheduledRun) { return }

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
}

function Read-YesNoChoice {
    param([string]$Prompt)

    while ($true) {
        Write-Host ''
        Write-Host -NoNewline "   $Prompt " -ForegroundColor Yellow
        $answer = (Read-Host).Trim().ToUpperInvariant()
        if ($answer -in @('S', 'SIM', 'Y', 'YES')) { return $true }
        if ($answer -in @('N', 'NAO', 'NÃO', 'NO')) { return $false }
        Write-Host '   Opcao invalida. Digite S para sim ou N para nao.' -ForegroundColor Red
    }
}

function Read-ScheduleFrequencyChoice {
    while ($true) {
        Write-Host ''
        Write-Host "   $(E 0x1F4C5)  [1] 1x ao dia" -ForegroundColor White
        Write-Host "   $(E 0x1F4C5)  [2] 1x na semana (domingo)" -ForegroundColor White
        Write-Host "   $(E 0x1F4C5)  [3] 1x no mes (dia 1)" -ForegroundColor White
        Write-Host ''
        Write-Host -NoNewline '   Digite 1, 2 ou 3: ' -ForegroundColor Yellow

        $answer = (Read-Host).Trim()
        switch ($answer) {
            '1' { return 'Daily' }
            '2' { return 'Weekly' }
            '3' { return 'Monthly' }
        }
        Write-Host '   Opcao invalida. Escolha 1, 2 ou 3.' -ForegroundColor Red
    }
}

function Read-ScheduleTimeChoice {
    $options = Get-ScheduleTimeOptions
    $valid = ($options | ForEach-Object { [string]$_.Index })

    while ($true) {
        Write-Host ''
        Write-Host "   $(E 0x1F551)  Escolha o horario (intervalos de 3 horas):" -ForegroundColor Cyan
        foreach ($option in $options) {
            $label = Get-ScheduleTimeLabel -Time $option.Value
            Write-Host ("   [{0}] {1}" -f $option.Index, $label) -ForegroundColor White
        }
        Write-Host ''
        Write-Host -NoNewline '   Digite o numero do horario (1 a 8): ' -ForegroundColor Yellow

        $answer = (Read-Host).Trim()
        $selected = $options | Where-Object { [string]$_.Index -eq $answer } | Select-Object -First 1
        if ($selected) { return $selected.Value }

        Write-Host '   Opcao invalida. Escolha um horario entre 1 e 8.' -ForegroundColor Red
    }
}

function Get-ScheduleFrequencyLabel {
    param([string]$Frequency)

    switch ($Frequency) {
        'Daily'   { return '1x ao dia' }
        'Weekly'  { return '1x na semana (domingo)' }
        'Monthly' { return '1x no mes (dia 1)' }
        default   { return $Frequency }
    }
}

function Show-SchedulePromptBanner {
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ("   $(E 0x23F0)  AGENDAMENTO AUTOMATICO") -ForegroundColor Cyan
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Get-ExistingScheduledTask {
    $taskName = $script:ScheduledTaskName
    $query = & schtasks.exe /Query /TN $taskName /FO LIST /V 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $query) {
        return $null
    }

    $scheduleLine = $query | Where-Object {
        $_ -match '^(Tipo de Agendamento|Schedule Type)\s*:'
    } | Select-Object -First 1

    $startLine = $query | Where-Object {
        $_ -match '^(Hora de in[ií]cio|Hora de inicio|Start Time)\s*:'
    } | Select-Object -First 1

    $nextLine = $query | Where-Object {
        $_ -match '^(Pr.xima hora de execu|Next Run Time)\s*:'
    } | Select-Object -First 1

    $frequency = 'Daily'
    if ($scheduleLine -match ':\s*(.+)') {
        $rawType = $Matches[1].Trim().ToUpperInvariant()
        if ($rawType -match 'SEMANAL|WEEKLY') { $frequency = 'Weekly' }
        elseif ($rawType -match 'MENSAL|MONTHLY') { $frequency = 'Monthly' }
        else { $frequency = 'Daily' }
    }

    $startTime = '03:00'
    if ($startLine -match ':\s*(\d{1,2}:\d{2})') {
        $startTime = $Matches[1]
        if ($startTime.Length -eq 4) { $startTime = "0$startTime" }
    }

    $nextRun = $null
    if ($nextLine -match ':\s*(.+)') {
        $nextRun = $Matches[1].Trim()
        if ($nextRun -match '^(N/A|N/D|-)') { $nextRun = $null }
    }

    [PSCustomObject]@{
        TaskName  = $taskName
        Frequency = $frequency
        Label     = Get-ScheduleFrequencyLabel -Frequency $frequency
        StartTime = $startTime
        StartTimeLabel = Get-ScheduleTimeLabel -Time $startTime
        NextRun   = $nextRun
    }
}

function Read-ExistingScheduleActionKey {
    Write-Host ''
    Write-Host -NoNewline '   Pressione Espaco, 1 ou 2: ' -ForegroundColor Yellow

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.Key) {
            'Spacebar' { return 'Skip' }
            'D1'       { return 'Edit' }
            'NumPad1'  { return 'Edit' }
            'D2'       { return 'Remove' }
            'NumPad2'  { return 'Remove' }
        }

        if ($key.Character -eq '1') { return 'Edit' }
        if ($key.Character -eq '2') { return 'Remove' }
    }
}

function Read-ExistingScheduleAction {
    Write-Host '   Ja existe um agendamento para a limpeza automatica.' -ForegroundColor White
    Write-Host ''
    Write-Host "         [space] Nao alterar" -ForegroundColor White
    Write-Host "   $(E 0x270E)  [1] Editar agendamento" -ForegroundColor White
    Write-Host "   $(E 0x1F5D1)  [2] Remover agendamento" -ForegroundColor White

    return Read-ExistingScheduleActionKey
}

function Remove-LimpezaScheduledTask {
    $taskName = $script:ScheduledTaskName
    schtasks /End /TN $taskName 2>$null | Out-Null
    $output = & schtasks.exe /Delete /TN $taskName /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }
}

function Show-ScheduledTaskSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [string]$Title = 'Agendamento atual'
    )

    Write-Host "   $Title" -ForegroundColor White
    Write-Host "       Frequencia : $($Task.Label)" -ForegroundColor DarkGray
    Write-Host "       Horario    : $($Task.StartTimeLabel)" -ForegroundColor DarkGray
    if ($Task.NextRun) {
        Write-Host "       Proxima execucao : $($Task.NextRun)" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function New-ScheduledMaintenanceTask {
    $frequency = Read-ScheduleFrequencyChoice
    $startTime = Read-ScheduleTimeChoice
    return Register-LimpezaScheduledTask -Frequency $frequency -StartTime $startTime
}

function Get-ScheduledTaskExecutablePath {
    $systemPath = Get-SystemInstallPath
    if (Test-Path -LiteralPath $systemPath) { return $systemPath }

    $sourcePath = Get-ExecutableSourcePath
    if ($sourcePath) { return $sourcePath }

    throw 'Executavel nao encontrado para criar a tarefa agendada.'
}

function Register-LimpezaScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Frequency,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$StartTime
    )

    $taskName = $script:ScheduledTaskName
    $exePath = Get-ScheduledTaskExecutablePath
    $taskCommand = "cmd.exe /c start `"`" /B `"$exePath`" -ScheduledRun"

    schtasks /End /TN $taskName 2>$null | Out-Null
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    $schtasksArgs = @('/Create', '/TN', $taskName, '/TR', $taskCommand, '/ST', $StartTime, '/RL', 'HIGHEST', '/F')
    switch ($Frequency) {
        'Daily'   { $schtasksArgs += @('/SC', 'DAILY') }
        'Weekly'  { $schtasksArgs += @('/SC', 'WEEKLY', '/D', 'SUN') }
        'Monthly' { $schtasksArgs += @('/SC', 'MONTHLY', '/D', '1') }
    }

    $prevError = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & schtasks.exe @schtasksArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevError

    if ($exitCode -ne 0) {
        throw (($output | Out-String).Trim())
    }

    $nextRun = $null
    $query = & schtasks.exe /Query /TN $taskName /FO LIST /V 2>$null
    if ($query) {
        $nextLine = $query | Where-Object { $_ -match '^(Proxima hora de execu|Next Run Time)\s*:' } | Select-Object -First 1
        if ($nextLine -match ':\s*(.+)') {
            $nextRun = $Matches[1].Trim()
        }
    }

    [PSCustomObject]@{
        TaskName  = $taskName
        Frequency = $Frequency
        Label     = Get-ScheduleFrequencyLabel -Frequency $Frequency
        StartTime = $StartTime
        StartTimeLabel = Get-ScheduleTimeLabel -Time $StartTime
        Command   = $taskCommand
        NextRun   = $nextRun
    }
}

function Invoke-ScheduledMaintenancePrompt {
    if ($ScheduledRun -or $env:LIMPEZA_SCHEDULED_RUN -eq '1') { return }
    if (-not [Environment]::UserInteractive) { return }

    Show-SchedulePromptBanner

    $existingTask = Get-ExistingScheduledTask

    if ($existingTask) {
        Show-ScheduledTaskSummary -Task $existingTask

        switch (Read-ExistingScheduleAction) {
            'Skip' {
                return
            }
            'Remove' {
                try {
                    Remove-LimpezaScheduledTask
                    Write-Host "   $(E 0x2705) Agendamento removido com sucesso." -ForegroundColor Green
                    Write-Host ''
                }
                catch {
                    Write-Host "   $(E 0x274C) Falha ao remover agendamento: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host ''
                }
                return
            }
            'Edit' {
                Write-Host '   Defina o novo agendamento:' -ForegroundColor Cyan
                Write-Host ''
                try {
                    $task = New-ScheduledMaintenanceTask
                    Write-Host "   $(E 0x2705) Agendamento atualizado com sucesso." -ForegroundColor Green
                    Show-ScheduledTaskSummary -Task $task -Title 'Novo agendamento'
                }
                catch {
                    Write-Host "   $(E 0x274C) Falha ao editar agendamento: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host ''
                }
                return
            }
        }
        return
    }

    Write-Host '   Deseja agendar a limpeza para rodar automaticamente?' -ForegroundColor White
    Write-Host '   A tarefa sera criada no Agendador de Tarefas do Windows.' -ForegroundColor DarkGray

    if (-not (Read-YesNoChoice -Prompt 'Agendar limpeza automatica? [S/N]:')) {
        return
    }

    try {
        $task = New-ScheduledMaintenanceTask
        Write-Host ''
        Write-Host "   $(E 0x2705) Agendamento criado com sucesso." -ForegroundColor Green
        Show-ScheduledTaskSummary -Task $task -Title 'Agendamento configurado'
    }
    catch {
        Write-Host ''
        Write-Host "   $(E 0x274C) Falha ao criar agendamento: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ''
    }
}

# --- Execucao principal ---

if ($ScheduledRun) {
    function Write-Host {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline = $true)]
            $Object,
            [switch]$NoNewline,
            [ConsoleColor]$ForegroundColor,
            [ConsoleColor]$BackgroundColor
        )
        begin { }
        process { }
        end { }
    }
    Initialize-SilentScheduledRun
}
else {
    Initialize-Console
}

if (-not $ScheduledRun) {
    Show-IntroAnimation
    Invoke-SystemInstallAndShortcut
}

Invoke-AppUpdateCheck

$startTime  = Get-Date
$freeBefore = Get-DriveCFreeBytes

if (-not $ScheduledRun) {
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
}

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
if (-not $ScheduledRun) {
    Write-StepHeader -Number 6 -Total 6 -Icon 0x1F4BF -Title 'Limpeza de Disco (cleanmgr)'
    Write-Host "       $(E 0x1FA9F) Abrindo o assistente..."
    Write-Host ''
    & cleanmgr /sagerun:1
    Write-StepResult -ExitCode $LASTEXITCODE
}

$freeAfter = Get-DriveCFreeBytes
$endTime   = Get-Date

if (-not $ScheduledRun) {
    Show-FinalResult -FreeBefore $freeBefore -FreeAfter $freeAfter -StartTime $startTime -EndTime $endTime
    Invoke-ScheduledMaintenancePrompt
}

if (Test-Path $emptyFolder) {
    Remove-Item -Path $emptyFolder -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $ScheduledRun) {
    Write-Host "   $(E 0x1F44B) Pressione qualquer tecla para sair..."
    Write-Host ''
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
