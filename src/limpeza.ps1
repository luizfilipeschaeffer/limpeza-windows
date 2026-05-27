#Requires -RunAsAdministrator

param(
    [switch]$ScheduledRun,
    [switch]$SkipDevCaches,
    [switch]$SkipNode,
    [switch]$SkipPython,
    [switch]$SkipDocker
)

# Limpeza Avancada do Windows v2.2.1
# Autor: Luiz Filipe Schaeffer

$AppVersion = '2.2.1'
$script:CleanupLog = [System.Collections.Generic.List[object]]::new()
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

#region LimpezaUpdateLoader
$script:LimpezaUpdateModulePath = Join-Path $PSScriptRoot 'LimpezaUpdate.ps1'
if (-not (Test-Path -LiteralPath $script:LimpezaUpdateModulePath) -and $PSCommandPath) {
    $script:LimpezaUpdateModulePath = Join-Path (Split-Path -Parent $PSCommandPath) 'LimpezaUpdate.ps1'
}
if (-not (Test-Path -LiteralPath $script:LimpezaUpdateModulePath)) {
    throw "Modulo de atualizacao obrigatorio ausente: $($script:LimpezaUpdateModulePath)"
}
. $script:LimpezaUpdateModulePath
Sync-LimpezaUpdateModule -SourceModulePath $script:LimpezaUpdateSelfPath | Out-Null
#endregion

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
    Get-LimpezaFileVersionLabel -Path $Path -FallbackVersion $AppVersion
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

    Install-LimpezaUpdateModuleBesideExecutable -TargetDirectory $env:SystemRoot | Out-Null

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

function Test-SkipFlag {
    param(
        [switch]$Switch,
        [string]$EnvVarName
    )
    if ($Switch) { return $true }
    if ($EnvVarName -and [Environment]::GetEnvironmentVariable($EnvVarName) -eq '1') { return $true }
    return $false
}

function Get-RobocopyLogStatus {
    param([int]$ExitCode)
    if ($ExitCode -ge 8) { return 'Parcial' }
    return 'Limpo'
}

function Add-CleanupLogEntry {
    param(
        [string]$Category,
        [string]$Target,
        [ValidateSet('Limpo', 'Ignorado', 'Parcial', 'Erro', 'Pulado')]
        [string]$Status,
        [string]$Detail = ''
    )
    $script:CleanupLog.Add([PSCustomObject]@{
            Category = $Category
            Target   = $Target
            Status   = $Status
            Detail   = $Detail
        })
}

function Get-CleanupStatusColor {
    param([string]$Status)
    switch ($Status) {
        'Limpo'    { return 'Green' }
        'Ignorado' { return 'DarkGray' }
        'Parcial'  { return 'Yellow' }
        'Erro'     { return 'Red' }
        'Pulado'   { return 'DarkCyan' }
        default    { return 'White' }
    }
}

