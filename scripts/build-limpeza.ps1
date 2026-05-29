param(
    [ValidateSet('Standard', 'CleanCode')]
    [string]$Edition = 'Standard'
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path $PSScriptRoot -Parent
$versionFile = if ($Edition -eq 'CleanCode') {
    Join-Path $projectDir 'config\VERSION.clean-code'
} else {
    Join-Path $projectDir 'config\VERSION'
}

if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "Arquivo de versao nao encontrado: $versionFile"
}

$versionLabel = (Get-Content -LiteralPath $versionFile -Raw).Trim()
$appVersion = if ($versionLabel -notmatch '\.\d+$') { "$versionLabel.0" } else { $versionLabel }

$buildDir  = Join-Path $projectDir 'tools\ps2exe-build'
$sourcePs1 = Join-Path $projectDir 'src\limpeza.ps1'
$updatePs1 = Join-Path $projectDir 'src\LimpezaUpdate.ps1'
$bundlePs1 = Join-Path $buildDir 'limpeza.bundle.ps1'
$iconFile  = Join-Path $projectDir 'assets\limpeza-icon.ico'

$editionProfile = switch ($Edition) {
    'CleanCode' {
        [PSCustomObject]@{
            OutputExe    = Join-Path $projectDir 'dist\LimpezaWindows-CleanCode.exe'
            ProductTitle = 'Limpeza Avancada do Windows (Clean Code)'
            Description  = 'Manutencao e liberacao de espaco no disco (Clean Code)'
        }
    }
    default {
        [PSCustomObject]@{
            OutputExe    = Join-Path $projectDir 'dist\LimpezaWindows.exe'
            ProductTitle = 'Limpeza Avancada do Windows'
            Description  = 'Manutencao e liberacao de espaco no disco'
        }
    }
}

$outputExe  = $editionProfile.OutputExe
$compiler   = Join-Path $buildDir 'ps2exe.ps1'
$wrapperPs1 = Join-Path $buildDir 'compile-limpeza.ps1'
$compilerUrl = 'https://raw.githubusercontent.com/MScholtes/PS2EXE/master/Module/ps2exe.ps1'
$windowsPs  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

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

Write-Host "Gerando bundle ($Edition)..." -ForegroundColor Cyan
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
$mainContent = [regex]::Replace($mainContent, "\`$script:ProductEdition = '[^']+'", "`$script:ProductEdition = '$Edition'")
$mainContent = [regex]::Replace($mainContent, "\`$AppVersion = '[^']+'", "`$AppVersion = '$versionLabel'")
Set-Content -LiteralPath $bundlePs1 -Value ($moduleContent + "`r`n`r`n" + $mainContent) -Encoding UTF8

$distDir = Split-Path $outputExe -Parent
Copy-Item -LiteralPath $updatePs1 -Destination (Join-Path $distDir 'LimpezaUpdate.ps1') -Force

Write-Host "Compilando $(Split-Path -Leaf $outputExe) com icone personalizado..." -ForegroundColor Cyan
Write-Host "  Edicao     : $Edition" -ForegroundColor DarkGray
Write-Host "  Versao     : $versionLabel" -ForegroundColor DarkGray
Write-Host "  Host atual : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host '  Compilador : Windows PowerShell 5.1 + ps2exe' -ForegroundColor DarkGray

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
. '$($compiler.Replace("'", "''"))'
Invoke-ps2exe -inputFile '$($bundlePs1.Replace("'", "''"))' -outputFile '$($outputExe.Replace("'", "''"))' -iconFile '$($iconFile.Replace("'", "''"))' -requireAdmin -UNICODEEncoding -title '$($editionProfile.ProductTitle.Replace("'", "''"))' -description '$($editionProfile.Description.Replace("'", "''"))' -company 'Luiz Filipe Schaeffer' -product '$($editionProfile.ProductTitle.Replace("'", "''"))' -copyright 'Luiz Filipe Schaeffer' -version '$appVersion'
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
Write-Host "  Edicao: $Edition"
Write-Host "  Icone: $iconFile"
Write-Host "  Versao: $((Get-Item -LiteralPath $outputExe).VersionInfo.ProductVersion)"
Write-Host "  Modulo: $(Join-Path $distDir 'LimpezaUpdate.ps1')"
Write-Host ''
if ($Edition -eq 'CleanCode') {
    Write-Host 'Execute dist\LimpezaWindows-CleanCode.exe ou bin\limpeza-clean-code.bat (UAC sera solicitado).' -ForegroundColor Yellow
}
else {
    Write-Host 'Execute dist\LimpezaWindows.exe ou bin\limpeza.bat (UAC sera solicitado).' -ForegroundColor Yellow
}
