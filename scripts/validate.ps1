$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

& (Join-Path $PSScriptRoot "ensure-tools.ps1")

$helmPath = Join-Path $repoRoot ".tools\\bin\\helm.exe"
& $helmPath lint (Join-Path $repoRoot "helm\\apps\\service-desk-api")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $helmPath lint (Join-Path $repoRoot "helm\\apps\\webhook-ingestion-service")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $repoRoot
try {
  & docker compose config
}
finally {
  Pop-Location
}

exit $LASTEXITCODE