function Show-CleanupReport {
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ("           $(E 0x1F4CB)  RELATORIO DA LIMPEZA  $(E 0x1F4CB)") -ForegroundColor Cyan
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''

    if ($script:CleanupLog.Count -eq 0) {
        Write-Host '  Nenhum item registrado nesta execucao.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $currentCategory = $null
    foreach ($entry in $script:CleanupLog) {
        if ($entry.Category -ne $currentCategory) {
            $currentCategory = $entry.Category
            Write-Host ''
            Write-Host "  [$currentCategory]" -ForegroundColor Cyan
        }
        $color = Get-CleanupStatusColor -Status $entry.Status
        $detailSuffix = if ($entry.Detail) { ' - ' + $entry.Detail } else { '' }
        Write-Host ('  - {0}' -f $entry.Target) -ForegroundColor White
        Write-Host ('    [{0}]{1}' -f $entry.Status, $detailSuffix) -ForegroundColor $color
    }

    $limpo    = @($script:CleanupLog | Where-Object Status -eq 'Limpo').Count
    $ignorado = @($script:CleanupLog | Where-Object Status -eq 'Ignorado').Count
    $parcial  = @($script:CleanupLog | Where-Object { $_.Status -in @('Parcial', 'Erro') }).Count
    $pulado   = @($script:CleanupLog | Where-Object Status -eq 'Pulado').Count

    Write-Host ''
    Write-Host '  ------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ("  Resumo: {0} limpos, {1} ignorados, {2} com aviso/erro, {3} pulados" -f $limpo, $ignorado, $parcial, $pulado) -ForegroundColor White
    Write-Host ''
}

function Get-CleanupLogFilePath {
    $logDir = Join-Path $env:ProgramData 'LimpezaWindows\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Join-Path $logDir "limpeza-$stamp.log"
}

function Export-CleanupLogToFile {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter,
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    $culture = [cultureinfo]::GetCultureInfo('pt-BR')
    $gainedGb = Get-DiskSpaceGainedGb -FreeBefore $FreeBefore -FreeAfter $FreeAfter
    $logPath = Get-CleanupLogFilePath
    $lines   = [System.Collections.Generic.List[string]]::new()

    $lines.Add("Limpeza Avancada do Windows v$AppVersion")
    $lines.Add("Inicio:  $($StartTime.ToString('dd/MM/yyyy HH:mm:ss'))")
    $lines.Add("Termino: $($EndTime.ToString('dd/MM/yyyy HH:mm:ss'))")
    $lines.Add("Execucao agendada (silenciosa)")
    $lines.Add('')
    $lines.Add('--- Relatorio ---')

    foreach ($entry in $script:CleanupLog) {
        $detail = if ($entry.Detail) { ' | ' + $entry.Detail } else { '' }
        $lines.Add(('[{0}] {1} | {2}{3}' -f $entry.Category, $entry.Target, $entry.Status, $detail))
    }

    $lines.Add('')
    $lines.Add('--- Espaco em disco C: ---')
    $lines.Add(("Antes:  {0} GB" -f (Get-DiskSpaceGbDisplay -FreeBytes $FreeBefore)))
    $lines.Add(("Depois: {0} GB" -f (Get-DiskSpaceGbDisplay -FreeBytes $FreeAfter)))
    $lines.Add(("Ganho:  {0} GB" -f $gainedGb.ToString('N2', $culture)))

    $lines | Set-Content -Path $logPath -Encoding UTF8
}

function Invoke-FinalSummaryScreen {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter,
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    Clear-Host
    try { chcp 65001 | Out-Null } catch {}
    $Host.UI.RawUI.WindowTitle = "$(E 0x1F9F9) Limpeza Avancada do Windows v$AppVersion"

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ("           $(E 0x1F389)  LIMPEZA CONCLUIDA  $(E 0x1F389)") -ForegroundColor Green
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "       $(E 0x1F464) Autor   : Luiz Filipe Schaeffer"
    Write-Host "       $(E 0x1F4CC) Versao  : $AppVersion"
    Write-Host ("       $(E 0x1F550) Inicio  : {0}" -f $StartTime.ToString('dd/MM/yyyy HH:mm:ss'))
    Write-Host ("       $(E 0x1F3C1) Termino : {0}" -f $EndTime.ToString('dd/MM/yyyy HH:mm:ss'))
    Write-Host ''

    Show-CleanupReport
    Show-FinalResult -FreeBefore $FreeBefore -FreeAfter $FreeAfter
    Invoke-ScheduledMaintenancePrompt
}

function Invoke-CleanupFolderPath {
    param(
        [string]$Category,
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Add-CleanupLogEntry -Category $Category -Target $TargetPath -Status 'Ignorado' -Detail 'Pasta ausente ou nao instalado'
        return
    }

    $code   = Invoke-RobocopyClean -TargetPath $TargetPath
    $status = Get-RobocopyLogStatus -ExitCode $code
    $detail = if ($status -eq 'Parcial') { 'Alguns arquivos em uso ou bloqueados' } else { 'Concluido' }
    Add-CleanupLogEntry -Category $Category -Target $TargetPath -Status $status -Detail $detail
}

function Invoke-DevToolCacheClean {
    $skipNode   = Test-SkipFlag -Switch $SkipNode   -EnvVarName 'LIMPEZA_SKIP_NODE'
    $skipPython = Test-SkipFlag -Switch $SkipPython -EnvVarName 'LIMPEZA_SKIP_PYTHON'
    $skipDocker = Test-SkipFlag -Switch $SkipDocker -EnvVarName 'LIMPEZA_SKIP_DOCKER'

    $nodeTargets = @(
        @{ Label = 'npm';        Path = Join-Path $env:LOCALAPPDATA 'npm-cache' }
        @{ Label = 'npm legado'; Path = Join-Path $env:APPDATA 'npm-cache' }
        @{ Label = 'pnpm';       Path = Join-Path $env:LOCALAPPDATA 'pnpm-store' }
        @{ Label = 'Yarn';       Path = Join-Path $env:LOCALAPPDATA 'Yarn\Cache' }
        @{ Label = 'Yarn Berry'; Path = Join-Path $env:LOCALAPPDATA 'Yarn\Berry\cache' }
        @{ Label = 'Turborepo';  Path = Join-Path $env:LOCALAPPDATA 'turbo' }
    )

    $pythonTargets = @(
        @{ Label = 'pip';     Path = Join-Path $env:LOCALAPPDATA 'pip\Cache' }
        @{ Label = 'pip alt'; Path = Join-Path $env:USERPROFILE '.cache\pip' }
        @{ Label = 'Poetry';  Path = Join-Path $env:LOCALAPPDATA 'pypoetry\Cache' }
        @{ Label = 'uv';      Path = Join-Path $env:LOCALAPPDATA 'uv\cache' }
    )

    if ($skipNode) {
        Add-CleanupLogEntry -Category 'Node' -Target '(todos)' -Status 'Pulado' -Detail 'SkipNode ou LIMPEZA_SKIP_NODE'
    }
    else {
        foreach ($target in $nodeTargets) {
            Invoke-CleanupFolderPath -Category 'Node' -TargetPath $target.Path
        }
    }

    if ($skipPython) {
        Add-CleanupLogEntry -Category 'Python' -Target '(todos)' -Status 'Pulado' -Detail 'SkipPython ou LIMPEZA_SKIP_PYTHON'
    }
    else {
        foreach ($target in $pythonTargets) {
            Invoke-CleanupFolderPath -Category 'Python' -TargetPath $target.Path
        }
    }

    if ($skipDocker) {
        Add-CleanupLogEntry -Category 'Docker' -Target 'docker system prune -f' -Status 'Pulado' -Detail 'SkipDocker ou LIMPEZA_SKIP_DOCKER'
        return
    }

    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Add-CleanupLogEntry -Category 'Docker' -Target 'docker system prune -f' -Status 'Ignorado' -Detail 'Docker CLI nao encontrado'
        return
    }

    $dockerOut = & docker system prune -f 2>&1 | Out-String
    $dockerOut = ($dockerOut -replace '\s+', ' ').Trim()
    if ($dockerOut.Length -gt 120) {
        $dockerOut = $dockerOut.Substring(0, 117) + '...'
    }

    if ($LASTEXITCODE -eq 0) {
        $detail = if ($dockerOut) { $dockerOut } else { 'Prune concluido' }
        Add-CleanupLogEntry -Category 'Docker' -Target 'docker system prune -f' -Status 'Limpo' -Detail $detail
    }
    else {
        $detail = if ($dockerOut) { $dockerOut } else { "Codigo de saida $LASTEXITCODE" }
        Add-CleanupLogEntry -Category 'Docker' -Target 'docker system prune -f' -Status 'Erro' -Detail $detail
    }
}

