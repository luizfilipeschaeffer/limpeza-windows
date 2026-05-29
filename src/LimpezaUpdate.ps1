# Modulo isolado de auto-atualizacao (GitHub Releases).
# Testado por tests/Test-LimpezaUpdate.ps1 — manter em sincronia com o helper gerado.

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
