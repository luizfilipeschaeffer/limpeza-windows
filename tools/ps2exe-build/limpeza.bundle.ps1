# Modulo isolado de auto-atualizacao (GitHub Releases).
# Testado por tests/Test-LimpezaUpdate.ps1 â€” manter em sincronia com o helper gerado.

if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.ps1') {
    $script:LimpezaUpdateSelfPath = $MyInvocation.MyCommand.Path
}

function Get-LimpezaProgramDataRoot {
    $edition = if ($script:LimpezaProductEdition) { $script:LimpezaProductEdition } else { 'Standard' }
    $folder  = if ($edition -eq 'CleanCode') { 'LimpezaWindows-CleanCode' } else { 'LimpezaWindows' }
    Join-Path $env:ProgramData $folder
}

function Get-LimpezaEditionProfile {
    param(
        [ValidateSet('Standard', 'CleanCode')]
        [string]$Edition = 'Standard'
    )

    switch ($Edition) {
        'CleanCode' {
            [PSCustomObject]@{
                Edition                 = 'CleanCode'
                UpdateAssetName         = 'LimpezaWindows-CleanCode.exe'
                LegacyShortcutName      = 'Limpeza Avancada do Windows (Clean Code).lnk'
                LegacyScheduledTaskName = 'Limpeza Avancada do Windows (Clean Code)'
                LegacySystemAssetName   = 'LimpezaWindows-CleanCode.exe'
                DisplaySuffix           = ' (Clean Code)'
                GitHubUserAgent         = 'LimpezaWindows-CleanCode'
                ProductTitle            = 'Limpeza Avancada do Windows (Clean Code)'
            }
        }
        default {
            [PSCustomObject]@{
                Edition                 = 'Standard'
                UpdateAssetName         = 'LimpezaWindows.exe'
                LegacyShortcutName      = 'Limpeza Avancada do Windows.lnk'
                LegacyScheduledTaskName = 'Limpeza Avancada do Windows'
                LegacySystemAssetName   = 'LimpezaWindows.exe'
                DisplaySuffix           = ''
                GitHubUserAgent         = 'LimpezaWindows'
                ProductTitle            = 'Limpeza Avancada do Windows'
            }
        }
    }
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
    $candidates.Add((Join-Path (Get-LimpezaProgramDataRoot) 'LimpezaUpdate.ps1'))
    $candidates.Add((Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'))
    $candidates.Add((Join-Path (Join-Path $env:ProgramData 'LimpezaWindows-CleanCode') 'LimpezaUpdate.ps1'))

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
        (Join-Path (Get-LimpezaProgramDataRoot) 'LimpezaUpdate.ps1')
        (Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1')
        (Join-Path (Join-Path $env:ProgramData 'LimpezaWindows-CleanCode') 'LimpezaUpdate.ps1')
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

    $destDir  = Get-LimpezaProgramDataRoot
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

function Resolve-LimpezaUpdateTargetExe {
    param(
        [string]$CommandPath = $PSCommandPath,
        [string]$DistFallbackPath
    )

    if ($CommandPath -match '\.exe$' -and (Test-Path -LiteralPath $CommandPath)) {
        return $CommandPath
    }

    if ($DistFallbackPath -and (Test-Path -LiteralPath $DistFallbackPath)) {
        return $DistFallbackPath
    }

    return $CommandPath
}

function Get-LimpezaAppInstallInfo {
    param(
        [string]$FallbackVersion,
        [string]$DistFallbackPath,
        [string]$CommandPath
    )

    $runningExe = $CommandPath -match '\.exe$'
    $executablePath = Resolve-LimpezaUpdateTargetExe -CommandPath $CommandPath -DistFallbackPath $DistFallbackPath

    [PSCustomObject]@{
        Mode           = if ($runningExe) { 'exe' } else { 'script' }
        ExecutablePath = $executablePath
        CurrentVersion = Get-LimpezaFileVersionLabel -Path $executablePath -FallbackVersion $FallbackVersion
    }
}

function Get-LimpezaGitHubLatestRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [hashtable]$Headers,
        [int]$PerPage = 30
    )

    $uri = "https://api.github.com/repos/$Repo/releases?per_page=$PerPage"
    $releases = Invoke-RestMethod -Uri $uri -Headers $Headers -TimeoutSec 15 -UseBasicParsing

    foreach ($release in $releases) {
        if ($release.draft) { continue }

        $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
        if (-not $asset) { continue }

        $version = ($release.tag_name -replace '^v', '').Trim()
        return [PSCustomObject]@{
            Version     = $version
            Tag         = $release.tag_name
            DownloadUrl = $asset.browser_download_url
            ReleaseUrl  = $release.html_url
            PublishedAt = $release.published_at
        }
    }

    throw "Nenhuma release publicada contem o asset '$AssetName'."
}

function Test-LimpezaUpdateAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion
    )

    [version]$ReleaseVersion -gt [version]$CurrentVersion
}

