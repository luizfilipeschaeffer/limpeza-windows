# Compila (opcional) e publica uma release no GitHub com o executavel.
param(
    [ValidateSet('Standard', 'CleanCode')]
    [string]$Edition = 'Standard',
    [string]$Repo = 'luizfilipeschaeffer/limpeza-windows',
    [switch]$SkipBuild,
    [switch]$Draft
)

$ErrorActionPreference = 'Stop'

$projectDir  = Split-Path $PSScriptRoot -Parent
$versionFile = if ($Edition -eq 'CleanCode') {
    Join-Path $projectDir 'config\VERSION.clean-code'
} else {
    Join-Path $projectDir 'config\VERSION'
}

$assetName = if ($Edition -eq 'CleanCode') { 'LimpezaWindows-CleanCode.exe' } else { 'LimpezaWindows.exe' }
$exePath   = Join-Path $projectDir "dist\$assetName"
$buildScript = Join-Path $PSScriptRoot 'build-limpeza.ps1'

if (-not (Test-Path $versionFile)) {
    throw "Arquivo VERSION nao encontrado: $versionFile"
}

$version = (Get-Content $versionFile -Raw).Trim()
$tag     = "v$version"

if (-not $SkipBuild) {
    Write-Host "Compilando executavel ($Edition)..." -ForegroundColor Cyan
    & $buildScript -Edition $Edition
    Write-Host ''
}

if (-not (Test-Path $exePath)) {
    throw "Executavel nao encontrado: $exePath. Rode o build ou use -SkipBuild com o .exe ja gerado."
}

$notesPath = Join-Path $projectDir 'RELEASE_NOTES.md'
if (-not (Test-Path $notesPath)) {
    @"
## Limpeza Avancada do Windows $tag

- Executavel com icone personalizado e elevacao automatica (UAC)
- Limpeza de TEMP, Prefetch, Windows Installer, DISM e cleanmgr

### Como usar

1. Baixe ``$assetName`` desta release
2. Execute como Administrador

Repositorio: https://github.com/$Repo
"@ | Set-Content -Path $notesPath -Encoding UTF8
}

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
gh release view $tag --repo $Repo 2>$null | Out-Null
$releaseExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap

if ($releaseExists) {
    Write-Host "Release $tag ja existe. Enviando asset $assetName..." -ForegroundColor Yellow
    gh release upload $tag $exePath --repo $Repo --clobber
    Write-Host "Asset atualizado na release $tag." -ForegroundColor Green
    return
}

$ghArgs = @(
    'release', 'create', $tag,
    $exePath,
    '--repo', $Repo,
    '--title', "Limpeza Avancada do Windows $tag",
    '--notes-file', $notesPath
)
if ($Draft) { $ghArgs += '--draft' }

Write-Host "Publicando release $tag ($Edition) no GitHub..." -ForegroundColor Cyan
& gh @ghArgs

Write-Host ''
Write-Host 'Release publicada:' -ForegroundColor Green
Write-Host "  https://github.com/$Repo/releases/tag/$tag"