function Invoke-WindowsUpdateCacheClean {
    $downloadPath = Join-Path $env:windir 'SoftwareDistribution\Download'

    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service bits -Force -ErrorAction SilentlyContinue

    Invoke-CleanupFolderPath -Category 'Windows' -TargetPath $downloadPath

    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service bits -ErrorAction SilentlyContinue
}

function Invoke-SystemSafeCacheClean {
    $folderTargets = @(
        Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
        Join-Path $env:windir 'Logs'
        Join-Path $env:ProgramData 'Microsoft\Windows\WER'
    )

    foreach ($targetPath in $folderTargets) {
        Invoke-CleanupFolderPath -Category 'Windows' -TargetPath $targetPath
    }
}

function Invoke-BrowserCacheClean {
    $browserTargets = @(
        Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'
        Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'
    )

    foreach ($targetPath in $browserTargets) {
        Invoke-CleanupFolderPath -Category 'Navegador' -TargetPath $targetPath
    }

    $firefoxProfilesRoot = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (-not (Test-Path -LiteralPath $firefoxProfilesRoot)) {
        Add-CleanupLogEntry -Category 'Navegador' -Target $firefoxProfilesRoot -Status 'Ignorado' -Detail 'Firefox nao instalado'
        return
    }

    $profiles = @(Get-ChildItem -LiteralPath $firefoxProfilesRoot -Directory -ErrorAction SilentlyContinue)
    if ($profiles.Count -eq 0) {
        Add-CleanupLogEntry -Category 'Navegador' -Target $firefoxProfilesRoot -Status 'Ignorado' -Detail 'Nenhum perfil encontrado'
        return
    }

    foreach ($profile in $profiles) {
        Invoke-CleanupFolderPath -Category 'Navegador' -TargetPath (Join-Path $profile.FullName 'cache2')
    }
}

