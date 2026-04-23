param(
  [string]$VaultAddress = "http://127.0.0.1:18200",
  [string]$VaultToken = "root-token",
  [ValidateSet("dev", "demo", "stage")]
  [string]$Environment = "demo",
  [string]$ServiceDeskSecretKey = $env:SERVICE_DESK_DJANGO_SECRET_KEY,
  [string]$WebhookApiKey = $env:WEBHOOK_API_KEY,
  [string]$WebhookSecret = $env:WEBHOOK_SECRET,
  [switch]$NoPromoteToCurrent
)

$ErrorActionPreference = "Stop"
$headers = @{
  "X-Vault-Token" = $VaultToken
}

function Wait-VaultReady {
  param(
    [int]$TimeoutSeconds = 60
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      Invoke-RestMethod `
        -Method Get `
        -Uri "$VaultAddress/v1/sys/health" `
        -Headers $headers `
        -TimeoutSec 5 | Out-Null
      return
    }
    catch {
      Start-Sleep -Seconds 2
    }
  }

  throw "Vault did not become ready at $VaultAddress within $TimeoutSeconds seconds."
}

function Resolve-DemoSecret {
  param(
    [string]$Value,
    [string]$Fallback
  )

  if ($Value) {
    return $Value
  }

  return $Fallback
}

function Write-VaultKvSecret {
  param(
    [string]$Path,
    [hashtable]$Data
  )

  $body = @{
    data = $Data
  }

  Invoke-RestMethod `
    -Method Post `
    -Uri "$VaultAddress/v1/$Path" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body (($body | ConvertTo-Json -Depth 10)) | Out-Null
}

Wait-VaultReady

$serviceDeskData = @{
  DJANGO_SECRET_KEY = Resolve-DemoSecret `
    -Value $ServiceDeskSecretKey `
    -Fallback "enterprise-service-desk-secret-key"
}

$webhookData = @{
  API_KEY = Resolve-DemoSecret `
    -Value $WebhookApiKey `
    -Fallback "enterprise-demo-api-key"
  WEBHOOK_SECRET = Resolve-DemoSecret `
    -Value $WebhookSecret `
    -Fallback "enterprise-demo-webhook-secret"
}

$payloads = @(
  @{
    name = "service-desk"
    environmentPath = "secret/data/platform/$Environment/service-desk"
    currentPath = "secret/data/platform/service-desk"
    data = $serviceDeskData
  },
  @{
    name = "webhook"
    environmentPath = "secret/data/platform/$Environment/webhook"
    currentPath = "secret/data/platform/webhook"
    data = $webhookData
  }
)

foreach ($payload in $payloads) {
  Write-VaultKvSecret -Path $payload.environmentPath -Data $payload.data
  Write-Host "Seeded $($payload.name) secret material at $($payload.environmentPath)."

  if (-not $NoPromoteToCurrent) {
    Write-VaultKvSecret -Path $payload.currentPath -Data $payload.data
    Write-Host "Promoted $($payload.name) secret material to $($payload.currentPath)."
  }
}

Write-Host "Vault secret seeding completed for environment '$Environment'."
