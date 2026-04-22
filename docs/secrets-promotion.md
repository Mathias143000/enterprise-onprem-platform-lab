# Secrets Promotion Flow

This lab intentionally keeps the runtime demo fast by using Vault dev mode, but the secret workflow is shaped like an operator flow rather than hardcoded application values.

## Goals

- keep real secret values out of Git
- seed demo material into Vault through an operator command
- keep GitOps manifests focused on references, not secret payloads
- make environment promotion explicit enough to discuss in an interview

## Paths

The seeding script writes environment-scoped material first:

```text
secret/data/platform/dev/service-desk
secret/data/platform/demo/service-desk
secret/data/platform/stage/service-desk
secret/data/platform/dev/webhook
secret/data/platform/demo/webhook
secret/data/platform/stage/webhook
```

By default it also promotes the selected environment to the current paths consumed by `ExternalSecret` resources:

```text
secret/data/platform/service-desk
secret/data/platform/webhook
```

The workloads do not read the environment-scoped paths directly. They read Kubernetes `Secret` objects materialized by `External Secrets` from the current Vault paths.

## Operator Commands

Seed demo defaults and promote them to the current runtime paths:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\seed-vault.ps1 -Environment demo
```

Seed environment-scoped material without promotion:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\seed-vault.ps1 -Environment stage -NoPromoteToCurrent
```

Seed from local environment variables instead of demo defaults:

```powershell
$env:SERVICE_DESK_DJANGO_SECRET_KEY = "local-only-value"
$env:WEBHOOK_API_KEY = "local-only-value"
$env:WEBHOOK_SECRET = "local-only-value"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\seed-vault.ps1 -Environment demo
```

## What This Proves

- GitOps stores the desired secret references through `ExternalSecret`, not application secret payloads.
- Secret material can be prepared per environment before promotion.
- Promotion is explicit and reversible in the operator workflow.
- The demo remains reproducible without pretending that Vault dev mode is production Vault.

## Known Limitations

- Vault still runs in dev mode for this local lab.
- The `vault-token` Kubernetes `Secret` is demo bootstrap material, not a production authentication model.
- A production version would replace this with Kubernetes auth, tighter policies, audit logging, and real secret rotation.
