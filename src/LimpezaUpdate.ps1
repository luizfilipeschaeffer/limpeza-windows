# Modulo isolado de auto-atualizacao (GitHub Releases).
# Testado por tests/Test-LimpezaUpdate.ps1 — manter em sincronia com o helper gerado.

if ($MyInvocation.MyCommand.Path) {
    $script:LimpezaUpdateSelfPath = $MyInvocation.MyCommand.Path
}

function Get-LimpezaFileVersionLabel {
    param(
        [string]$Path,
        [string]$FallbackVersion = '0.0.0'
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $FallbackVersion }
    $fileVersion = (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
    if (-not $fileVersion) { return $FallbackVersion }

    $parts = $fileVersion.Split('.')
    if ($parts.Count -ge 3) {
        return "$($parts[0]).$($parts[1]).$($parts[2])"
    }
    return $fileVersion
}

function Get-LimpezaSystemInstallPath {
    param([string]$AssetName = 'LimpezaWindows.exe')
    Join-Path $env:SystemRoot $AssetName
}

function Test-LimpezaFileUnlocked {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $stream.Close()
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Install-LimpezaUpdatedExecutable {
    <#
    .SYNOPSIS
    Substitui o executavel instalado apos o processo em execucao encerrar (rename + copy + verificacao).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$StagingPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [string]$LogPath,
        [int]$TimeoutSeconds = 90
    )

    $writeLog = {
        param([string]$Message)
        if (-not $LogPath) { return }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $StagingPath)) {
        & $writeLog "Staging ausente: $StagingPath"
        return [PSCustomObject]@{ Success = $false; Error = 'Arquivo baixado nao encontrado.' }
    }

    $backupPath = "$TargetPath.bak"
    $deadline   = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            if ((Test-Path -LiteralPath $TargetPath) -and -not (Test-LimpezaFileUnlocked -Path $TargetPath)) {
                & $writeLog "Aguardando desbloqueio: $TargetPath"
                Start-Sleep -Milliseconds 500
                continue
            }

            if (Test-Path -LiteralPath $TargetPath) {
                if (Test-Path -LiteralPath $backupPath) {
                    Remove-Item -LiteralPath $backupPath -Force
                }
                Rename-Item -LiteralPath $TargetPath -NewName (Split-Path -Leaf $backupPath) -Force
                & $writeLog "Backup criado: $backupPath"
            }

            Copy-Item -LiteralPath $StagingPath -Destination $TargetPath -Force
            & $writeLog "Copia concluida para $TargetPath"

            $installedVersion = Get-LimpezaFileVersionLabel -Path $TargetPath
            if ([version]$installedVersion -lt [version]$ExpectedVersion) {
                throw "Versao instalada ($installedVersion) menor que a esperada ($ExpectedVersion)."
            }

            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $StagingPath -Force -ErrorAction SilentlyContinue

            & $writeLog "Atualizacao OK: v$installedVersion"
            return [PSCustomObject]@{
                Success           = $true
                InstalledVersion  = $installedVersion
                Error             = $null
            }
        }
        catch {
            & $writeLog "Tentativa falhou: $($_.Exception.Message)"
            if (-not (Test-Path -LiteralPath $TargetPath) -and (Test-Path -LiteralPath $backupPath)) {
                Rename-Item -LiteralPath $backupPath -NewName (Split-Path -Leaf $TargetPath) -Force -ErrorAction SilentlyContinue
                & $writeLog 'Backup restaurado apos falha.'
            }
            Start-Sleep -Milliseconds 500
        }
    }

    & $writeLog 'Timeout ao substituir o executavel.'
    return [PSCustomObject]@{
        Success = $false
        Error   = 'Nao foi possivel substituir o executavel (arquivo em uso ou sem permissao).'
    }
}

