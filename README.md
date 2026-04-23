# Enterprise On-Prem Platform Lab

Enterprise-flavored on-prem Kubernetes lab for vacancies that expect more than a generic cloud-native demo.  
This repository focuses on an honest `enterprise-core v1` scope: multi-node cluster operations, `Flux` GitOps, `Helm`, `MetalLB`, `Traefik`, `Vault`-backed secrets, `MinIO` persistence, and observability with `Prometheus`, `Grafana`, `Loki`, and `Jaeger`.

## Portfolio Role

This is the primary platform flagship in the portfolio.

Use this repository when the discussion is about:

- multi-node Kubernetes operations instead of only single-cluster app delivery
- `Flux` release, break, and rollback flow
- ingress, external IP exposure, secrets, storage, and observability in one lab
- operator automation and runbook-first platform work

Use `k8s-gitops-platform-lab` instead when the review should stay on the cleaner baseline GitOps path with `Argo CD`, local TLS, and a lighter platform scope.

## Status

`Definition of Done` is achieved for the first strong portfolio version and the first technical hardening wave.

What is implemented and validated:

- reproducible multi-node `k3d` cluster with `k3s` workloads
- `Flux` + `Helm` delivery of two real workloads
- `MetalLB` external IP allocation and `Traefik` ingress routing
- `Vault` + `External Secrets` for workload secret consumption
- `MinIO` with persistent volume and restart persistence check
- `Prometheus`, `Grafana`, `Loki`, `Jaeger`
- GitOps release, failure, and rollback drill
- smoke/evidence automation and operator runbook
- CI-safe hardening check with Helm render validation, policy gates, and SBOM evidence
- runtime security markers for workload Deployments
- explicit Vault secret seed/promotion flow
- postmortem-grade incident drill

What is explicitly deferred:

- `Rancher`
- `GitLab CI/CD`
- `Harbor`
- `Longhorn`
- `Calico`
- `Istio`
- `Ansible` node preparation

Those items are explicit non-goals because the goal of this version is credible platform depth, not a museum of partially implemented tools.

## What This Repo Proves

- I can bootstrap and operate a multi-node Kubernetes platform locally.
- I can expose workloads through enterprise-style ingress and load-balancing layers.
- I can wire secret delivery through `Vault` into workloads.
- I can run stateful storage for a demo platform and verify persistence.
- I can collect metrics, logs, and traces for platform and workload troubleshooting.
- I can demonstrate a real GitOps release, a visible failure, and a rollback.

## Implemented Stack

- Cluster: `k3d` with multi-node `k3s`
- GitOps: `Flux`
- Packaging: `Helm`
- Ingress: `Traefik`
- External IPs: `MetalLB`
- Secrets: `Vault` + `External Secrets`
- Storage: `MinIO` on PVC
- Observability: `Prometheus`, `Grafana`, `Loki`, `Jaeger`
- Hardening: GitHub Actions, policy checks, SBOM evidence
- Automation: `PowerShell` + `Python`
- Demo workloads:
  - `service-desk-api`
  - `webhook-ingestion-service`

## Architecture

See [docs/architecture.md](docs/architecture.md).

## Review Path

For a fast technical review, the most useful order is:

1. this README for scope, trade-offs, and demo flow
2. [docs/architecture.md](docs/architecture.md) for platform shape and dependencies
3. [runbooks/demo.md](runbooks/demo.md) for the operator walkthrough
4. `scripts/cluster-up.ps1` for bootstrap orchestration
5. `automation/smoke_check.py` for what is actually verified
6. `scripts/demo-rollout.ps1` for release, break, and rollback proof
7. [docs/hardening.md](docs/hardening.md) for CI-safe policy, SBOM, secrets, and incident evidence

## Quick Demo

1. Validate tooling and manifests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

2. Run CI-safe hardening validation:

```powershell
python automation\hardening_check.py --output-dir artifacts\hardening
```

3. Bootstrap the platform:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1
```

4. Run smoke verification:

```powershell
python automation\smoke_check.py
```

5. Check workload ingress:

```powershell
curl.exe -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
curl.exe -H "Host: webhook.platform.lab" http://127.0.0.1:18080/health
```

6. Run GitOps drill:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action break
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action rollback
```