function Invoke-RecycleBinClean {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Add-CleanupLogEntry -Category 'Windows' -Target 'Lixeira' -Status 'Limpo' -Detail 'Lixeira esvaziada'
    }
    catch {
        Add-CleanupLogEntry -Category 'Windows' -Target 'Lixeira' -Status 'Parcial' -Detail 'Nao foi possivel esvaziar completamente'
    }
}

function Invoke-DnsCacheFlush {
    $null = & ipconfig.exe /flushdns 2>&1
    $status = if ($LASTEXITCODE -eq 0) { 'Limpo' } else { 'Erro' }
    $detail = if ($LASTEXITCODE -eq 0) { 'Cache DNS limpo' } else { "Codigo de saida $LASTEXITCODE" }
    Add-CleanupLogEntry -Category 'Windows' -Target 'ipconfig /flushdns' -Status $status -Detail $detail
}

function Get-DriveCFreeBytes {
    (Get-PSDrive C).Free
}

function Get-DiskSpaceGbDisplay {
    param([long]$FreeBytes)

    $culture = [cultureinfo]::GetCultureInfo('pt-BR')
    [decimal]::Round($FreeBytes / 1GB, 2, [MidpointRounding]::AwayFromZero).ToString('N2', $culture)
}

function Get-DiskSpaceGainedGb {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter
    )

    $culture  = [cultureinfo]::GetCultureInfo('pt-BR')
    $antesGb  = [decimal]::Parse((Get-DiskSpaceGbDisplay -FreeBytes $FreeBefore), $culture)
    $depoisGb = [decimal]::Parse((Get-DiskSpaceGbDisplay -FreeBytes $FreeAfter), $culture)
    $depoisGb - $antesGb
}

