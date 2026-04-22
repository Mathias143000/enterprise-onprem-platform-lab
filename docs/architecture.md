# Architecture

## Enterprise-Core v1 Scope

This repository intentionally stops at the first strong enterprise-core milestone:

- multi-node `k3d` cluster running `k3s`
- `Flux`-driven reconciliation from a local Git smart HTTP source
- `Helm`-managed workloads
- `MetalLB` + `Traefik` for ingress and service exposure
- `Vault` + `External Secrets` for secret injection
- `MinIO` with persistent volume
- `Prometheus`, `Grafana`, `Loki`, `Jaeger`
- workload rollout/failure/rollback drill
- CI-safe hardening checks for Helm rendering, policy gates, SBOM evidence, secrets flow, and incident-drill assets

`Rancher`, `GitLab`, `Harbor`, `Longhorn`, and `Istio` are intentionally left for the next wave.

## Platform Diagram

```mermaid
flowchart LR
    Dev[Operator] --> Scripts[PowerShell and Python automation]
    Dev --> CI[GitHub Actions hardening workflow]
    Scripts --> Docker[Docker Compose sidecars]
    Docker --> GitHTTP[Git smart HTTP daemon]
    Docker --> Vault[Vault dev server]

    Scripts --> K3d[k3d multi-node cluster]
    K3d --> Flux[Flux controllers]
    Flux --> GitHTTP
    Flux --> Helm[Helm releases]

    Helm --> SD[service-desk-api]
    Helm --> WH[webhook-ingestion-service]
    Helm --> Obs[Prometheus Grafana Loki]

    Vault --> ESO[External Secrets]
    ESO --> SD
    ESO --> WH

    SD --> Jaeger[Jaeger]
    WH --> Jaeger

    MetalLB[MetalLB] --> Traefik[Traefik ingress]
    Traefik --> SD
    Traefik --> WH
    Traefik --> Obs
    Traefik --> MinIO[MinIO console]
    Traefik --> Jaeger

    CI --> Render[Helm lint and render]
    CI --> Policy[Policy gates]
    CI --> SBOM[SBOM evidence]
```

## Network Diagram

```mermaid
flowchart TB
    Host[Windows host] --> LocalHTTP[localhost:18080]
    Host --> LocalHTTPS[localhost:18443]
    LocalHTTP --> K3dLB[k3d load balancer]
    LocalHTTPS --> K3dLB

    K3dLB --> NodePort80[Traefik NodePort 30080]
    K3dLB --> NodePort443[Traefik NodePort 30443]
    NodePort80 --> TraefikSvc[Traefik service]
    NodePort443 --> TraefikSvc

    TraefikSvc --> SDIngress[service-desk.platform.lab]
    TraefikSvc --> WHIngress[webhook.platform.lab]
    TraefikSvc --> GrafanaIngress[grafana.platform.lab]
    TraefikSvc --> PromIngress[prometheus.platform.lab]
    TraefikSvc --> JaegerIngress[jaeger.platform.lab]
    TraefikSvc --> MinIOIngress[minio.platform.lab]
```

## Secret Flow

1. `scripts/seed-vault.ps1` writes environment-scoped demo material into `Vault`.
2. The script can promote the selected environment to current runtime paths.
3. `ClusterSecretStore enterprise-vault` points `External Secrets` to `Vault`.
4. `ExternalSecret` resources materialize Kubernetes secrets in workload namespaces.
5. Workloads read those secrets through standard `secretKeyRef` env vars.

## GitOps Flow

1. Source manifests live in `flux/` and `helm/`.
2. `scripts/bootstrap-gitops-repo.ps1` creates a bare repo and worktree for the demo Git source.
3. `scripts/push-gitops.ps1` syncs source manifests into the worktree and pushes to the bare repo.
4. `Flux` reads `GitRepository platform-repo`.
5. `Kustomization enterprise-platform` applies the desired state.
6. `HelmRelease` resources reconcile workloads and platform components.
7. Workload charts use `reconcileStrategy: Revision` so local chart changes are picked up from Git revisions, not only chart version bumps.

## Failure and Recovery Story

The reproducible drill uses `scripts/demo-rollout.ps1`:

- `release`: bumps `service-desk-api` app version and waits for Flux to apply the new revision
- `break`: changes the canonical ingress host so the public route fails visibly
- `rollback`: reverts the last bad commit and waits until the healthy route returns

This is deliberately simple, but it is observable and operator-friendly.

The hardening-wave incident drill in `scripts/incident-drill.ps1` wraps the same failure mode with baseline smoke, detection smoke, rollback, evidence collection, and a postmortem-style note.

## Hardening Flow

`automation/hardening_check.py` provides a CI-safe validation path:

1. lint and render workload Helm charts for `dev` and `demo` values
2. verify GitOps values consume `ExternalSecret` output instead of chart-created secrets
3. enforce compact policy gates on image tags, probes, resources, seccomp, dropped capabilities, and ingress class
4. generate a CycloneDX-style SBOM inventory for workload images and charts
5. verify that secret-promotion and incident-drill assets are present

The full cluster demo remains local and operator-first. The CI path is a representative hardening gate, not a fake replacement for the full `k3d` runtime.
