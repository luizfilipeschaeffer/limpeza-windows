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
        -LogPath (Join-Path $tempRoot 'update.log')

    Assert-True (Test-Path -LiteralPath $helperPath) 'Helper de atualizacao gerado'
    $helperText = Get-Content -LiteralPath $helperPath -Raw
    Assert-True ($helperText -match 'Install-LimpezaUpdatedExecutable') 'Helper invoca Install-LimpezaUpdatedExecutable'
    Assert-True ($helperText -match 'ProgramData\\LimpezaWindows\\LimpezaUpdate\.ps1') 'Helper carrega modulo em ProgramData'

    $syncSource = Join-Path $tempRoot 'LimpezaUpdate.ps1'
    Copy-Item -LiteralPath $modulePath -Destination $syncSource -Force
    Assert-True (Sync-LimpezaUpdateModule -SourceModulePath $syncSource) 'Sync copia modulo para ProgramData'

    $programDataModule = Join-Path (Join-Path $env:ProgramData 'LimpezaWindows') 'LimpezaUpdate.ps1'
    Assert-True (Test-Path -LiteralPath $programDataModule) 'Modulo presente em ProgramData apos Sync'
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
