param(
  [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "artifacts\\incidents\\latest"),
  [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$timelinePath = Join-Path $OutputDir "timeline.md"
$postmortemPath = Join-Path $OutputDir "postmortem.md"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Add-Timeline {
  param([string]$Message)

  $line = "- $((Get-Date).ToUniversalTime().ToString("o")) - $Message"
  Add-Content -Path $timelinePath -Value $line -Encoding utf8
  Write-Host $line
}

function Invoke-RecordedStep {
  param(
    [string]$Name,
    [scriptblock]$ScriptBlock
  )

  Add-Timeline "START: $Name"
  try {
    & $ScriptBlock
    Add-Timeline "OK: $Name"
  }
  catch {
    Add-Timeline "FAILED: $Name - $($_.Exception.Message)"
    throw
  }
}

function Invoke-Smoke {
  param(
    [string]$Name,
    [switch]$ExpectFailure
  )

  $safeName = $Name.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  $stdoutPath = Join-Path $OutputDir "$safeName.stdout.txt"
  $stderrPath = Join-Path $OutputDir "$safeName.stderr.txt"

  Add-Timeline "START: smoke $Name"
  $process = Start-Process `
    -FilePath "python" `
    -ArgumentList @("automation\\smoke_check.py") `
    -WorkingDirectory $repoRoot `
    -NoNewWindow `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  if ($ExpectFailure) {
    if ($process.ExitCode -eq 0) {
      Add-Timeline "FAILED: smoke $Name unexpectedly passed during failure window"
      throw "Smoke check unexpectedly passed during the incident window."
    }

    Add-Timeline "DETECTED: smoke $Name failed as expected during the incident window"
    return
  }

  if ($process.ExitCode -ne 0) {
    Add-Timeline "FAILED: smoke $Name returned exit code $($process.ExitCode)"
    throw "Smoke check failed with exit code $($process.ExitCode)."
  }

  Add-Timeline "OK: smoke $Name"
}

Set-Content -Path $timelinePath -Value "# Incident Timeline`n" -Encoding utf8
Add-Timeline "Incident drill started"

Invoke-Smoke -Name "baseline"

if (-not $SkipRelease) {
  Invoke-RecordedStep -Name "release known-good GitOps revision" -ScriptBlock {
    & (Join-Path $PSScriptRoot "demo-rollout.ps1") -Action release
  }
}

Invoke-RecordedStep -Name "inject bad ingress release" -ScriptBlock {
  & (Join-Path $PSScriptRoot "demo-rollout.ps1") -Action break
}

Invoke-Smoke -Name "detection-after-bad-release" -ExpectFailure

Invoke-RecordedStep -Name "rollback through GitOps" -ScriptBlock {
  & (Join-Path $PSScriptRoot "demo-rollout.ps1") -Action rollback
}

Invoke-Smoke -Name "post-rollback"

$evidenceDir = Join-Path $OutputDir "evidence"
Invoke-RecordedStep -Name "collect platform evidence" -ScriptBlock {
  & (Join-Path $PSScriptRoot "collect-evidence.ps1") -OutputDir $evidenceDir
}

$postmortem = @"
# Postmortem: Bad GitOps Ingress Release

## Summary

A controlled GitOps change broke the public `service-desk.platform.lab` route by changing the ingress host to an invalid demo host. The failure was detected by the smoke path and recovered through a GitOps rollback.

## Impact

- `service-desk-api` public route became unavailable through the expected host.
- Platform components, Flux, Vault, observability, and the webhook workload were expected to remain available.

## Detection

- `automation/smoke_check.py` failed during the incident window.
- Timeline: `timeline.md`
- Smoke stdout/stderr: `detection-after-bad-release.stdout.txt`, `detection-after-bad-release.stderr.txt`

## Recovery

- `scripts/demo-rollout.ps1 -Action rollback` reverted the bad Git commit.
- Flux reconciled the healthy revision.
- `automation/smoke_check.py` passed after rollback.

## Evidence

- Cluster state: `evidence/`
- Timeline: `timeline.md`
- Baseline smoke: `baseline.stdout.txt`
- Detection smoke: `detection-after-bad-release.stdout.txt`
- Post-rollback smoke: `post-rollback.stdout.txt`

## Follow-Ups

- Keep ingress-host changes behind policy checks where possible.
- Keep smoke checks in the release path so route regressions are caught quickly.
- Consider adding a second drill for registry outage or node loss after this first hardening wave.
"@

Set-Content -Path $postmortemPath -Value $postmortem -Encoding utf8
Add-Timeline "Incident drill completed"
Write-Host "Incident drill evidence written to $OutputDir"
