param(
  [ValidateSet("release", "break", "rollback")]
  [string]$Action = "release"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$worktreePath = Join-Path $repoRoot "artifacts\\git\\platform-worktree"
$bareRepoPath = Join-Path $repoRoot "artifacts\\git\\platform.git"
$sourceFluxPath = Join-Path $repoRoot "flux"
$workloadFile = Join-Path $sourceFluxPath "apps\\base\\workloads-service-desk.yaml"

if (-not (Test-Path $workloadFile)) {
  throw "Flux source is not ready. Run cluster-up.ps1 first."
}

function Request-FluxReconcile {
  $timestamp = (Get-Date).ToUniversalTime().ToString("o")
  & kubectl annotate gitrepository platform-repo -n flux-system "reconcile.fluxcd.io/requestedAt=$timestamp" --overwrite | Out-Null
  & kubectl annotate kustomization enterprise-platform -n flux-system "reconcile.fluxcd.io/requestedAt=$timestamp" --overwrite | Out-Null
}

function Wait-ForJsonPathValue {
  param(
    [string]$Command,
    [string]$ExpectedValue,
    [int]$TimeoutSeconds = 600
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $value = Invoke-Expression $Command
    if ($value -eq $ExpectedValue) {
      return
    }
    Start-Sleep -Seconds 5
  }

  throw "Timed out waiting for command result '$ExpectedValue': $Command"
}

function Wait-ForRevisionApplied {
  param([string]$Revision)

  $escapedRevision = $Revision.Replace("'", "''")
  Wait-ForJsonPathValue -Command "kubectl get gitrepository platform-repo -n flux-system -o jsonpath=""{.status.artifact.revision}""" -ExpectedValue $Revision -TimeoutSeconds 300
  Wait-ForJsonPathValue -Command "kubectl get kustomization enterprise-platform -n flux-system -o jsonpath=""{.status.lastAppliedRevision}""" -ExpectedValue $Revision -TimeoutSeconds 900
  Wait-ForJsonPathValue -Command "kubectl get kustomization enterprise-platform -n flux-system -o jsonpath=""{.status.conditions[?(@.type=='Ready')].status}""" -ExpectedValue "True" -TimeoutSeconds 900
}

$previousHead = (& git -C $worktreePath rev-parse HEAD).Trim()
$content = Get-Content $workloadFile -Raw
$pushedHead = $null

switch ($Action) {
  "release" {
    if ($content -match 'appVersion:\s+"2\.0\.1"') {
      $content = $content -replace 'appVersion:\s+"2\.0\.1"', 'appVersion: "2.0.2"'
    }
    elseif ($content -match 'appVersion:\s+"2\.0\.0"') {
      $content = $content -replace 'appVersion:\s+"2\.0\.0"', 'appVersion: "2.0.1"'
    }
    Set-Content -Path $workloadFile -Value $content -NoNewline
    & (Join-Path $PSScriptRoot "push-gitops.ps1") -Message "Release service-desk enterprise demo"
    $pushedHead = (& git -C $worktreePath rev-parse HEAD).Trim()
  }
  "break" {
    if ($content -notmatch 'host:\s+service-desk-broken\.platform\.lab') {
      if ($content -match 'host:\s+service-desk\.platform\.lab') {
        $content = $content -replace 'host:\s+service-desk\.platform\.lab', 'host: service-desk-broken.platform.lab'
      }
      else {
        throw "Failed to locate canonical ingress host in workloads-service-desk.yaml"
      }
      Set-Content -Path $workloadFile -Value $content -NoNewline
      & (Join-Path $PSScriptRoot "push-gitops.ps1") -Message "Break service-desk ingress in enterprise lab"
      $pushedHead = (& git -C $worktreePath rev-parse HEAD).Trim()
    }
  }
  "rollback" {
    Push-Location $worktreePath
    try {
      & git revert --no-edit HEAD | Out-Null
      & git push origin main | Out-Null
    }
    finally {
      Pop-Location
    }

    & git -C $bareRepoPath update-server-info
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (Test-Path $sourceFluxPath) {
      Remove-Item -Recurse -Force $sourceFluxPath
    }
    Copy-Item -Recurse -Force (Join-Path $worktreePath "flux") $sourceFluxPath
    $pushedHead = (& git -C $worktreePath rev-parse HEAD).Trim()
  }
}

if ($pushedHead -and $pushedHead -ne $previousHead) {
  $revision = "main@sha1:$pushedHead"
  Request-FluxReconcile
  Wait-ForRevisionApplied -Revision $revision
  Write-Host "Flux applied revision $revision"
}
