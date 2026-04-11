param(
  [string]$ClusterName = "enterprise-onprem-lab"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$k3dPath = Join-Path $repoRoot ".tools\\bin\\k3d.exe"

if (Test-Path $k3dPath) {
  & $k3dPath cluster delete $ClusterName 2>$null
}

Push-Location $repoRoot
try {
  & docker compose down --remove-orphans
}
finally {
  Pop-Location
}
