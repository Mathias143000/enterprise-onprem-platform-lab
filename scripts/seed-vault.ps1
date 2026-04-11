param(
  [string]$VaultAddress = "http://127.0.0.1:18200",
  [string]$VaultToken = "root-token"
)

$ErrorActionPreference = "Stop"
$headers = @{
  "X-Vault-Token" = $VaultToken
}

$payloads = @(
  @{
    path = "secret/data/platform/service-desk"
    body = @{
      data = @{
        DJANGO_SECRET_KEY = "enterprise-service-desk-secret-key"
      }
    }
  },
  @{
    path = "secret/data/platform/webhook"
    body = @{
      data = @{
        API_KEY = "enterprise-demo-api-key"
        WEBHOOK_SECRET = "enterprise-demo-webhook-secret"
      }
    }
  }
)

foreach ($payload in $payloads) {
  Invoke-RestMethod `
    -Method Post `
    -Uri "$VaultAddress/v1/$($payload.path)" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body (($payload.body | ConvertTo-Json -Depth 10))
}

Write-Host "Vault demo secrets seeded."
