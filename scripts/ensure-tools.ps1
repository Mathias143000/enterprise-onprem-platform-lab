param(
  [string]$ToolsDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) ".tools\\bin")
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

function Download-File {
  param(
    [string]$Url,
    [string]$Destination
  )
  Write-Host "Downloading $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Destination
}

$k3dPath = Join-Path $ToolsDir "k3d.exe"
if (-not (Test-Path $k3dPath)) {
  $k3dRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/k3d-io/k3d/releases/latest"
  $k3dAsset = $k3dRelease.assets | Where-Object { $_.name -match "windows-amd64\.exe$" } | Select-Object -First 1
  if (-not $k3dAsset) {
    throw "Failed to locate the Windows k3d asset."
  }
  Download-File -Url $k3dAsset.browser_download_url -Destination $k3dPath
}

$helmPath = Join-Path $ToolsDir "helm.exe"
if (-not (Test-Path $helmPath)) {
  $helmRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/helm/helm/releases/latest"
  $helmTag = $helmRelease.tag_name
  $helmZip = Join-Path $env:TEMP "helm-windows-amd64.zip"
  $helmExtractDir = Join-Path $env:TEMP "helm-windows-amd64"
  Download-File -Url "https://get.helm.sh/helm-$helmTag-windows-amd64.zip" -Destination $helmZip
  if (Test-Path $helmExtractDir) {
    Remove-Item -Recurse -Force $helmExtractDir
  }
  Expand-Archive -Path $helmZip -DestinationPath $helmExtractDir
  Copy-Item (Join-Path $helmExtractDir "windows-amd64\\helm.exe") $helmPath -Force
}

Write-Host "k3d: $k3dPath"
Write-Host "helm: $helmPath"