7. Run the incident drill:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\incident-drill.ps1
```

8. Collect evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect-evidence.ps1
```

## Validated Evidence

The current DoD was verified with:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1`
- `python automation\hardening_check.py --output-dir artifacts\hardening`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-down.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1`
- `python automation\smoke_check.py`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect-evidence.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action release`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action break`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action rollback`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\incident-drill.ps1`

The evidence bundle is written to `artifacts/evidence/latest/`.
Incident evidence is written to `artifacts/incidents/latest/`.

## Validation Story

The current DoD is validated through an operator-first path, not only through static manifests:

| Capability | Current proof |
| --- | --- |
| Multi-node cluster bootstrap | `scripts/cluster-up.ps1` + cluster inventory in the evidence bundle |
| GitOps release / break / rollback | `scripts/demo-rollout.ps1` with visible workload state changes |
| Ingress and external exposure | `curl.exe` health checks through `Traefik` and `MetalLB`-backed routing |
| Secret delivery | `Vault` + `External Secrets` synced into workloads and exercised during smoke |
| Storage persistence | `MinIO` PVC restart persistence check |
| Platform observability | `Prometheus`, `Grafana`, `Loki`, and `Jaeger` reachable after bootstrap |
| CI-safe hardening | `.github/workflows/hardening.yml` + `automation/hardening_check.py` |
| Policy and SBOM evidence | `artifacts/hardening/hardening-report.md` + `artifacts/hardening/sbom.cdx.json` |
| Incident evidence | `scripts/incident-drill.ps1` + `runbooks/incident-drill.md` |

This remains intentionally PowerShell-first for full local platform operations because the repo is meant to prove operator workflow on a Windows workstation. The hardening wave adds a CI-safe representative validation layer for Helm rendering, policy gates, SBOM evidence, secret-flow checks, and incident-drill assets.

## Repo Map

- `.github/` CI hardening workflow
- `cluster/` cluster-side add-ons and generated MetalLB pool
- `flux/` GitOps sources and Kustomization roots
- `helm/` workload charts
- `scripts/` bootstrap, rollout, evidence, and validation commands
- `automation/` Python smoke validation
- `docs/` architecture and notes
- `runbooks/` operator walkthroughs

## Known Limitations

- This repo uses `k3d` to simulate an on-prem cluster; it does not pretend to be a full datacenter deployment.
- `MetalLB` assigns a real cluster IP, but on Docker Desktop the host-side demo path is intentionally routed through `localhost:18080/18443` because direct access to the Docker network VIP is unreliable from Windows.
- `Vault` runs in dev mode for demo speed and reproducibility, while the operator flow now separates environment seed paths from current runtime paths.
- `MinIO` persistence is demonstrated with a PVC, while `Longhorn` is intentionally outside this portfolio slice.
- The repo demonstrates `Flux`-driven GitOps, but not the full `GitLab -> Harbor -> Flux` enterprise chain yet.
- The current SBOM is repo-local delivery evidence, not a full registry-backed attestation/signing platform.

## Explicit Non-Goals

- `Rancher` management layer
- `GitLab CI/CD`
- `Harbor` registry flow
- `Longhorn`
- `Calico`
- `Istio` + deeper service-mesh story
- `Ansible` node preparation
- additional failure drills: node loss, registry outage, storage degradation

These are deliberate boundaries for the current flagship, not open DoD work.

## Hardening Wave 1 DoD

The first technical hardening wave is now closed around depth, not breadth:

- CI-safe representative validation through GitHub Actions
- Helm render checks for `dev` and `demo` values
- policy gates for image tags, secret ownership, probes, resources, ingress class, and runtime security markers
- CycloneDX-style SBOM evidence for workload images and charts
- secret seed/promotion documentation and script support
- postmortem-grade incident drill with timeline, smoke output, rollback, and evidence bundle

The larger-scope non-goals are intentionally excluded from this DoD: registry-backed signing, external admission policy enforcement, production Vault auth/policies, node-loss drills, registry outage drills, and storage degradation drills.
