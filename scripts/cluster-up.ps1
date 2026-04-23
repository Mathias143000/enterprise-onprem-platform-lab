param(
  [string]$ClusterName = "enterprise-onprem-lab",
  [switch]$ForceRecreate
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$toolsDir = Join-Path $repoRoot ".tools\\bin"
$k3dPath = Join-Path $toolsDir "k3d.exe"
$helmPath = Join-Path $toolsDir "helm.exe"

function Wait-GitRepo {
  param([string]$Url)

  $uri = [System.Uri]$Url
  $probeUrl = "{0}://{1}:{2}{3}/info/refs?service=git-upload-pack" -f $uri.Scheme, $uri.Host, $uri.Port, $uri.AbsolutePath.TrimEnd("/")

  for ($attempt = 1; $attempt -le 45; $attempt++) {
    try {
      $statusCode = & curl.exe -s -o NUL -w "%{http_code}" $probeUrl
      if ($statusCode -eq "200") {
        break
      }
    }
    catch {
    }
    Start-Sleep -Seconds 2
  }

  for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
      & git ls-remote $Url | Out-Null
      if ($LASTEXITCODE -eq 0) {
        return
      }
    }
    catch {
    }
    Start-Sleep -Seconds 2
  }
  throw "Git repository did not become reachable at $Url (probe: $probeUrl)"
}

function Wait-ServiceExternalIP {
  param(
    [string]$Namespace,
    [string]$Name,
    [int]$TimeoutSeconds = 300
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $ip = & kubectl get svc $Name -n $Namespace -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>$null
    if ($ip) {
      return $ip
    }
    Start-Sleep -Seconds 5
  }

  throw "Timed out waiting for external IP on service/$Name in namespace $Namespace"
}

function New-MetalLbPool {
  param([string]$ClusterName)

  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
  $networkJson = & docker network inspect "k3d-$ClusterName" | ConvertFrom-Json
  $gateway = $networkJson[0].IPAM.Config[0].Gateway
  if (-not $gateway) {
    throw "Failed to determine Docker network gateway for k3d-$ClusterName"
  }

  $octets = $gateway.Split(".")
  if ($octets.Length -lt 4) {
    throw "Unexpected gateway format: $gateway"
  }

  $rangeStart = "$($octets[0]).$($octets[1]).$($octets[2]).240"
  $rangeEnd = "$($octets[0]).$($octets[1]).$($octets[2]).250"
  $poolFile = Join-Path $repoRoot "cluster\\addons\\metallb-address-pool.generated.yaml"
  @"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: enterprise-pool
  namespace: metallb-system
spec:
  addresses:
    - $rangeStart-$rangeEnd
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: enterprise-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - enterprise-pool
"@ | Set-Content -Path $poolFile -NoNewline

  return $poolFile
}

& (Join-Path $PSScriptRoot "ensure-tools.ps1")

Push-Location $repoRoot
try {
  & docker compose up -d --build
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  Pop-Location
}

& (Join-Path $PSScriptRoot "bootstrap-gitops-repo.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Wait-GitRepo -Url "http://127.0.0.1:18018/git/platform.git"

$clusterList = & $k3dPath cluster list 2>$null
$clusterExists = $clusterList | Select-String -Pattern "^$ClusterName\s" | Select-Object -First 1
if ($clusterExists -and $clusterExists.Line -match "\s0/\d+") {
  Write-Host "Existing k3d cluster '$ClusterName' is not fully running; recreating it."
  & $k3dPath cluster delete $ClusterName
  $clusterExists = $null
}

if ($clusterExists -and $ForceRecreate) {
  & $k3dPath cluster delete $ClusterName
  $clusterExists = $null
}

if (-not $clusterExists) {
  & $k3dPath cluster create $ClusterName `
    --servers 1 `
    --agents 2 `
    --wait `
    -p "18080:30080@loadbalancer" `
    -p "18443:30443@loadbalancer" `
    --k3s-arg "--disable=servicelb@server:0"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $k3dPath kubeconfig merge $ClusterName --kubeconfig-switch-context
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apiPort = $null
try {
  $apiPortOutput = & docker port "k3d-$ClusterName-serverlb" 6443/tcp 2>$null
  if ($LASTEXITCODE -eq 0) {
    $apiPort = $apiPortOutput | Select-Object -First 1
  }
}
catch {
  $apiPort = $null
}

if ($apiPort) {
  $normalizedApiPort = ($apiPort -replace '0\.0\.0\.0:', '') -replace '\[::\]:', ''
  & kubectl config set-cluster "k3d-$ClusterName" --server="https://127.0.0.1:$normalizedApiPort" | Out-Null
}

& kubectl wait --for=condition=Ready nodes --all --timeout=240s
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& kubectl apply -f (Join-Path $repoRoot "cluster\\addons\\traefik-helmchartconfig.yaml")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace metallb-system -Kind deployment -Name controller -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace metallb-system -Kind daemonset -Name speaker -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$poolFile = New-MetalLbPool -ClusterName $ClusterName
& kubectl apply -f $poolFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
& kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.4.0/install.yaml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace flux-system -Kind deployment -Name source-controller -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace flux-system -Kind deployment -Name kustomize-controller -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace flux-system -Kind deployment -Name helm-controller -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $helmPath repo add external-secrets https://charts.external-secrets.io | Out-Null
& $helmPath repo update | Out-Null
& $helmPath upgrade --install external-secrets external-secrets/external-secrets `
  --namespace external-secrets `
  --create-namespace `
  --set installCRDs=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace external-secrets -Kind deployment -Name external-secrets -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "seed-vault.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "build-and-import-images.ps1") -ClusterName $ClusterName
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& kubectl apply --validate=false -f (Join-Path $repoRoot "flux\\clusters\\demo\\gitrepository.yaml")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& kubectl apply --validate=false -f (Join-Path $repoRoot "flux\\clusters\\demo\\kustomization.yaml")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace flux-system -Kind gitrepository -Name platform-repo -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace flux-system -Kind kustomization -Name enterprise-platform -TimeoutSeconds 1800
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace service-desk -Kind externalsecret -Name service-desk-secrets -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace webhook -Kind externalsecret -Name webhook-ingestion-secrets -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace observability -Kind helmrelease -Name prometheus -TimeoutSeconds 900
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace observability -Kind helmrelease -Name loki-stack -TimeoutSeconds 900
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace observability -Kind helmrelease -Name grafana -TimeoutSeconds 900
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace observability -Kind deployment -Name jaeger -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace platform -Kind deployment -Name minio -TimeoutSeconds 600
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace service-desk -Kind helmrelease -Name service-desk-api -TimeoutSeconds 900
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "wait-k8s.ps1") -Namespace webhook -Kind helmrelease -Name webhook-ingestion-service -TimeoutSeconds 900
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$traefikIp = Wait-ServiceExternalIP -Namespace kube-system -Name traefik -TimeoutSeconds 300
Write-Host "Traefik external IP: $traefikIp"
Write-Host "Flux synced and workloads are ready."