function Get-LimpezaUpdateLogPath {
    param([string]$Prefix = 'update')

    $logDir = Join-Path (Get-LimpezaProgramDataRoot) 'logs'
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
        [string]$WorkingDirectory
    )

    if (-not (Test-LimpezaUpdateModuleFile -Path $ModuleSourcePath)) {
        throw "Modulo de atualizacao invalido: $ModuleSourcePath"
    }

    if (-not $WorkingDirectory) {
        $WorkingDirectory = Split-Path -Parent $TargetPath
    }

    $modulePathEscaped = $ModuleSourcePath.Replace("'", "''")
    $helperPath = Join-Path $env:TEMP "limpeza-updater-$([guid]::NewGuid().ToString('N')).ps1"

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

Start-Process -FilePath '$($TargetPath.Replace("'", "''"))' -WorkingDirectory '$($WorkingDirectory.Replace("'", "''"))'
exit 0
"@
    Set-Content -LiteralPath $helperPath -Value $content -Encoding UTF8
    return $helperPath
}

function Sync-LimpezaUpdateModule {
    param([string]$SourceModulePath)

    if (-not (Test-LimpezaUpdateModuleFile -Path $SourceModulePath)) { return $false }

    $destDir = Get-LimpezaProgramDataRoot
    $destPath = Join-Path $destDir 'LimpezaUpdate.ps1'
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $copy = $true
    if (Test-Path -LiteralPath $destPath) {
        $srcItem  = Get-Item -LiteralPath $SourceModulePath
        $destItem = Get-Item -LiteralPath $destPath
        $copy = $srcItem.LastWriteTimeUtc -gt $destItem.LastWriteTimeUtc -or $srcItem.Length -ne $destItem.Length
    }

    if ($copy) {
        try {
            Copy-Item -LiteralPath $SourceModulePath -Destination $destPath -Force -ErrorAction Stop
        }
        catch {
            return $false
        }
    }
    return $true
}

