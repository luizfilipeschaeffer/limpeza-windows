$ErrorActionPreference = 'Stop'
$testScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests\Test-LimpezaUpdate.ps1'
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $testScript
exit $LASTEXITCODE