function Get-LimpezaAppInstallInfo {
    param(
        [string]$AssetName,
        [string]$FallbackVersion,
        [string]$DistFallbackPath,
        [string]$CommandPath
    )

    $systemPath = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $runningExe = $CommandPath -match '\.exe$'

    if ($runningExe -and (Test-Path -LiteralPath $CommandPath)) {
        $executablePath = $CommandPath
    }
    elseif (Test-Path -LiteralPath $systemPath) {
        $executablePath = $systemPath
    }
    elseif ($runningExe) {
        $executablePath = $CommandPath
    }
    else {
        $executablePath = $DistFallbackPath
    }

    [PSCustomObject]@{
        Mode             = if ($runningExe) { 'exe' } else { 'script' }
        ExecutablePath   = $executablePath
        InstallPath      = $systemPath
        InstallDirectory = $env:SystemRoot
        CurrentVersion   = Get-LimpezaFileVersionLabel -Path $executablePath -FallbackVersion $FallbackVersion
    }
}

function Get-LimpezaGitHubLatestRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [hashtable]$Headers
    )

    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    $release = Invoke-RestMethod -Uri $uri -Headers $Headers -TimeoutSec 12 -UseBasicParsing
    $version = ($release.tag_name -replace '^v', '').Trim()
    $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $asset) {
        throw "Arquivo '$AssetName' nao encontrado na release $($release.tag_name)."
    }

    [PSCustomObject]@{
        Version     = $version
        Tag         = $release.tag_name
        DownloadUrl = $asset.browser_download_url
        ReleaseUrl  = $release.html_url
        PublishedAt = $release.published_at
    }
}

function Test-LimpezaUpdateAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion
    )

    [version]$ReleaseVersion -gt [version]$CurrentVersion
}

function Read-LimpezaUpdateChoice {
    while ($true) {
        Write-Host ''
        Write-Host '   [S] Sim — baixar e reiniciar com a nova versao' -ForegroundColor White
        Write-Host '   [N] Nao — continuar a limpeza agora' -ForegroundColor White
        Write-Host ''
        Write-Host -NoNewline '   Digite S ou N e pressione Enter: ' -ForegroundColor Yellow

        $answer = (Read-Host).Trim().ToUpperInvariant()
        if ($answer -in @('S', 'SIM', 'Y', 'YES')) { return $true }
        if ($answer -in @('N', 'NAO', 'NÃO', 'NO')) { return $false }
        Write-Host '   Opcao invalida. Use S para atualizar ou N para continuar.' -ForegroundColor Red
    }
}

function Get-LimpezaUpdateLogPath {
    $logDir = Join-Path $env:ProgramData 'LimpezaWindows\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Join-Path $logDir ("update-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function New-LimpezaUpdaterHelperScript {
    param(
        [Parameter(Mandatory = $true)][string]$StagingPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][int]$ParentProcessId,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$LaunchArgument = '',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$WorkingDirectory = $env:SystemRoot
    )

    $helperPath = Join-Path $env:TEMP "limpeza-updater-$([guid]::NewGuid().ToString('N')).ps1"
    $modulePath = Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'

    $launchBlock = if ($LaunchArgument) {
        "Start-Process -FilePath `$TargetPath -ArgumentList '$($LaunchArgument.Replace("'", "''"))' -WorkingDirectory '$($WorkingDirectory.Replace("'", "''"))'"
    }
    else {
        "Start-Process -FilePath `$TargetPath -WorkingDirectory '$($WorkingDirectory.Replace("'", "''"))'"
    }

    $content = @"
`$ErrorActionPreference = 'Stop'
`$modulePath = '$($modulePath.Replace("'", "''"))'
if (-not (Test-Path -LiteralPath `$modulePath)) {
    Add-Content -LiteralPath '$($LogPath.Replace("'", "''"))' -Value "[`$(Get-Date -Format 'HH:mm:ss')] Modulo LimpezaUpdate.ps1 ausente: `$modulePath" -Encoding UTF8
    exit 1
}
. `$modulePath

try {
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Seconds 1

`$result = Install-LimpezaUpdatedExecutable `
    -StagingPath '$($StagingPath.Replace("'", "''"))' `
    -TargetPath '$($TargetPath.Replace("'", "''"))' `
    -ExpectedVersion '$($ExpectedVersion.Replace("'", "''"))' `
    -LogPath '$($LogPath.Replace("'", "''"))'

if (-not `$result.Success) {
  Add-Content -LiteralPath '$($LogPath.Replace("'", "''"))' -Value "[`$(Get-Date -Format 'HH:mm:ss')] FALHA: `$(`$result.Error)" -Encoding UTF8
  exit 1
}

