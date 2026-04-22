# Demo Runbook

## Goal

Show a compact enterprise-style platform story in 10-15 minutes:

1. cluster bootstrap
2. GitOps-delivered workloads
3. Vault-backed secrets
4. metrics, logs, and traces
5. stateful persistence
6. failure, rollback, and hardening evidence

## Prerequisites

- Docker Desktop is running
- `kubectl` context can be switched by the provided scripts
- no local port conflict on `18018`, `18080`, `18200`, `18443`

## 1. Validate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## 2. Bootstrap the lab

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1
```

Expected result:

- three nodes are `Ready`
- `Flux` is healthy
- `service-desk-api` and `webhook-ingestion-service` are healthy
- `Traefik` has a `MetalLB` IP

## 3. Smoke the platform

```powershell
python automation\smoke_check.py
```

Expected result:

- service-desk health is `ok`
- webhook health is `ok`
- MinIO persistence check passes
- Jaeger reports at least one workload trace

## 4. Verify ingress from the host

```powershell
curl.exe -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
curl.exe -H "Host: webhook.platform.lab" http://127.0.0.1:18080/health
curl.exe -H "Host: jaeger.platform.lab" http://127.0.0.1:18080/api/services
```

## 5. Explain secret delivery

For the hardening-wave promotion model, see [../docs/secrets-promotion.md](../docs/secrets-promotion.md).

```powershell
kubectl get clustersecretstore enterprise-vault
kubectl get externalsecrets -A
kubectl describe externalsecret -n service-desk service-desk-secrets
```

Talking point:

- secrets are seeded into `Vault`
- `External Secrets` syncs them into Kubernetes
- workloads consume standard Kubernetes secrets, not hardcoded values

## 6. Run the GitOps drill

### Release

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action release
curl.exe -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
```

Expected result:

- service-desk stays healthy
- response version changes from `2.0.0` to `2.0.1` or `2.0.2`

### Break

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action break
curl.exe -o NUL -w "%{http_code}" -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
```

Expected result:

- canonical route returns `404`
- broken host now owns the route

### Rollback

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollout.ps1 -Action rollback
curl.exe -H "Host: service-desk.platform.lab" http://127.0.0.1:18080/api/health/
```

Expected result:

- canonical route returns `200` again
- workload is healthy after rollback

## 7. Collect evidence

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect-evidence.ps1
```

Evidence files land in `artifacts/evidence/latest/`.

## 8. Optional hardening drill

```powershell
python automation\hardening_check.py --output-dir artifacts\hardening
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\incident-drill.ps1
```

Hardening evidence lands in `artifacts/hardening/` and incident evidence lands in `artifacts/incidents/latest/`.

## 9. Tear down

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-down.ps1
```

## Known Caveats

- The host demo path uses `localhost:18080/18443`, even though `MetalLB` assigns a cluster IP, because Docker Desktop networking does not expose that VIP reliably to the Windows host.
- `Vault` runs in dev mode.
- `Rancher`, `GitLab`, `Harbor`, `Longhorn`, and `Istio` are not part of v1 and should be called out as backlog, not hidden.
