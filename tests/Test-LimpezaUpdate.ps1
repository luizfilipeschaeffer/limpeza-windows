# Testes do modulo LimpezaUpdate (sem rede, sem admin).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-LimpezaUpdate.ps1

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $projectDir 'src\LimpezaUpdate.ps1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Modulo nao encontrado: $modulePath"
}

. $modulePath

$failed  = 0
$passed  = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if ($Condition) {
        $script:passed++
        Write-Host "  OK  $Name" -ForegroundColor Green
    }
    else {
        $script:failed++
        Write-Host "  FALHA  $Name" -ForegroundColor Red
    }
}

function Assert-Equals {
    param(
        $Expected,
        $Actual,
        [string]$Name
    )
    Assert-True ($Expected -eq $Actual) "$Name (esperado='$Expected', atual='$Actual')"
}

Write-Host ''
Write-Host 'Test-LimpezaUpdate.ps1' -ForegroundColor Cyan
Write-Host '======================' -ForegroundColor Cyan
Write-Host ''

Assert-True (Test-LimpezaUpdateAvailable -CurrentVersion '2.1.0' -ReleaseVersion '2.2.0') 'Update disponivel quando release maior'
Assert-True (-not (Test-LimpezaUpdateAvailable -CurrentVersion '2.2.0' -ReleaseVersion '2.2.0')) 'Sem update na mesma versao'
Assert-True (-not (Test-LimpezaUpdateAvailable -CurrentVersion '2.3.0' -ReleaseVersion '2.2.0')) 'Sem update quando local e mais novo'

$standardProfile = Get-LimpezaEditionProfile -Edition Standard
$cleanProfile    = Get-LimpezaEditionProfile -Edition CleanCode
Assert-Equals 'LimpezaWindows.exe' $standardProfile.UpdateAssetName 'Standard usa asset LimpezaWindows.exe'
Assert-Equals 'LimpezaWindows-CleanCode.exe' $cleanProfile.UpdateAssetName 'CleanCode usa asset LimpezaWindows-CleanCode.exe'
Assert-True ($standardProfile.UpdateAssetName -ne $cleanProfile.UpdateAssetName) 'Assets de atualizacao sao distintos por edicao'

$script:LimpezaProductEdition = 'CleanCode'
Assert-True ((Get-LimpezaProgramDataRoot) -like '*LimpezaWindows-CleanCode') 'ProgramData separado para CleanCode'
$script:LimpezaProductEdition = 'Standard'
Assert-True ((Get-LimpezaProgramDataRoot) -like '*LimpezaWindows') 'ProgramData padrao para Standard'
Remove-Variable -Name LimpezaProductEdition -Scope Script -ErrorAction SilentlyContinue

