Add-Type -AssemblyName System.Drawing

$projectDir = Split-Path $PSScriptRoot -Parent
$path = Join-Path $projectDir 'assets\limpeza-icon.ico'

if (-not (Test-Path $path)) {
    throw "Icone nao encontrado: $path"
}

$fs = [IO.File]::OpenRead($path)
$br = New-Object IO.BinaryReader($fs)
$null = $br.ReadUInt16()
$null = $br.ReadUInt16()
$count = $br.ReadUInt16()

Write-Host "Entradas no ICO: $count"
for ($i = 0; $i -lt $count; $i++) {
    $w = $br.ReadByte()
    $h = $br.ReadByte()
    $null = $br.ReadByte()
    $null = $br.ReadByte()
    $null = $br.ReadUInt16()
    $bpp = $br.ReadUInt16()
    $size = $br.ReadUInt32()
    $null = $br.ReadUInt32()
    if ($w -eq 0) { $w = 256 }
    if ($h -eq 0) { $h = 256 }
    Write-Host "  ${w}x${h} | ${bpp} bpp | $size bytes"
}
$fs.Close()

$icon = New-Object System.Drawing.Icon $path
Write-Host "Icone padrao carregado: $($icon.Width)x$($icon.Height)"
