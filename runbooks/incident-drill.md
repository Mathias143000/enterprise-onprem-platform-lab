# Incident Drill Runbook

This drill turns the existing release -> break -> rollback demo into postmortem-grade operator evidence.

## Scenario

A bad GitOps change changes the `service-desk-api` ingress host from:

```text
service-desk.platform.lab
```

to:

```text
service-desk-broken.platform.lab
```

The expected route fails, the smoke check detects it, and recovery happens through Git rollback plus Flux reconciliation.

## Preconditions

The platform should already be running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cluster-up.ps1
python automation\smoke_check.py
```

## Run The Drill

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\incident-drill.ps1
```

If you already performed the release step and only want to test the failure window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\incident-drill.ps1 -SkipRelease
```

## Evidence

The drill writes evidence under:

```text
artifacts/incidents/latest/
```

Expected files:

- `timeline.md`
- `postmortem.md`
- `baseline.stdout.txt`
- `detection-after-bad-release.stdout.txt`
- `detection-after-bad-release.stderr.txt`
- `post-rollback.stdout.txt`
- `evidence/`

## What To Explain In An Interview

- The failure was introduced through Git, not by manually editing the cluster.
- Detection came from the same smoke path used for normal validation.
- Recovery was a GitOps rollback, followed by Flux reconciliation.
- Evidence includes both cluster state and smoke output, so the incident can be reviewed after the demo.

## Limitations

- This is a controlled application-routing incident, not a full node-loss or storage-degradation drill.
- It is intentionally the first hardening-wave incident because it is reproducible on a local workstation.
- Deeper drills such as registry outage, node loss, or storage degradation remain backlog items.
