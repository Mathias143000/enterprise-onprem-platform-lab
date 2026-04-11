param(
  [Parameter(Mandatory = $true)][string]$Namespace,
  [Parameter(Mandatory = $true)][string]$Kind,
  [Parameter(Mandatory = $true)][string]$Name,
  [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
  try {
    switch ($Kind) {
      "deployment" {
        & kubectl rollout status deployment/$Name -n $Namespace --timeout=15s | Out-Null
        if ($LASTEXITCODE -eq 0) {
          exit 0
        }
      }
      "daemonset" {
        & kubectl rollout status daemonset/$Name -n $Namespace --timeout=15s | Out-Null
        if ($LASTEXITCODE -eq 0) {
          exit 0
        }
      }
      "statefulset" {
        & kubectl rollout status statefulset/$Name -n $Namespace --timeout=15s | Out-Null
        if ($LASTEXITCODE -eq 0) {
          exit 0
        }
      }
      "application" {
        $health = & kubectl get application $Name -n $Namespace -o jsonpath="{.status.health.status}"
        $sync = & kubectl get application $Name -n $Namespace -o jsonpath="{.status.sync.status}"
        if ($health -eq "Healthy" -and $sync -eq "Synced") {
          exit 0
        }
      }
      "gitrepository" {
        $ready = & kubectl get gitrepository $Name -n $Namespace -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
        if ($ready -eq "True") {
          exit 0
        }
      }
      "kustomization" {
        $ready = & kubectl get kustomization $Name -n $Namespace -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
        if ($ready -eq "True") {
          exit 0
        }
      }
      "helmrelease" {
        $ready = & kubectl get helmrelease $Name -n $Namespace -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
        if ($ready -eq "True") {
          exit 0
        }
      }
      "externalsecret" {
        $ready = & kubectl get externalsecret $Name -n $Namespace -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
        if ($ready -eq "True") {
          exit 0
        }
      }
      "certificate" {
        $ready = & kubectl get certificate $Name -n $Namespace -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
        if ($ready -eq "True") {
          exit 0
        }
      }
      default {
        throw "Unsupported kind: $Kind"
      }
    }
  }
  catch {
  }

  Start-Sleep -Seconds 5
}

Write-Error "Timed out waiting for $Kind/$Name in namespace $Namespace."
exit 1
