param(
  [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "artifacts\\evidence\\latest")
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$traefikIp = & kubectl get svc traefik -n kube-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
$ingressBaseUrl = "http://127.0.0.1:18080"

& kubectl get nodes -o wide | Out-File -Encoding utf8 (Join-Path $OutputDir "nodes.txt")
& kubectl get pods -A -o wide | Out-File -Encoding utf8 (Join-Path $OutputDir "pods.txt")
& kubectl get svc -A | Out-File -Encoding utf8 (Join-Path $OutputDir "services.txt")
& kubectl get ingress -A | Out-File -Encoding utf8 (Join-Path $OutputDir "ingress.txt")
& kubectl get gitrepositories -n flux-system | Out-File -Encoding utf8 (Join-Path $OutputDir "gitrepositories.txt")
& kubectl get kustomizations -n flux-system | Out-File -Encoding utf8 (Join-Path $OutputDir "kustomizations.txt")
& kubectl get helmreleases -A | Out-File -Encoding utf8 (Join-Path $OutputDir "helmreleases.txt")
& kubectl get externalsecrets -A | Out-File -Encoding utf8 (Join-Path $OutputDir "externalsecrets.txt")
& kubectl get clustersecretstores | Out-File -Encoding utf8 (Join-Path $OutputDir "clustersecretstores.txt")
& kubectl get pvc -A | Out-File -Encoding utf8 (Join-Path $OutputDir "persistent-volume-claims.txt")
& kubectl top pods -A | Out-File -Encoding utf8 (Join-Path $OutputDir "pod-metrics.txt")
"Traefik external IP: $traefikIp" | Out-File -Encoding utf8 (Join-Path $OutputDir "ingress-endpoint.txt")
"Ingress base URL: $ingressBaseUrl" | Out-File -Append -Encoding utf8 (Join-Path $OutputDir "ingress-endpoint.txt")

if ($traefikIp) {
  & curl.exe -s -H "Host: service-desk.platform.lab" "$ingressBaseUrl/api/health/" | Out-File -Encoding utf8 (Join-Path $OutputDir "service-desk-health.json")
  & curl.exe -s -H "Host: service-desk.platform.lab" "$ingressBaseUrl/api/metrics/" | Out-File -Encoding utf8 (Join-Path $OutputDir "service-desk-metrics.txt")
  & curl.exe -s -H "Host: webhook.platform.lab" "$ingressBaseUrl/health" | Out-File -Encoding utf8 (Join-Path $OutputDir "webhook-health.json")
  & curl.exe -s -H "Host: webhook.platform.lab" "$ingressBaseUrl/metrics" | Out-File -Encoding utf8 (Join-Path $OutputDir "webhook-metrics.txt")
  & curl.exe -s -H "Host: jaeger.platform.lab" "$ingressBaseUrl/api/services" | Out-File -Encoding utf8 (Join-Path $OutputDir "jaeger-services.json")
  & curl.exe -s -H "Host: prometheus.platform.lab" "$ingressBaseUrl/-/ready" | Out-File -Encoding utf8 (Join-Path $OutputDir "prometheus-ready.txt")
}
