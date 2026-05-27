$ErrorActionPreference = 'Stop'

$projectDir = Split-Path $PSScriptRoot -Parent
$versionFile = Join-Path $projectDir 'config\VERSION'
$appVersion = if (Test-Path $versionFile) {
    (Get-Content $versionFile -Raw).Trim()
} else {
    '2.0.0.0'
}
if ($appVersion -notmatch '\.\d+$') {
    $appVersion = "$appVersion.0"
}
$buildDir   = Join-Path $projectDir 'tools\ps2exe-build'
$sourcePs1  = Join-Path $projectDir 'src\limpeza.ps1'
$iconFile   = Join-Path $projectDir 'assets\limpeza-icon.ico'
$outputExe  = Join-Path $projectDir 'dist\LimpezaWindows.exe'
$compiler   = Join-Path $buildDir 'ps2exe.ps1'
$compilerUrl = 'https://raw.githubusercontent.com/MScholtes/PS2EXE/master/Module/ps2exe.ps1'

if (-not (Test-Path $sourcePs1)) {
    throw "Arquivo nao encontrado: $sourcePs1"
}

if (-not (Test-Path $iconFile)) {
    throw "Icone nao encontrado: $iconFile"
}

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $outputExe -Parent) -Force | Out-Null

$prepareIcon = Join-Path $PSScriptRoot 'prepare-icon.ps1'
if (Test-Path $prepareIcon) {
    Write-Host 'Preparando icone multi-resolucao (dimensoes nativas)...' -ForegroundColor Cyan
    & $prepareIcon
    Write-Host ''
}

if (-not (Test-Path $compiler)) {
    Write-Host 'Baixando compilador ps2exe...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $compilerUrl -OutFile $compiler -UseBasicParsing
}

Write-Host 'Compilando LimpezaWindows.exe com icone personalizado...' -ForegroundColor Cyan

. $compiler
Invoke-ps2exe `
    -inputFile $sourcePs1 `
    -outputFile $outputExe `
    -iconFile $iconFile `
    -requireAdmin `
    -UNICODEEncoding `
    -title 'Limpeza Avancada do Windows' `
    -description 'Manutencao e liberacao de espaco no disco' `
    -company 'Luiz Filipe Schaeffer' `
    -product 'Limpeza Avancada do Windows' `
    -copyright 'Luiz Filipe Schaeffer' `
    -version $appVersion

if (-not (Test-Path $outputExe)) {
    throw 'Falha ao gerar o executavel.'
}

Write-Host ''
Write-Host 'Executavel criado com sucesso:' -ForegroundColor Green
Write-Host "  $outputExe"
Write-Host "  Icone: $iconFile"
Write-Host ''
Write-Host 'Execute dist\LimpezaWindows.exe ou bin\limpeza.bat (UAC sera solicitado).' -ForegroundColor Yellow
