Add-Type -AssemblyName System.Drawing

function New-MultiResolutionIcon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIconPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputIconPath,

        [int[]]$Sizes = @(16, 24, 32, 48, 64, 96, 128, 256)
    )

    if (-not (Test-Path $SourceIconPath)) {
        throw "Arquivo de origem nao encontrado: $SourceIconPath"
    }

    $sourceIcon = New-Object System.Drawing.Icon $SourceIconPath
    $sourceBitmap = $sourceIcon.ToBitmap()
    $sourceIcon.Dispose()

    $pngEntries = New-Object System.Collections.Generic.List[object]
    $sortedSizes = $Sizes | Sort-Object -Unique

    foreach ($size in $sortedSizes) {
        $bitmap = New-Object System.Drawing.Bitmap $size, $size
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawImage($sourceBitmap, 0, 0, $size, $size)
        $graphics.Dispose()

        $stream = New-Object IO.MemoryStream
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngEntries.Add([PSCustomObject]@{
            Size = $size
            Data = $stream.ToArray()
        })
        $stream.Dispose()
        $bitmap.Dispose()
    }

    $sourceBitmap.Dispose()

    $headerSize = 6 + ($pngEntries.Count * 16)
    $offset = $headerSize
    $entries = New-Object System.Collections.Generic.List[byte]

    foreach ($entry in $pngEntries) {
        $entries.Add([byte]($(if ($entry.Size -ge 256) { 0 } else { $entry.Size })))
        $entries.Add([byte]($(if ($entry.Size -ge 256) { 0 } else { $entry.Size })))
        $entries.Add(0)
        $entries.Add(0)
        $entries.AddRange([BitConverter]::GetBytes([uint16]1))
        $entries.AddRange([BitConverter]::GetBytes([uint16]32))
        $entries.AddRange([BitConverter]::GetBytes([uint32]$entry.Data.Length))
        $entries.AddRange([BitConverter]::GetBytes([uint32]$offset))
        $offset += $entry.Data.Length
    }

    $fileStream = [IO.File]::Open($OutputIconPath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
    $writer = New-Object IO.BinaryWriter($fileStream)

    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$pngEntries.Count)
    $writer.Write($entries.ToArray())

    foreach ($entry in $pngEntries) {
        $writer.Write($entry.Data)
    }

    $writer.Close()
    $fileStream.Close()
}

function Get-IconEntries {
    param([string]$IconPath)

    $stream = [IO.File]::OpenRead($IconPath)
    $reader = New-Object IO.BinaryReader($stream)
    $null = $reader.ReadUInt16()
    $null = $reader.ReadUInt16()
    $count = $reader.ReadUInt16()
    $entries = @()

    for ($i = 0; $i -lt $count; $i++) {
        $width = $reader.ReadByte()
        $height = $reader.ReadByte()
        $null = $reader.ReadByte()
        $null = $reader.ReadByte()
        $null = $reader.ReadUInt16()
        $bpp = $reader.ReadUInt16()
        $size = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        if ($width -eq 0) { $width = 256 }
        if ($height -eq 0) { $height = 256 }
        $entries += "${width}x${height} (${bpp} bpp)"
    }

    $reader.Close()
    $stream.Close()
    return $entries
}

$projectDir = Split-Path $PSScriptRoot -Parent
$assetsDir  = Join-Path $projectDir 'assets'
$sourceIcon = Join-Path $assetsDir 'limpeza-icon.ico'
$outputIcon = Join-Path $assetsDir 'limpeza-icon.ico'
$backupIcon = Join-Path $assetsDir 'limpeza-icon.source.ico'

if (-not (Test-Path $sourceIcon)) {
    throw "Icone nao encontrado: $sourceIcon"
}

if (-not (Test-Path $backupIcon)) {
    Copy-Item -Path $sourceIcon -Destination $backupIcon -Force
    Write-Host "Backup do icone original salvo em assets\limpeza-icon.source.ico"
}

$tempIcon = Join-Path $assetsDir 'limpeza-icon.tmp.ico'
New-MultiResolutionIcon -SourceIconPath $backupIcon -OutputIconPath $tempIcon
Move-Item -Path $tempIcon -Destination $outputIcon -Force

Write-Host 'Icone multi-resolucao gerado:' -ForegroundColor Green
Get-IconEntries -IconPath $outputIcon | ForEach-Object { Write-Host "  $_" }