function Show-FinalResult {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter
    )

    $culture  = [cultureinfo]::GetCultureInfo('pt-BR')
    $antesGb  = Get-DiskSpaceGbDisplay -FreeBytes $FreeBefore
    $depoisGb = Get-DiskSpaceGbDisplay -FreeBytes $FreeAfter
    $gainedGb = Get-DiskSpaceGainedGb -FreeBefore $FreeBefore -FreeAfter $FreeAfter

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ("           $(E 0x1F389)  RESULTADO FINAL  $(E 0x1F389)") -ForegroundColor Green
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("  $(E 0x1F4C9) Antes  : {0} GB livres" -f $antesGb) -ForegroundColor DarkYellow
    Write-Host ("  $(E 0x1F4C8) Depois : {0} GB livres" -f $depoisGb) -ForegroundColor Green
    Write-Host ''

    $gainedColor = if ($gainedGb -gt 0) { 'Green' } else { 'DarkGray' }
    Write-Host ("  $(E 0x1F4CA) Espaco ganho com a limpeza: {0} GB" -f $gainedGb.ToString('N2', $culture)) -ForegroundColor $gainedColor
    if ($gainedGb -le 0) {
        Write-Host "  $(E 0x1F4A1) (nenhum ganho mensuravel - arquivos em uso ou disco ja limpo)" -ForegroundColor DarkGray
    }

    Write-Host ''
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
    Write-Host '======================================================' -ForegroundColor Cyan
    Write-Host ("           $(E 0x23F0)  AGENDAMENTO AUTOMATICO") -ForegroundColor Cyan
    Write-Host '======================================================' -ForegroundColor Cyan
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
    Write-Host -NoNewline '   Pressione S, 1 ou 2: ' -ForegroundColor Yellow

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.Key) {
            'D1'      { return 'Edit' }
            'NumPad1' { return 'Edit' }
            'D2'      { return 'Remove' }
            'NumPad2' { return 'Remove' }
        }

        $char = $key.Character.ToString().ToUpperInvariant()
        if ($char -eq 'S') { return 'Skip' }
        if ($char -eq '1') { return 'Edit' }
        if ($char -eq '2') { return 'Remove' }
    }
}

