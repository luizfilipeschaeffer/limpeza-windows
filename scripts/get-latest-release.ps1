# Baixa a ultima versao do executavel publicada em GitHub Releases.
param(
    [string]$Repo = 'luizfilipeschaeffer/limpeza-windows',
    [string]$AssetName = 'LimpezaWindows.exe',
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path $PSScriptRoot -Parent
$outPath    = Join-Path $projectDir 'dist\LimpezaWindows.exe'
$apiUrl     = "https://api.github.com/repos/$Repo/releases/latest"
$headers    = @{
    'User-Agent' = 'LimpezaWindows-Updater'
    'Accept'     = 'application/vnd.github+json'
}

function Write-Info([string]$Message, [ConsoleColor]$Color = 'Gray') {
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

Write-Info 'Consultando ultima release no GitHub...' Cyan

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
}
catch {
    throw "Nao foi possivel consultar releases em https://github.com/$Repo/releases : $($_.Exception.Message)"
}

$tag     = $release.tag_name
$version = $tag -replace '^v', ''
$asset   = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1

if (-not $asset) {
    $names = ($release.assets | ForEach-Object { $_.name }) -join ', '
    throw "Asset '$AssetName' nao encontrado na release $tag. Disponiveis: $names"
}

Write-Info "  Ultima versao : $tag ($version)" Green
Write-Info "  Publicada em  : $($release.published_at)" DarkGray
Write-Info "  Pagina        : $($release.html_url)" DarkCyan

if ((Test-Path $outPath) -and -not $Force) {
    $localVersion = (Get-Item $outPath).VersionInfo.ProductVersion
    if ($localVersion -eq $version) {
        Write-Info ''
        Write-Info "Ja esta atualizado ($AssetName v$localVersion)." Green
        return [PSCustomObject]@{
            Updated  = $false
            Version  = $version
            Path     = $outPath
            Release  = $release.html_url
        }
    }
}

New-Item -ItemType Directory -Path (Split-Path $outPath -Parent) -Force | Out-Null

Write-Info ''
Write-Info "Baixando $AssetName..." Cyan
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $outPath -UseBasicParsing

Write-Info ''
Write-Info 'Download concluido:' Green
Write-Info "  $outPath"
Write-Info "  Versao: $((Get-Item $outPath).VersionInfo.ProductVersion)"

[PSCustomObject]@{
    Updated = $true
    Version = $version
    Path    = $outPath
    Release = $release.html_url
}