$tempRoot = Join-Path $env:TEMP ("LimpezaUpdateTest-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $v1 = Join-Path $tempRoot 'app-v1.exe'
    $v2 = Join-Path $tempRoot 'app-v2.exe'
    $target = Join-Path $tempRoot 'LimpezaWindows.exe'

    Set-Content -LiteralPath $v1 -Value 'version-1' -Encoding ASCII
    Set-Content -LiteralPath $v2 -Value 'version-2-longer' -Encoding ASCII
    Copy-Item -LiteralPath $v1 -Destination $target -Force

    Assert-True (Test-LimpezaFileUnlocked -Path $target) 'Arquivo de teste desbloqueado'

    $installResult = Install-LimpezaUpdatedExecutable `
        -StagingPath $v2 `
        -TargetPath $target `
        -ExpectedVersion '0.0.0' `
        -TimeoutSeconds 5

    Assert-True $installResult.Success 'Install-LimpezaUpdatedExecutable substitui o alvo'
    Assert-Equals 'version-2-longer' (Get-Content -LiteralPath $target -Raw).Trim() 'Conteudo do executavel atualizado'

    Set-Content -LiteralPath $v2 -Value 'version-2-longer' -Encoding ASCII -Force

    $locked = Join-Path $tempRoot 'locked.bin'
    Copy-Item -LiteralPath $v2 -Destination $locked -Force
    $stream = [System.IO.File]::Open(
        $locked,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $failResult = Install-LimpezaUpdatedExecutable `
            -StagingPath $v1 `
            -TargetPath $locked `
            -ExpectedVersion '0.0.0' `
            -TimeoutSeconds 2
        Assert-True (-not $failResult.Success) 'Install falha com arquivo bloqueado'
    }
    finally {
        $stream.Close()
        $stream.Dispose()
    }

    $helperPath = New-LimpezaUpdaterHelperScript `
        -StagingPath $v2 `
        -TargetPath $target `
        -ExpectedVersion '0.0.0' `
        -ParentProcessId $PID `
        -LogPath (Join-Path $tempRoot 'update.log') `
        -ModuleSourcePath $modulePath

    Assert-True (Test-Path -LiteralPath $helperPath) 'Helper de atualizacao gerado'
    $helperText = Get-Content -LiteralPath $helperPath -Raw
    Assert-True ($helperText -match 'Install-LimpezaUpdatedExecutable') 'Helper invoca Install-LimpezaUpdatedExecutable'
    Assert-True ($helperText -match [regex]::Escape($modulePath)) 'Helper carrega modulo por caminho absoluto valido'

    $fakeExeAsPs1 = Join-Path $tempRoot 'fake-module.ps1'
    Copy-Item -LiteralPath $v1 -Destination $fakeExeAsPs1 -Force
    Assert-True (-not (Test-LimpezaUpdateModuleFile -Path $fakeExeAsPs1)) 'Rejeita executavel disfarçado de .ps1'

    $syncSource = Join-Path $tempRoot 'LimpezaUpdate.ps1'
    Copy-Item -LiteralPath $modulePath -Destination $syncSource -Force
    $script:LimpezaProductEdition = 'Standard'
    $syncOk = Sync-LimpezaUpdateModule -SourceModulePath $syncSource
    if ($syncOk) {
        $programDataModule = Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'
        Assert-True (Test-Path -LiteralPath $programDataModule) 'Modulo presente em ProgramData apos Sync'
    }
    else {
        Write-Host '  AVISO  Sync para ProgramData ignorado (sem permissao de escrita)' -ForegroundColor DarkYellow
    }

    $artifacts = Get-LimpezaLegacyArtifactPaths -AssetName 'LimpezaWindows.exe'
    Assert-True ($artifacts.Count -ge 2) 'Lista de artefatos legados definida'
    Assert-True ($artifacts -contains (Join-Path $env:SystemRoot 'LimpezaWindows.exe')) 'Artefatos legados incluem executavel do SystemRoot'

    $exePath = Join-Path $tempRoot 'my-app.exe'
    Set-Content -LiteralPath $exePath -Value 'portable' -Encoding ASCII
    $resolved = Resolve-LimpezaUpdateTargetExe -CommandPath $exePath -DistFallbackPath (Join-Path $tempRoot 'missing.exe')
    Assert-Equals $exePath $resolved 'Resolve-LimpezaUpdateTargetExe prioriza exe em execucao'

    $distFallback = Join-Path $tempRoot 'dist-fallback.exe'
    Set-Content -LiteralPath $distFallback -Value 'fallback' -Encoding ASCII
    $resolvedScript = Resolve-LimpezaUpdateTargetExe -CommandPath (Join-Path $tempRoot 'limpeza.ps1') -DistFallbackPath $distFallback
    Assert-Equals $distFallback $resolvedScript 'Resolve-LimpezaUpdateTargetExe usa dist quando script'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("Resultado: $passed aprovado(s), $failed falha(s).") -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
Write-Host ''

if ($failed -gt 0) {
    exit 1
}

exit 0
