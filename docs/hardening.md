# Hardening Validation

This document captures the first technical hardening wave for the enterprise on-prem platform lab.

The goal is not to turn the local lab into a fake production datacenter. The goal is to add machine-checkable guardrails and operator evidence around the platform story that already exists.

## What Is Covered

- CI-safe Helm lint and render validation
- GitOps workload secret-reference checks
- Kubernetes manifest policy checks
- runtime security markers on workload Deployments
- CycloneDX-style SBOM generation for chart and image inventory
- explicit Vault seed and promotion flow
- postmortem-grade incident drill around a bad GitOps ingress release

## CI-Safe Validation

Run the hardening check locally:

```powershell
python automation\hardening_check.py --output-dir artifacts\hardening
```

The check writes:

```text
artifacts/hardening/hardening-report.md
artifacts/hardening/sbom.cdx.json
artifacts/hardening/rendered/
```

The same check is wired into GitHub Actions through:

```text
.github/workflows/hardening.yml
```

## Policy Gates

The hardening check currently fails when:

- GitOps workload values create chart-owned Kubernetes `Secret` resources instead of consuming `ExternalSecret` output
- local Git-backed workload charts are not reconciled by Git revision
- workload images use `latest`
- rendered Deployments miss probes, resource requests/limits, seccomp, dropped capabilities, or `allowPrivilegeEscalation: false`
- rendered Ingress objects do not use the expected `traefik` class
- required hardening assets such as the incident drill or secrets promotion documentation are missing

This is intentionally compact and repo-local. A production version would likely move these rules into OPA/Conftest, Kyverno, or admission policies.

## Supply Chain Evidence

The generated SBOM is a lightweight CycloneDX-style inventory for:

- workload container images referenced by rendered manifests
- Helm charts maintained in this repository

This is not a replacement for a full registry-backed SBOM/signing workflow. It is the first hardening-wave signal that images and charts are treated as controlled delivery artifacts.

## Runtime Security

The workload charts now render:

- `seccompProfile: RuntimeDefault`
- `allowPrivilegeEscalation: false`
- dropped Linux capabilities
- explicit readiness and liveness probes
- resource requests and limits

`readOnlyRootFilesystem` remains `false` because these demo workloads still need local writable paths. That choice is explicit instead of accidental.

## Secrets Flow

See [secrets-promotion.md](secrets-promotion.md).

The short version:

- seed environment-scoped material into Vault
- optionally promote that material to the current runtime paths
- keep GitOps manifests focused on `ExternalSecret` references
- avoid storing real secret payloads in Git

## Incident Drill

See [../runbooks/incident-drill.md](../runbooks/incident-drill.md).

The drill proves:

- a bad release is introduced through GitOps
- the same smoke path detects the route regression
- recovery happens through Git rollback and Flux reconciliation
- evidence and a postmortem-style note are collected under `artifacts/incidents/latest/`

## Remaining Backlog

- full registry-backed signing flow
- external admission-controller enforcement
- registry outage drill
- node-loss drill
- storage-degradation drill
- production Vault auth/policy model
