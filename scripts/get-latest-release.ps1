# Baixa a ultima versao do executavel publicada em GitHub Releases (por edicao/asset).
param(
    [ValidateSet('Standard', 'CleanCode')]
    [string]$Edition = 'Standard',
    [string]$Repo = 'luizfilipeschaeffer/limpeza-windows',
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path $PSScriptRoot -Parent
$assetName  = if ($Edition -eq 'CleanCode') { 'LimpezaWindows-CleanCode.exe' } else { 'LimpezaWindows.exe' }
$outPath    = Join-Path $projectDir "dist\$assetName"
$apiUrl     = "https://api.github.com/repos/$Repo/releases?per_page=30"
$headers    = @{
    'User-Agent' = if ($Edition -eq 'CleanCode') { 'LimpezaWindows-CleanCode-Updater' } else { 'LimpezaWindows-Updater' }
    'Accept'     = 'application/vnd.github+json'
}

function Write-Info([string]$Message, [ConsoleColor]$Color = 'Gray') {
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

Write-Info "Consultando releases ($Edition / $assetName)..." Cyan

try {
    $releases = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
}
catch {
    throw "Nao foi possivel consultar releases em https://github.com/$Repo/releases : $($_.Exception.Message)"
}

$release = $null
$asset   = $null
foreach ($candidate in $releases) {
    if ($candidate.draft) { continue }
    $match = $candidate.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if ($match) {
        $release = $candidate
        $asset   = $match
        break
    }
}

if (-not $release -or -not $asset) {
    throw "Nenhuma release publicada contem o asset '$assetName'."
}

$tag     = $release.tag_name
$version = $tag -replace '^v', ''

Write-Info "  Ultima versao : $tag ($version)" Green
Write-Info "  Publicada em  : $($release.published_at)" DarkGray
Write-Info "  Pagina        : $($release.html_url)" DarkCyan

if ((Test-Path $outPath) -and -not $Force) {
    $localVersion = (Get-Item $outPath).VersionInfo.ProductVersion
    if ($localVersion -eq $version) {
        Write-Info ''
        Write-Info "Ja esta atualizado ($assetName v$localVersion)." Green
        return [PSCustomObject]@{
            Updated = $false
            Version = $version
            Path    = $outPath
            Release = $release.html_url
        }
    }
}

New-Item -ItemType Directory -Path (Split-Path $outPath -Parent) -Force | Out-Null

Write-Info ''
Write-Info "Baixando $assetName..." Cyan
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
