# Modulo isolado de auto-atualizacao (GitHub Releases).
# Testado por tests/Test-LimpezaUpdate.ps1 — manter em sincronia com o helper gerado.

if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.ps1') {
    $script:LimpezaUpdateSelfPath = $MyInvocation.MyCommand.Path
}

function Test-LimpezaUpdateModuleFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 64) { return $false }

    $header = [System.IO.File]::ReadAllBytes($Path)
    if ($header.Length -ge 2 -and $header[0] -eq 0x4D -and $header[1] -eq 0x5A) {
        return $false
    }

    $match = Select-String -LiteralPath $Path -Pattern 'function\s+Get-LimpezaFileVersionLabel' -SimpleMatch:$false -Quiet
    return [bool]$match
}

function Resolve-LimpezaUpdateModulePath {
    param(
        [string]$CommandPath,
        [string]$ExplicitModulePath
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($ExplicitModulePath) { $candidates.Add($ExplicitModulePath) }
    if ($script:LimpezaUpdateSelfPath) { $candidates.Add($script:LimpezaUpdateSelfPath) }

    if ($CommandPath -match '\.exe$') {
        $candidates.Add((Join-Path (Split-Path -Parent $CommandPath) 'LimpezaUpdate.ps1'))
    }

    $candidates.Add((Join-Path $env:SystemRoot 'LimpezaUpdate.ps1'))
    $candidates.Add((Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'))

    if ($CommandPath -match '\.ps1$') {
        $candidates.Add((Join-Path (Split-Path -Parent $CommandPath) 'LimpezaUpdate.ps1'))
    }

    foreach ($candidate in $candidates) {
        if (Test-LimpezaUpdateModuleFile -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Remove-CorruptLimpezaUpdateModuleCopies {
    $paths = @(
        (Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1')
        (Join-Path $env:SystemRoot 'LimpezaUpdate.ps1')
    )

    foreach ($path in $paths) {
        if ((Test-Path -LiteralPath $path) -and -not (Test-LimpezaUpdateModuleFile -Path $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Import-LimpezaUpdateModuleFromGitHub {
    param([string]$Repo = 'luizfilipeschaeffer/limpeza-windows')

    $destDir  = Join-Path $env:ProgramData 'LimpezaWindows'
    $destPath = Join-Path $destDir 'LimpezaUpdate.ps1'
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $url = "https://raw.githubusercontent.com/$Repo/master/src/LimpezaUpdate.ps1"
    Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing

    if (-not (Test-LimpezaUpdateModuleFile -Path $destPath)) {
        throw 'Download do modulo LimpezaUpdate.ps1 do GitHub retornou arquivo invalido.'
    }

    return $destPath
}

function Ensure-LimpezaUpdateModuleDeployed {
    param(
        [string]$CommandPath,
        [string]$ExplicitModulePath,
        [string]$Repo = 'luizfilipeschaeffer/limpeza-windows'
    )

    Remove-CorruptLimpezaUpdateModuleCopies

    $source = Resolve-LimpezaUpdateModulePath -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath
    if (-not $source) {
        try {
            $source = Import-LimpezaUpdateModuleFromGitHub -Repo $Repo
        }
        catch {
            return $null
        }
    }

    Sync-LimpezaUpdateModule -SourceModulePath $source | Out-Null

    if ($CommandPath -match '\.exe$') {
        $besideExe = Join-Path (Split-Path -Parent $CommandPath) 'LimpezaUpdate.ps1'
        if (-not (Test-SameFilePath -PathA $source -PathB $besideExe)) {
            Copy-Item -LiteralPath $source -Destination $besideExe -Force -ErrorAction SilentlyContinue
        }
    }

    $systemModule = Join-Path $env:SystemRoot 'LimpezaUpdate.ps1'
    if (-not (Test-SameFilePath -PathA $source -PathB $systemModule)) {
        Copy-Item -LiteralPath $source -Destination $systemModule -Force -ErrorAction SilentlyContinue
    }

    return $source
}

function Test-SameFilePath {
    param([string]$PathA, [string]$PathB)

    if (-not $PathA -or -not $PathB) { return $false }
    try {
        return [System.IO.Path]::GetFullPath($PathA).Equals(
            [System.IO.Path]::GetFullPath($PathB),
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {
        return $false
    }
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
    param([string]$Prefix = 'update')

    $logDir = Join-Path $env:ProgramData 'LimpezaWindows\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Join-Path $logDir ("{0}-{1}.log" -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function New-LimpezaUpdaterHelperScript {
    param(
        [Parameter(Mandatory = $true)][string]$StagingPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][int]$ParentProcessId,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$ModuleSourcePath,
        [string]$LaunchArgument = '',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$WorkingDirectory = $env:SystemRoot
    )

    if (-not (Test-LimpezaUpdateModuleFile -Path $ModuleSourcePath)) {
        throw "Modulo de atualizacao invalido: $ModuleSourcePath"
    }

    $modulePathEscaped = $ModuleSourcePath.Replace("'", "''")
    $helperPath = Join-Path $env:TEMP "limpeza-updater-$([guid]::NewGuid().ToString('N')).ps1"

    $launchBlock = if ($LaunchArgument) {
        "Start-Process -FilePath `$TargetPath -ArgumentList '$($LaunchArgument.Replace("'", "''"))' -WorkingDirectory '$($WorkingDirectory.Replace("'", "''"))'"
    }
    else {
        "Start-Process -FilePath `$TargetPath -WorkingDirectory '$($WorkingDirectory.Replace("'", "''"))'"
    }

    $content = @"
`$ErrorActionPreference = 'Stop'
. '$modulePathEscaped'

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

    if (-not (Test-LimpezaUpdateModuleFile -Path $SourceModulePath)) { return $false }

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
    param(
        [string]$TargetDirectory = $env:SystemRoot,
        [string]$CommandPath = $PSCommandPath,
        [string]$ExplicitModulePath
    )

    $source = Ensure-LimpezaUpdateModuleDeployed -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath
    if (-not $source) { return $false }

    $destPath = Join-Path $TargetDirectory 'LimpezaUpdate.ps1'
    if (-not (Test-SameFilePath -PathA $source -PathB $destPath)) {
        Copy-Item -LiteralPath $source -Destination $destPath -Force -ErrorAction SilentlyContinue
    }
    return $true
}

function Start-LimpezaAppUpdateAndRestart {
    param(
        [Parameter(Mandatory = $true)][object]$Release,
        [string]$RestartArgument = '',
        [switch]$Silent,
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$CommandPath = $PSCommandPath,
        [string]$ExplicitModulePath,
        [string]$Repo = 'luizfilipeschaeffer/limpeza-windows'
    )

    $targetExe = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $stagingExe = Join-Path $env:TEMP "LimpezaWindows-$([guid]::NewGuid().ToString('N')).exe"
    $logPath = Get-LimpezaUpdateLogPath

    $moduleSource = Ensure-LimpezaUpdateModuleDeployed `
        -CommandPath $CommandPath `
        -ExplicitModulePath $ExplicitModulePath `
        -Repo $Repo

    if (-not $moduleSource) {
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
        -ModuleSourcePath $moduleSource `
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
        [string]$ExplicitModulePath,
        [switch]$ScheduledRun,
        [scriptblock]$WriteUpdatePrompt
    )

    if ($env:LIMPEZA_SKIP_UPDATE -eq '1') { return }

    Ensure-LimpezaUpdateModuleDeployed -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath -Repo $Repo | Out-Null

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
            Start-LimpezaAppUpdateAndRestart -Release $release -RestartArgument '-ScheduledRun' -Silent -AssetName $AssetName -ShortcutName $ShortcutName -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath -Repo $Repo
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
            Start-LimpezaAppUpdateAndRestart -Release $release -AssetName $AssetName -ShortcutName $ShortcutName -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath -Repo $Repo
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

function Get-LimpezaInstallArtifactPaths {
    param(
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk'
    )

    $systemExe = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $paths   = [System.Collections.Generic.List[string]]::new()
    $paths.Add($systemExe)
    $paths.Add((Join-Path $env:SystemRoot 'LimpezaUpdate.ps1'))
    $paths.Add((Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'))

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $paths.Add((Join-Path $desktop $ShortcutName))
    }

    return $paths.ToArray()
}

function Test-LimpezaInstalledInSystem {
    param([string]$AssetName = 'LimpezaWindows.exe')
    Test-Path -LiteralPath (Get-LimpezaSystemInstallPath -AssetName $AssetName)
}

function Remove-LimpezaDesktopShortcut {
    param([string]$ShortcutName = 'Limpeza Avancada do Windows.lnk')

    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { return }

    $shortcutPath = Join-Path $desktop $ShortcutName
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }
}

function Remove-LimpezaInstalledScheduledTask {
    param([string]$TaskName = 'Limpeza Avancada do Windows')

    schtasks /End /TN $TaskName 2>$null | Out-Null
    & schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
}

function Remove-LimpezaInstalledArtifacts {
    param(
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$ScheduledTaskName = 'Limpeza Avancada do Windows',
        [string]$CommandPath = $PSCommandPath
    )

    $systemExe = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $skipExe   = $false

    if ($CommandPath -match '\.exe$' -and (Test-Path -LiteralPath $systemExe)) {
        try {
            $skipExe = [System.IO.Path]::GetFullPath($CommandPath).Equals(
                [System.IO.Path]::GetFullPath($systemExe),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
        catch { }
    }

    Remove-LimpezaInstalledScheduledTask -TaskName $ScheduledTaskName
    Remove-LimpezaDesktopShortcut -ShortcutName $ShortcutName

    foreach ($path in (Get-LimpezaInstallArtifactPaths -AssetName $AssetName -ShortcutName $ShortcutName)) {
        if ($skipExe -and (Test-SameFilePath -PathA $path -PathB $systemExe)) { continue }
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    $programDataDir = Join-Path $env:ProgramData 'LimpezaWindows'
    if (Test-Path -LiteralPath $programDataDir) {
        Remove-Item -LiteralPath $programDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-LimpezaUninstallHelperScript {
    param(
        [Parameter(Mandatory = $true)][int]$ParentProcessId,
        [Parameter(Mandatory = $true)][string]$SystemExe,
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [Parameter(Mandatory = $true)][string]$ScheduledTaskName,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $helperPath = Join-Path $env:TEMP "limpeza-uninstall-$([guid]::NewGuid().ToString('N')).ps1"
    $systemModule = Join-Path $env:SystemRoot 'LimpezaUpdate.ps1'
    $programDataDir = Join-Path $env:ProgramData 'LimpezaWindows'

    $content = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$log = '$($LogPath.Replace("'", "''"))'

function Write-UninstallLog([string]`$Message) {
    Add-Content -LiteralPath `$log -Value "[`$(Get-Date -Format 'HH:mm:ss')] `$Message" -Encoding UTF8
}

try {
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Seconds 1

Write-UninstallLog 'Iniciando desinstalacao...'
schtasks /End /TN '$($ScheduledTaskName.Replace("'", "''"))' 2>`$null | Out-Null
schtasks.exe /Delete /TN '$($ScheduledTaskName.Replace("'", "''"))' /F 2>`$null | Out-Null
Write-UninstallLog 'Tarefa agendada removida (se existia).'

`$desktop = [Environment]::GetFolderPath('Desktop')
if (`$desktop) {
    `$shortcut = Join-Path `$desktop '$($ShortcutName.Replace("'", "''"))'
    if (Test-Path -LiteralPath `$shortcut) {
        Remove-Item -LiteralPath `$shortcut -Force
        Write-UninstallLog "Atalho removido: `$shortcut"
    }
}

`$targets = @(
    '$($SystemExe.Replace("'", "''"))',
    '$($systemModule.Replace("'", "''"))',
    (Join-Path '$($programDataDir.Replace("'", "''"))' 'LimpezaUpdate.ps1')
)

foreach (`$target in `$targets) {
    if (-not (Test-Path -LiteralPath `$target)) { continue }
    `$retries = 0
    while ((Test-Path -LiteralPath `$target) -and (`$retries -lt 30)) {
        Remove-Item -LiteralPath `$target -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath `$target) { Start-Sleep -Milliseconds 400 }
        `$retries++
    }
    if (Test-Path -LiteralPath `$target) {
        Write-UninstallLog "AVISO: nao foi possivel remover `$target"
    }
    else {
        Write-UninstallLog "Removido: `$target"
    }
}

if (Test-Path -LiteralPath '$($programDataDir.Replace("'", "''"))') {
    Remove-Item -LiteralPath '$($programDataDir.Replace("'", "''"))' -Recurse -Force -ErrorAction SilentlyContinue
    Write-UninstallLog 'Pasta ProgramData\LimpezaWindows removida.'
}

Write-UninstallLog 'Desinstalacao concluida.'
exit 0
"@

    Set-Content -LiteralPath $helperPath -Value $content -Encoding UTF8
    return $helperPath
}

function Start-LimpezaAppUninstallAndExit {
    param(
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$ScheduledTaskName = 'Limpeza Avancada do Windows',
        [string]$CommandPath = $PSCommandPath
    )

    $systemExe = Get-LimpezaSystemInstallPath -AssetName $AssetName
    $logPath   = Get-LimpezaUpdateLogPath -Prefix 'uninstall'

    $runningFromSystem = $false
    if ($CommandPath -match '\.exe$' -and (Test-Path -LiteralPath $systemExe)) {
        try {
            $runningFromSystem = [System.IO.Path]::GetFullPath($CommandPath).Equals(
                [System.IO.Path]::GetFullPath($systemExe),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
        catch { }
    }

    Write-Host ''
    Write-Host '   Removendo instalacao do Windows...' -ForegroundColor Yellow

    if ($runningFromSystem) {
        $helperPs1 = New-LimpezaUninstallHelperScript `
            -ParentProcessId $PID `
            -SystemExe $systemExe `
            -ShortcutName $ShortcutName `
            -ScheduledTaskName $ScheduledTaskName `
            -LogPath $logPath

        Write-Host '   O programa sera encerrado para concluir a remocao.' -ForegroundColor DarkGray
        Write-Host "   Log: $logPath" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '   Para usar novamente, execute o .exe da pasta dist ou baixe do GitHub.' -ForegroundColor Cyan
        Write-Host ''

        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $helperPs1) `
            -WindowStyle Hidden | Out-Null

        exit 0
    }

    Remove-LimpezaInstalledArtifacts `
        -AssetName $AssetName `
        -ShortcutName $ShortcutName `
        -ScheduledTaskName $ScheduledTaskName `
        -CommandPath $CommandPath

    Write-Host '   Instalacao removida com sucesso.' -ForegroundColor Green
    Write-Host '   Voce pode instalar de novo executando o .exe da pasta dist ou o instalador do GitHub.' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

function Show-LimpezaStartupMenu {
    param(
        [object]$Install,
        [bool]$InstalledInSystem,
        [bool]$UpdateAvailable,
        [object]$Release
    )

    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host '           LIMPEZA AVANCADA DO WINDOWS' -ForegroundColor Cyan
    Write-Host '  ======================================================' -ForegroundColor Cyan
    Write-Host ''

    if ($InstalledInSystem) {
        Write-Host "   Instalado em  : $($Install.InstallPath)" -ForegroundColor White
    }
    else {
        Write-Host '   Instalacao em C:\Windows : (ainda nao instalado)' -ForegroundColor DarkGray
    }

    Write-Host "   Versao atual  : v$($Install.CurrentVersion)" -ForegroundColor White

    if ($UpdateAvailable -and $Release) {
        Write-Host "   Nova versao   : v$($Release.Version) ($($Release.Tag))" -ForegroundColor Green
    }
    else {
        Write-Host '   Atualizacao    : voce ja esta na ultima versao publicada' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  ------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   Escolha uma opcao ANTES de iniciar a limpeza:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '   [1] Continuar com a limpeza' -ForegroundColor White

    if ($UpdateAvailable) {
        Write-Host ("   [2] Atualizar para v{0} e reiniciar" -f $Release.Version) -ForegroundColor Green
    }

    if ($InstalledInSystem) {
        Write-Host '   [3] Desinstalar (remove de C:\Windows, atalho e agendamento)' -ForegroundColor DarkYellow
    }

    Write-Host '   [0] Sair sem executar nada' -ForegroundColor DarkGray
    Write-Host ''
}

function Read-LimpezaStartupMenuChoice {
    param(
        [bool]$UpdateAvailable,
        [bool]$InstalledInSystem
    )

    while ($true) {
        Write-Host -NoNewline '   Digite 0, 1' -ForegroundColor Yellow
        if ($UpdateAvailable) { Write-Host -NoNewline ', 2' -ForegroundColor Yellow }
        if ($InstalledInSystem) { Write-Host -NoNewline ' ou 3' -ForegroundColor Yellow }
        Write-Host -NoNewline ': ' -ForegroundColor Yellow

        $answer = (Read-Host).Trim()

        switch ($answer) {
            '0' { return 'Exit' }
            '1' { return 'Continue' }
            '2' {
                if ($UpdateAvailable) { return 'Update' }
            }
            '3' {
                if ($InstalledInSystem) { return 'Uninstall' }
            }
        }

        Write-Host '   Opcao invalida. Tente novamente.' -ForegroundColor Red
    }
}

function Invoke-LimpezaStartupDecision {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [Parameter(Mandatory = $true)][string]$AppVersion,
        [Parameter(Mandatory = $true)][string]$DistFallbackPath,
        [Parameter(Mandatory = $true)][string]$CommandPath,
        [Parameter(Mandatory = $true)][hashtable]$ApiHeaders,
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [Parameter(Mandatory = $true)][string]$ScheduledTaskName,
        [string]$ExplicitModulePath,
        [switch]$ScheduledRun
    )

    if ($ScheduledRun) {
        if ($env:LIMPEZA_SKIP_UPDATE -ne '1') {
            Invoke-LimpezaAppUpdateCheck `
                -Repo $Repo `
                -AssetName $AssetName `
                -AppVersion $AppVersion `
                -DistFallbackPath $DistFallbackPath `
                -CommandPath $CommandPath `
                -ApiHeaders $ApiHeaders `
                -ShortcutName $ShortcutName `
                -ExplicitModulePath $ExplicitModulePath `
                -ScheduledRun
        }
        return
    }

    if ($env:LIMPEZA_SKIP_UPDATE -eq '1' -and $env:LIMPEZA_SKIP_STARTUP_MENU -eq '1') {
        return
    }

    Ensure-LimpezaUpdateModuleDeployed -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath -Repo $Repo | Out-Null

    $install = Get-LimpezaAppInstallInfo `
        -AssetName $AssetName `
        -FallbackVersion $AppVersion `
        -DistFallbackPath $DistFallbackPath `
        -CommandPath $CommandPath

    $installedInSystem = Test-LimpezaInstalledInSystem -AssetName $AssetName
    $release           = $null
    $updateAvailable   = $false

    try {
        $release = Get-LimpezaGitHubLatestRelease -Repo $Repo -AssetName $AssetName -Headers $ApiHeaders
        $updateAvailable = Test-LimpezaUpdateAvailable -CurrentVersion $install.CurrentVersion -ReleaseVersion $release.Version
    }
    catch {
        Write-Host ''
        Write-Host '   Nao foi possivel verificar atualizacoes no GitHub.' -ForegroundColor DarkYellow
        Write-Host '   Voce ainda pode continuar ou desinstalar a copia local.' -ForegroundColor DarkGray
        Write-Host ''
    }

    Show-LimpezaStartupMenu -Install $install -InstalledInSystem $installedInSystem -UpdateAvailable $updateAvailable -Release $release

    switch (Read-LimpezaStartupMenuChoice -UpdateAvailable $updateAvailable -InstalledInSystem $installedInSystem) {
        'Exit' {
            Write-Host '   Saindo sem executar a limpeza.' -ForegroundColor DarkGray
            Write-Host ''
            exit 0
        }
        'Uninstall' {
            Start-LimpezaAppUninstallAndExit `
                -AssetName $AssetName `
                -ShortcutName $ShortcutName `
                -ScheduledTaskName $ScheduledTaskName `
                -CommandPath $CommandPath
        }
        'Update' {
            if (-not $release) {
                Write-Host '   Atualizacao indisponivel no momento.' -ForegroundColor Red
                Write-Host ''
                return
            }
            try {
                Start-LimpezaAppUpdateAndRestart `
                    -Release $release `
                    -AssetName $AssetName `
                    -ShortcutName $ShortcutName `
                    -CommandPath $CommandPath `
                    -ExplicitModulePath $ExplicitModulePath `
                    -Repo $Repo
            }
            catch {
                Write-Host ''
                Write-Host "   Falha ao atualizar: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host '   Pressione qualquer tecla para voltar ao menu ou feche a janela.' -ForegroundColor DarkYellow
                Write-Host ''
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                Invoke-LimpezaStartupDecision `
                    -Repo $Repo `
                    -AssetName $AssetName `
                    -AppVersion $AppVersion `
                    -DistFallbackPath $DistFallbackPath `
                    -CommandPath $CommandPath `
                    -ApiHeaders $ApiHeaders `
                    -ShortcutName $ShortcutName `
                    -ScheduledTaskName $ScheduledTaskName `
                    -ExplicitModulePath $ExplicitModulePath
            }
        }
        default {
            Write-Host ''
            Write-Host "   Continuando com v$($install.CurrentVersion)..." -ForegroundColor DarkCyan
            Write-Host ''
        }
    }
}
