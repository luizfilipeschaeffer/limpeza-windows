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

$buildDir    = Join-Path $projectDir 'tools\ps2exe-build'
$sourcePs1   = Join-Path $projectDir 'src\limpeza.ps1'
$updatePs1   = Join-Path $projectDir 'src\LimpezaUpdate.ps1'
$bundlePs1   = Join-Path $buildDir 'limpeza.bundle.ps1'
$iconFile    = Join-Path $projectDir 'assets\limpeza-icon.ico'
$outputExe   = Join-Path $projectDir 'dist\LimpezaWindows.exe'
$compiler    = Join-Path $buildDir 'ps2exe.ps1'
$wrapperPs1  = Join-Path $buildDir 'compile-limpeza.ps1'
$compilerUrl = 'https://raw.githubusercontent.com/MScholtes/PS2EXE/master/Module/ps2exe.ps1'
$windowsPs   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path $sourcePs1)) {
    throw "Arquivo nao encontrado: $sourcePs1"
}

if (-not (Test-Path $updatePs1)) {
    throw "Modulo de atualizacao nao encontrado: $updatePs1"
}

$updateTests = Join-Path $PSScriptRoot 'run-update-tests.ps1'
if (Test-Path $updateTests) {
    Write-Host 'Rodando testes de atualizacao...' -ForegroundColor Cyan
    & $updateTests
    if ($LASTEXITCODE -ne 0) {
        throw 'Testes de atualizacao falharam. Build interrompido.'
    }
    Write-Host ''
}

if (-not (Test-Path $iconFile)) {
    throw "Icone nao encontrado: $iconFile"
}

if (-not (Test-Path $windowsPs)) {
    throw "Windows PowerShell 5.1 nao encontrado: $windowsPs"
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

if (Test-Path -LiteralPath $outputExe) {
    Remove-Item -LiteralPath $outputExe -Force
}

Write-Host 'Gerando bundle (LimpezaUpdate + limpeza)...' -ForegroundColor Cyan
$moduleContent = Get-Content -LiteralPath $updatePs1 -Raw
$mainContent   = Get-Content -LiteralPath $sourcePs1 -Raw
$mainContent   = [regex]::Replace(
    $mainContent,
    '(?s)#region LimpezaUpdateLoader.*?#endregion\r?\n',
    @"
# Modulo LimpezaUpdate embarcado no build
Sync-LimpezaUpdateModule -SourceModulePath `$script:LimpezaUpdateSelfPath | Out-Null

"@
)
Set-Content -LiteralPath $bundlePs1 -Value ($moduleContent + "`r`n`r`n" + $mainContent) -Encoding UTF8

$distDir = Split-Path $outputExe -Parent
Copy-Item -LiteralPath $updatePs1 -Destination (Join-Path $distDir 'LimpezaUpdate.ps1') -Force

Write-Host 'Compilando LimpezaWindows.exe com icone personalizado...' -ForegroundColor Cyan
Write-Host "  Host atual : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host '  Compilador : Windows PowerShell 5.1 + ps2exe' -ForegroundColor DarkGray

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
. '$($compiler.Replace("'", "''"))'
Invoke-ps2exe -inputFile '$($bundlePs1.Replace("'", "''"))' -outputFile '$($outputExe.Replace("'", "''"))' -iconFile '$($iconFile.Replace("'", "''"))' -requireAdmin -UNICODEEncoding -title 'Limpeza Avancada do Windows' -description 'Manutencao e liberacao de espaco no disco' -company 'Luiz Filipe Schaeffer' -product 'Limpeza Avancada do Windows' -copyright 'Luiz Filipe Schaeffer' -version '$appVersion'
"@
Set-Content -Path $wrapperPs1 -Value $wrapperContent -Encoding UTF8

& $windowsPs -NoProfile -ExecutionPolicy Bypass -File $wrapperPs1
if ($LASTEXITCODE -ne 0) {
    throw "Compilacao ps2exe falhou com codigo de saida $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $outputExe)) {
    throw 'Falha ao gerar o executavel.'
}

Write-Host ''
Write-Host 'Executavel criado com sucesso:' -ForegroundColor Green
Write-Host "  $outputExe"
Write-Host "  Icone: $iconFile"
Write-Host "  Versao: $((Get-Item -LiteralPath $outputExe).VersionInfo.ProductVersion)"
Write-Host "  Modulo: $(Join-Path $distDir 'LimpezaUpdate.ps1')"
Write-Host ''
Write-Host 'Execute dist\LimpezaWindows.exe ou bin\limpeza.bat (UAC sera solicitado).' -ForegroundColor Yellow
Write-Host 'Copie LimpezaUpdate.ps1 junto ao .exe se instalar manualmente fora de C:\Windows.' -ForegroundColor DarkGray