function Start-LimpezaAppUpdateAndRestart {
    param(
        [Parameter(Mandatory = $true)][object]$Release,
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$CommandPath = $PSCommandPath,
        [string]$DistFallbackPath,
        [string]$ExplicitModulePath,
        [string]$Repo = 'luizfilipeschaeffer/limpeza-windows'
    )

    $targetExe = Resolve-LimpezaUpdateTargetExe -CommandPath $CommandPath -DistFallbackPath $DistFallbackPath
    $workingDir = Split-Path -Parent $targetExe
    $stagingExe = Join-Path $env:TEMP "$([System.IO.Path]::GetFileNameWithoutExtension($AssetName))-$([guid]::NewGuid().ToString('N')).exe"
    $logPath = Get-LimpezaUpdateLogPath

    $moduleSource = Ensure-LimpezaUpdateModuleDeployed `
        -CommandPath $CommandPath `
        -ExplicitModulePath $ExplicitModulePath `
        -Repo $Repo

    if (-not $moduleSource) {
        throw 'Modulo LimpezaUpdate.ps1 nao encontrado para o assistente de atualizacao.'
    }

    Write-Host ''
    Write-Host "   Baixando $AssetName v$($Release.Version)..." -ForegroundColor Cyan

    $prevProgress = $ProgressPreference
    $ProgressPreference = 'Continue'
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
        -WorkingDirectory $workingDir

    Write-Host "   Download concluido. Aplicando v$($Release.Version)..." -ForegroundColor Green
    Write-Host '   A limpeza iniciara automaticamente na nova versao.' -ForegroundColor DarkGray
    Write-Host "   Log da atualizacao: $logPath" -ForegroundColor DarkGray
    Write-Host ''

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
        [string]$ExplicitModulePath
    )

    if ($env:LIMPEZA_SKIP_UPDATE -eq '1') { return }

    Ensure-LimpezaUpdateModuleDeployed -CommandPath $CommandPath -ExplicitModulePath $ExplicitModulePath -Repo $Repo | Out-Null

    $install = Get-LimpezaAppInstallInfo `
        -FallbackVersion $AppVersion `
        -DistFallbackPath $DistFallbackPath `
        -CommandPath $CommandPath

    try {
        $release = Get-LimpezaGitHubLatestRelease -Repo $Repo -AssetName $AssetName -Headers $ApiHeaders
    }
    catch {
        Write-Host ''
        Write-Host '   Nao foi possivel verificar atualizacoes. Continuando...' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if (-not (Test-LimpezaUpdateAvailable -CurrentVersion $install.CurrentVersion -ReleaseVersion $release.Version)) {
        return
    }

    Write-Host ''
    Write-Host "   Nova versao v$($release.Version) detectada (atual: v$($install.CurrentVersion)). Atualizando..." -ForegroundColor Cyan
    Write-Host ''

    try {
        Start-LimpezaAppUpdateAndRestart `
            -Release $release `
            -AssetName $AssetName `
            -CommandPath $CommandPath `
            -DistFallbackPath $DistFallbackPath `
            -ExplicitModulePath $ExplicitModulePath `
            -Repo $Repo
    }
    catch {
        Write-Host "   Falha na atualizacao automatica. Continuando com v$($install.CurrentVersion)..." -ForegroundColor DarkYellow
        Write-Host "   $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Get-LimpezaLegacyArtifactPaths {
    param(
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk'
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add((Get-LimpezaSystemInstallPath -AssetName $AssetName))
    $paths.Add((Join-Path $env:SystemRoot 'LimpezaUpdate.ps1'))

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $paths.Add((Join-Path $desktop $ShortcutName))
    }

    return $paths.ToArray()
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

function Invoke-LimpezaLegacyCleanup {
    param(
        [string]$AssetName = 'LimpezaWindows.exe',
        [string]$ShortcutName = 'Limpeza Avancada do Windows.lnk',
        [string]$ScheduledTaskName = 'Limpeza Avancada do Windows',
        [string]$CommandPath = $PSCommandPath
    )

    Remove-LimpezaInstalledScheduledTask -TaskName $ScheduledTaskName
    Remove-LimpezaDesktopShortcut -ShortcutName $ShortcutName

    foreach ($path in (Get-LimpezaLegacyArtifactPaths -AssetName $AssetName -ShortcutName $ShortcutName)) {
        if ($CommandPath -match '\.exe$' -and (Test-SameFilePath -PathA $path -PathB $CommandPath)) {
            continue
        }
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}


#Requires -RunAsAdministrator

param(
    [switch]$SkipDevCaches,
    [switch]$SkipNode,
    [switch]$SkipPython,
    [switch]$SkipDocker
)

# Limpeza Avancada do Windows v2.4.0
# Autor: Luiz Filipe Schaeffer

$script:ProductEdition = 'CleanCode'
if ($env:LIMPEZA_PRODUCT_EDITION -eq 'CleanCode') {
    $script:ProductEdition = 'CleanCode'
}
$AppVersion = '2.4.0'
$script:CleanupLog = [System.Collections.Generic.List[object]]::new()
$GitHubRepo = 'luizfilipeschaeffer/limpeza-windows'

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Get-LimpezaWindowTitle {
    $suffix = if ($script:EditionProfile) { $script:EditionProfile.DisplaySuffix } else { '' }
    "$(E 0x1F9F9) Limpeza Avancada do Windows$suffix v$AppVersion"
}

function Initialize-Console {
    try { chcp 65001 | Out-Null } catch {}
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding  = $utf8
    $global:OutputEncoding    = $utf8
    $Host.UI.RawUI.WindowTitle = Get-LimpezaWindowTitle
    Clear-Host
}

function E([int]$CodePoint) {
    [char]::ConvertFromUtf32($CodePoint)
}

$script:GitHubApiHeaders = @{
    'User-Agent' = 'LimpezaWindows'
    'Accept'     = 'application/vnd.github+json'
}

# Modulo LimpezaUpdate embarcado no build
Sync-LimpezaUpdateModule -SourceModulePath $script:LimpezaUpdateSelfPath | Out-Null

function Get-FileVersionLabel {
    param([string]$Path)
    Get-LimpezaFileVersionLabel -Path $Path -FallbackVersion $AppVersion
}

function Write-Banner {
    param([string[]]$Lines, [ConsoleColor]$Color = 'Cyan')
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor $Color
    foreach ($line in $Lines) { Write-Host "  $line" -ForegroundColor $Color }
    Write-Host '  ======================================================' -ForegroundColor $Color
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

function Invoke-FinalSummaryScreen {
    param(
        [long]$FreeBefore,
        [long]$FreeAfter,
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    Clear-Host
    try { chcp 65001 | Out-Null } catch {}
    $Host.UI.RawUI.WindowTitle = Get-LimpezaWindowTitle

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

# --- Execucao principal ---

Initialize-Console

$script:DistFallbackExe = Join-Path (Split-Path $PSScriptRoot -Parent) "dist\$script:UpdateAssetName"

Invoke-LimpezaLegacyCleanup `
    -AssetName $script:UpdateAssetName `
    -ShortcutName $script:LegacyShortcutName `
    -ScheduledTaskName $script:LegacyScheduledTaskName `
    -CommandPath $PSCommandPath

Invoke-LimpezaAppUpdateCheck `
    -Repo $GitHubRepo `
    -AssetName $script:UpdateAssetName `
    -AppVersion $AppVersion `
    -DistFallbackPath $script:DistFallbackExe `
    -CommandPath $PSCommandPath `
    -ExplicitModulePath $script:LimpezaUpdateModulePath `
    -ApiHeaders $script:GitHubApiHeaders

$startTime  = Get-Date
$freeBefore = Get-DriveCFreeBytes

$gbFree      = [math]::Round($freeBefore / 1GB, 2)
$drive       = Get-PSDrive C
$total       = $drive.Used + $drive.Free
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
Write-StepHeader -Number 11 -Total $stepTotal -Icon 0x1F4BF -Title 'Limpeza de Disco (cleanmgr)'
Write-Host "       $(E 0x1FA9F) Abrindo o assistente..."
Write-Host ''
& cleanmgr /sagerun:1
$cleanmgrCode = $LASTEXITCODE
Write-StepResult -ExitCode $cleanmgrCode
$cleanmgrStatus = if ($cleanmgrCode -ge 8) { 'Parcial' } elseif ($cleanmgrCode -eq 0) { 'Limpo' } else { 'Erro' }
Add-CleanupLogEntry -Category 'Windows' -Target 'cleanmgr /sagerun:1' -Status $cleanmgrStatus -Detail 'Assistente de limpeza de disco'

$freeAfter = Get-DriveCFreeBytes
$endTime   = Get-Date

Invoke-FinalSummaryScreen -FreeBefore $freeBefore -FreeAfter $freeAfter -StartTime $startTime -EndTime $endTime

if (Test-Path $emptyFolder) {
    Remove-Item -Path $emptyFolder -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "   $(E 0x1F44B) Pressione qualquer tecla para sair..."
Write-Host ''
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

