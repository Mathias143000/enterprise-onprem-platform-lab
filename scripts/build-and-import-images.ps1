param(
  [string]$ClusterName = "enterprise-onprem-lab"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$portfolioRoot = Split-Path $repoRoot -Parent

$serviceDeskImage = "k8s-lab/service-desk-api:2.0.0"
$webhookImage = "k8s-lab/webhook-ingestion-service:2.0.0"

& docker build -t $serviceDeskImage (Join-Path $portfolioRoot "service-desk-api")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& docker build -t $webhookImage (Join-Path $portfolioRoot "webhook-ingestion-service")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$k3dPath = Join-Path $repoRoot ".tools\\bin\\k3d.exe"
& $k3dPath image import $serviceDeskImage -c $ClusterName
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $k3dPath image import $webhookImage -c $ClusterName
exit $LASTEXITCODE