`$desktop = [Environment]::GetFolderPath('Desktop')
if (`$desktop) {
    `$shortcutPath = Join-Path `$desktop '$($ShortcutName.Replace("'", "''"))'
    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$shortcutPath)
    `$shortcut.TargetPath = '$($TargetPath.Replace("'", "''"))'
    `$shortcut.WorkingDirectory = '$($WorkingDirectory.Replace("'", "''"))'
    `$shortcut.Description = 'Limpeza Avancada do Windows'
    `$shortcut.IconLocation = '$($TargetPath.Replace("'", "''"))',0'
    `$shortcut.Save()
}

$launchBlock
exit 0
"@
    Set-Content -LiteralPath $helperPath -Value $content -Encoding UTF8
    return $helperPath
}

function Sync-LimpezaUpdateModule {
    param([string]$SourceModulePath)

    if (-not (Test-Path -LiteralPath $SourceModulePath)) { return $false }

    $destDir = Join-Path $env:ProgramData 'LimpezaWindows'
    $destPath = Join-Path $destDir 'LimpezaUpdate.ps1'
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $copy = $true
    if (Test-Path -LiteralPath $destPath) {
        $srcItem  = Get-Item -LiteralPath $SourceModulePath
        $destItem = Get-Item -LiteralPath $destPath
        $copy = $srcItem.LastWriteTimeUtc -gt $destItem.LastWriteTimeUtc -or $srcItem.Length -ne $destItem.Length
    }

    if ($copy) {
        Copy-Item -LiteralPath $SourceModulePath -Destination $destPath -Force
    }
    return $true
}

function Install-LimpezaUpdateModuleBesideExecutable {
    param([string]$TargetDirectory = $env:SystemRoot)

    $source = $script:LimpezaUpdateSelfPath
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        $source = Join-Path (Split-Path -Parent $PSCommandPath) 'LimpezaUpdate.ps1'
    }
    if (-not (Test-Path -LiteralPath $source)) { return $false }

    $destPath = Join-Path $TargetDirectory 'LimpezaUpdate.ps1'
    Copy-Item -LiteralPath $source -Destination $destPath -Force -ErrorAction SilentlyContinue
    Sync-LimpezaUpdateModule -SourceModulePath $source | Out-Null
    return $true
}

function Start-LimpezaAppUpdateAndRestart {
    param(
        [Parameter(Mandatory = $true)][object]$Release,
        [string]$RestartArgument = '',
        [switch]$Silent,
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk'
    )

    $targetExe = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $stagingExe = Join-Path $env:TEMP "LimpezaWindows-$([guid]::NewGuid().ToString('N')).exe"
    $logPath = Get-LimpezaUpdateLogPath

    $moduleSource = $script:LimpezaUpdateSelfPath
    if (-not $moduleSource -or -not (Test-Path -LiteralPath $moduleSource)) {
        $moduleSource = Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'
    }
    if (-not (Sync-LimpezaUpdateModule -SourceModulePath $moduleSource)) {
        throw 'Modulo LimpezaUpdate.ps1 nao encontrado para o assistente de atualizacao.'
    }

    if (-not $Silent) {
        Write-Host ''
        Write-Host "   Baixando $AssetName v$($Release.Version)..." -ForegroundColor Cyan
    }

    $prevProgress = $ProgressPreference
    $ProgressPreference = if ($Silent) { 'SilentlyContinue' } else { 'Continue' }
    try {
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $stagingExe -UseBasicParsing
    }
    finally {
        $ProgressPreference = $prevProgress
    }

    if (-not (Test-Path -LiteralPath $stagingExe)) {
        throw 'Download da atualizacao falhou.'
    }

    $downloadedVersion = Get-LimpezaFileVersionLabel -Path $stagingExe -FallbackVersion '0.0.0'
    if ([version]$downloadedVersion -lt [version]$Release.Version) {
        Remove-Item -LiteralPath $stagingExe -Force -ErrorAction SilentlyContinue
        throw "Arquivo baixado invalido (versao $downloadedVersion, esperado $($Release.Version))."
    }

    $helperPs1 = New-LimpezaUpdaterHelperScript `
        -StagingPath $stagingExe `
        -TargetPath $targetExe `
        -ExpectedVersion $Release.Version `
        -ParentProcessId $PID `
        -LogPath $logPath `
        -LaunchArgument $RestartArgument `
        -ShortcutName $ShortcutName `
        -WorkingDirectory $env:SystemRoot

    if (-not $Silent) {
        Write-Host "   Download concluido. Aplicando v$($Release.Version)..." -ForegroundColor Green
        Write-Host '   A limpeza iniciara automaticamente na nova versao.' -ForegroundColor DarkGray
        Write-Host "   Log da atualizacao: $logPath" -ForegroundColor DarkGray
        Write-Host ''
    }

    $helperProc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden',
            '-File', $helperPs1
        ) `
        -WindowStyle Hidden `
        -PassThru

    if (-not $helperProc) {
        throw 'Nao foi possivel iniciar o assistente de atualizacao.'
    }

    exit 0
}

function Invoke-LimpezaAppUpdateCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [Parameter(Mandatory = $true)][string]$AppVersion,
        [Parameter(Mandatory = $true)][string]$DistFallbackPath,
        [Parameter(Mandatory = $true)][string]$CommandPath,
        [Parameter(Mandatory = $true)][hashtable]$ApiHeaders,
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [switch]$ScheduledRun,
        [scriptblock]$WriteUpdatePrompt
    )

    if ($env:LIMPEZA_SKIP_UPDATE -eq '1') { return }

    $install = Get-LimpezaAppInstallInfo `
        -AssetName $AssetName `
        -FallbackVersion $AppVersion `
        -DistFallbackPath $DistFallbackPath `
        -CommandPath $CommandPath

    try {
        $release = Get-LimpezaGitHubLatestRelease -Repo $Repo -AssetName $AssetName -Headers $ApiHeaders
    }
    catch {
        if (-not $ScheduledRun) {
            Write-Host ''
            Write-Host '   Nao foi possivel verificar atualizacoes. Continuando...' -ForegroundColor DarkYellow
            Write-Host ''
        }
        return
    }

    if (-not (Test-LimpezaUpdateAvailable -CurrentVersion $install.CurrentVersion -ReleaseVersion $release.Version)) {
        return
    }

    if ($ScheduledRun) {
        Write-Host "   Nova versao v$($release.Version) detectada (atual: v$($install.CurrentVersion)). Atualizando..." -ForegroundColor Cyan
        Write-Host ''
        try {
            Start-LimpezaAppUpdateAndRestart -Release $release -RestartArgument '-ScheduledRun' -Silent -AssetName $AssetName -ShortcutName $ShortcutName
        }
        catch {
            Write-Host "   Falha na atualizacao automatica. Continuando com v$($install.CurrentVersion)..." -ForegroundColor DarkYellow
            Write-Host ''
        }
        return
    }

    & $WriteUpdatePrompt $install $release

    if (Read-LimpezaUpdateChoice) {
        try {
            Start-LimpezaAppUpdateAndRestart -Release $release -AssetName $AssetName -ShortcutName $ShortcutName
        }
        catch {
            Write-Host ''
            Write-Host "   Falha ao atualizar: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '   Continuando com a versao atual...' -ForegroundColor DarkYellow
            Write-Host ''
        }
    }
    else {
        Write-Host ''
        Write-Host "   Continuando com v$($install.CurrentVersion)..." -ForegroundColor DarkCyan
        Write-Host ''
    }
}