function Read-ExistingScheduleAction {
    Write-Host '   Ja existe um agendamento para a limpeza automatica.' -ForegroundColor White
    Write-Host ''
    Write-Host "         [S] Sair" -ForegroundColor White
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
    # /TR direto no .exe (evita cmd/start /B — o schtasks interpreta /B como opcao invalida)
    $taskCommand = "`"$exePath`" -ScheduledRun"

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
}

$script:DistFallbackExe = Join-Path (Split-Path $PSScriptRoot -Parent) "dist\$script:UpdateAssetName"

Invoke-LimpezaAppUpdateCheck `
    -Repo $GitHubRepo `
    -AssetName $script:UpdateAssetName `
    -AppVersion $AppVersion `
    -DistFallbackPath $script:DistFallbackExe `
    -CommandPath $PSCommandPath `
    -ApiHeaders $script:GitHubApiHeaders `
    -ShortcutName $script:ShortcutFileName `
    -ScheduledRun:$ScheduledRun `
    -WriteUpdatePrompt {
        param($Install, $Release)
        Write-Host ''
        Write-Host '  ======================================================' -ForegroundColor Yellow
        Write-Host ("   $(E 0x1F4E5)  ATUALIZACAO DISPONIVEL") -ForegroundColor Yellow
        Write-Host '  ======================================================' -ForegroundColor Yellow
        Write-Host ''
        Write-Host "   Versao instalada : v$($Install.CurrentVersion)" -ForegroundColor White
        Write-Host "   Versao no GitHub : v$($Release.Version) ($($Release.Tag))" -ForegroundColor Green
        Write-Host "   Publicada em     : $($Release.PublishedAt)" -ForegroundColor DarkGray
        Write-Host "   Detalhes         : $($Release.ReleaseUrl)" -ForegroundColor DarkCyan
    }

if (-not $ScheduledRun) {
    Invoke-SystemInstallAndShortcut
}

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

$stepTotal = 11

# [1/11] TEMP do Windows
$winTempPath = Join-Path $env:windir 'Temp'
Write-StepHeader -Number 1 -Total $stepTotal -Icon 0x1F5D1 -Title 'TEMP do Windows'
Show-Spinner 'Varrendo arquivos temporarios'
$code = Invoke-RobocopyClean -TargetPath $winTempPath
Write-StepResult -ExitCode $code
Add-CleanupLogEntry -Category 'Windows' -Target $winTempPath -Status (Get-RobocopyLogStatus -ExitCode $code) -Detail $(if ($code -ge 8) { 'Alguns arquivos em uso' } else { 'Concluido' })

# [2/11] TEMP do usuario
$userTempPath = $env:TEMP
Write-StepHeader -Number 2 -Total $stepTotal -Icon 0x1F4C1 -Title 'TEMP do usuario'
Show-Spinner 'Limpando pasta TEMP do usuario'
$code = Invoke-RobocopyClean -TargetPath $userTempPath
Write-StepResult -ExitCode $code
Add-CleanupLogEntry -Category 'Windows' -Target $userTempPath -Status (Get-RobocopyLogStatus -ExitCode $code) -Detail $(if ($code -ge 8) { 'Alguns arquivos em uso' } else { 'Concluido' })

# [3/11] Prefetch
$prefetchPath = Join-Path $env:windir 'Prefetch'
Write-StepHeader -Number 3 -Total $stepTotal -Icon 0x26A1 -Title 'Prefetch'
Show-Spinner 'Otimizando cache Prefetch'
$code = Invoke-RobocopyClean -TargetPath $prefetchPath
Write-StepResult -ExitCode $code
Add-CleanupLogEntry -Category 'Windows' -Target $prefetchPath -Status (Get-RobocopyLogStatus -ExitCode $code) -Detail $(if ($code -ge 8) { 'Alguns arquivos em uso' } else { 'Concluido' })

# [4/11] Cache do Windows Update
Write-StepHeader -Number 4 -Total $stepTotal -Icon 0x1F504 -Title 'Cache do Windows Update'
Show-Spinner 'Limpando downloads do Windows Update'
Invoke-WindowsUpdateCacheClean
Write-StepResult -ExitCode 0

# [5/11] Caches do sistema (miniaturas, logs, relatorios de erro)
Write-StepHeader -Number 5 -Total $stepTotal -Icon 0x1F4C3 -Title 'Caches do sistema (miniaturas, logs, WER)'
Show-Spinner 'Limpando miniaturas, logs e relatorios de erro'
Invoke-SystemSafeCacheClean
Write-StepResult -ExitCode 0

# [6/11] Caches de navegadores
Write-StepHeader -Number 6 -Total $stepTotal -Icon 0x1F310 -Title 'Caches de navegadores (Edge, Chrome, Firefox)'
Show-Spinner 'Limpando caches Edge, Chrome e Firefox'
Invoke-BrowserCacheClean
Write-StepResult -ExitCode 0

# [7/11] Lixeira e cache DNS
Write-StepHeader -Number 7 -Total $stepTotal -Icon 0x1F5D1 -Title 'Lixeira e cache DNS'
Show-Spinner 'Esvaziando lixeira e limpando cache DNS'
Invoke-RecycleBinClean
Invoke-DnsCacheFlush
Write-StepResult -ExitCode 0

# [8/11] Caches de desenvolvimento
if (-not (Test-SkipFlag -Switch $SkipDevCaches -EnvVarName 'LIMPEZA_SKIP_DEV')) {
    Write-StepHeader -Number 8 -Total $stepTotal -Icon 0x1F4BB -Title 'Caches de desenvolvimento (Node, Python, Docker)'
    Show-Spinner 'Limpando caches npm, pip, Docker...'
    Invoke-DevToolCacheClean
    Write-StepResult -ExitCode 0
}
else {
    Add-CleanupLogEntry -Category 'Dev' -Target '(todos)' -Status 'Pulado' -Detail 'SkipDevCaches ou LIMPEZA_SKIP_DEV'
}

# [9/11] Windows Installer
$installer = Join-Path $env:windir 'Installer'
Write-StepHeader -Number 9 -Total $stepTotal -Icon 0x1F4E6 -Title 'Windows Installer (agressivo)'
Show-Spinner 'Removendo residuos do Installer'
& takeown /f $installer /r /d y 2>$null | Out-Null
& icacls $installer /grant administrators:F /t 2>$null | Out-Null
& attrib -h -r -s "$installer\*.*" /s /d 2>$null | Out-Null
Get-ChildItem -Path $installer -Recurse -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-StepResult -ExitCode 0
Add-CleanupLogEntry -Category 'Windows' -Target $installer -Status 'Limpo' -Detail 'Residuos do Installer removidos'

# [10/11] DISM
$dismTarget = 'DISM - Repositorio de Componentes'
Write-StepHeader -Number 10 -Total $stepTotal -Icon 0x1F527 -Title 'Componentes do Windows (DISM)'
Show-Spinner 'Analisando repositorio de componentes'
$dismOut = & Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
if ($dismOut -match 'Limpeza do Repositorio de Componentes Recomendada\s*:\s*Sim') {
    Write-Host "       $(E 0x1F525) Limpeza recomendada. Executando..." -ForegroundColor Yellow
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    $dismStatus = if ($LASTEXITCODE -eq 0) { 'Limpo' } else { 'Erro' }
    $dismDetail = if ($LASTEXITCODE -eq 0) { 'Limpeza de componentes executada' } else { "Codigo de saida $LASTEXITCODE" }
}
else {
    Write-Host "       $(E 0x2728) Nenhuma limpeza necessaria no momento." -ForegroundColor DarkGray
    $dismStatus = 'Ignorado'
    $dismDetail = 'Nenhuma limpeza necessaria no momento'
}
Write-StepResult -ExitCode $LASTEXITCODE
Add-CleanupLogEntry -Category 'Windows' -Target $dismTarget -Status $dismStatus -Detail $dismDetail

# [11/11] cleanmgr
if (-not $ScheduledRun) {
    Write-StepHeader -Number 11 -Total $stepTotal -Icon 0x1F4BF -Title 'Limpeza de Disco (cleanmgr)'
    Write-Host "       $(E 0x1FA9F) Abrindo o assistente..."
    Write-Host ''
    & cleanmgr /sagerun:1
    $cleanmgrCode = $LASTEXITCODE
    Write-StepResult -ExitCode $cleanmgrCode
    $cleanmgrStatus = if ($cleanmgrCode -ge 8) { 'Parcial' } elseif ($cleanmgrCode -eq 0) { 'Limpo' } else { 'Erro' }
    Add-CleanupLogEntry -Category 'Windows' -Target 'cleanmgr /sagerun:1' -Status $cleanmgrStatus -Detail 'Assistente de limpeza de disco'
}
else {
    Add-CleanupLogEntry -Category 'Windows' -Target 'cleanmgr /sagerun:1' -Status 'Pulado' -Detail 'Execucao agendada (sem assistente grafico)'
}

$freeAfter = Get-DriveCFreeBytes
$endTime   = Get-Date

if (-not $ScheduledRun) {
    Invoke-FinalSummaryScreen -FreeBefore $freeBefore -FreeAfter $freeAfter -StartTime $startTime -EndTime $endTime
}
else {
    Export-CleanupLogToFile -FreeBefore $freeBefore -FreeAfter $freeAfter -StartTime $startTime -EndTime $endTime
}

if (Test-Path $emptyFolder) {
    Remove-Item -Path $emptyFolder -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $ScheduledRun) {
    Write-Host "   $(E 0x1F44B) Pressione qualquer tecla para sair..."
    Write-Host ''
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
