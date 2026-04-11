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

`Definition of Done` is achieved for the first strong portfolio version.

What is implemented and validated:

- reproducible multi-node `k3d` cluster with `k3s` workloads
- `Flux` + `Helm` delivery of two real workloads
- `MetalLB` external IP allocation and `Traefik` ingress routing
- `Vault` + `External Secrets` for workload secret consumption
- `MinIO` with persistent volume and restart persistence check
- `Prometheus`, `Grafana`, `Loki`, `Jaeger`
- GitOps release, failure, and rollback drill
- smoke/evidence automation and operator runbook

What is explicitly deferred:

- `Rancher`
- `GitLab CI/CD`
- `Harbor`
- `Longhorn`
- `Calico`
- `Istio`
- `Ansible` node preparation

Those items stay in backlog because the goal of this version is credible platform depth, not a museum of partially implemented tools.

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

## Quick Demo

1. Validate tooling and manifests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

2. Bootstrap the platform:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1
```

3. Run smoke verification:

```powershell
python automation\smoke_check.py
```

4. Check workload ingress:

```powershell
curl.exe -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
curl.exe -H "Host: webhook.platform.lab" http://127.0.0.1:18080/health
```

5. Run GitOps drill:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action break
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action rollback
```

6. Collect evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect-evidence.ps1
```

## Validated Evidence

The current DoD was verified with:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-down.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1`
- `python automation\smoke_check.py`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect-evidence.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action release`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action break`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action rollback`

The evidence bundle is written to `artifacts/evidence/latest/`.

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

This is intentionally a PowerShell-first local validation story because the repo is meant to prove operator workflow on a Windows workstation. The next step is not to replace that path, but to automate a representative subset of it in CI so the repo shows both hands-on platform operations and repeatable machine validation.

## Repo Map

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
- `Vault` runs in dev mode for demo speed and reproducibility.
- `MinIO` persistence is demonstrated with a PVC, but `Longhorn` is intentionally deferred to backlog.
- The repo demonstrates `Flux`-driven GitOps, but not the full `GitLab -> Harbor -> Flux` enterprise chain yet.

## Backlog After DoD

- `Rancher` management layer
- `GitLab CI/CD`
- `Harbor` registry flow
- `Longhorn`
- `Calico`
- `Istio` + deeper service-mesh story
- `Ansible` node preparation
- additional failure drills: node loss, registry outage, storage degradation

## Next Hardening Milestone

The next meaningful upgrade for this repo is depth, not breadth:

- automate a representative bootstrap + smoke path on a CI runner
- add stronger supply-chain signals such as `SBOM`, image signing, and policy checks
- deepen the secret and promotion story beyond the current demo-safe baseline
- document one postmortem-grade incident drill with clearer operator evidence

That is the line between the current strong portfolio lab and a more obvious `senior+` platform signal.
