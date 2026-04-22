import argparse
import json
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHARTS = {
    "service-desk-api": {
        "path": ROOT / "helm" / "apps" / "service-desk-api",
        "namespace": "service-desk",
        "values": ["values-dev.yaml", "values-demo.yaml"],
    },
    "webhook-ingestion-service": {
        "path": ROOT / "helm" / "apps" / "webhook-ingestion-service",
        "namespace": "webhook",
        "values": ["values-dev.yaml", "values-demo.yaml"],
    },
}
FLUX_WORKLOADS = [
    ROOT / "flux" / "apps" / "base" / "workloads-service-desk.yaml",
    ROOT / "flux" / "apps" / "base" / "workloads-webhook.yaml",
]


def run(command: list[str], cwd: Path = ROOT) -> str:
    completed = subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    return completed.stdout


def find_helm() -> str:
    helm = shutil.which("helm")
    if helm:
        return helm

    local = ROOT / ".tools" / "bin" / "helm.exe"
    if local.exists():
        return str(local)

    raise RuntimeError("helm was not found in PATH or .tools/bin. Run scripts/ensure-tools.ps1 first.")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def scalar(text: str, key: str) -> str:
    match = re.search(rf"(?m)^\s*{re.escape(key)}:\s*['\"]?([^'\"\n]+)", text)
    return match.group(1).strip() if match else ""


def split_documents(rendered: str) -> list[str]:
    return [doc.strip() for doc in re.split(r"(?m)^---\s*$", rendered) if doc.strip()]


def document_kind(doc: str) -> str:
    return scalar(doc, "kind")


def document_name(doc: str) -> str:
    match = re.search(r"(?m)^metadata:\s*\n(?:\s{2,}.+\n)*?\s{2}name:\s*([^\n]+)", doc)
    return match.group(1).strip() if match else "unknown"


def lint_and_render(output_dir: Path) -> list[Path]:
    helm = find_helm()
    rendered_files: list[Path] = []
    render_dir = output_dir / "rendered"
    render_dir.mkdir(parents=True, exist_ok=True)

    for chart_name, chart in CHARTS.items():
        chart_path = chart["path"]
        run([helm, "lint", str(chart_path)])

        for values_name in chart["values"]:
            values_path = chart_path / values_name
            run([helm, "lint", str(chart_path), "--values", str(values_path)])
            rendered = run(
                [
                    helm,
                    "template",
                    chart_name,
                    str(chart_path),
                    "--namespace",
                    chart["namespace"],
                    "--values",
                    str(values_path),
                ]
            )
            rendered_path = render_dir / f"{chart_name}-{values_path.stem}.yaml"
            rendered_path.write_text(rendered, encoding="utf-8")
            rendered_files.append(rendered_path)

    return rendered_files


def validate_kustomization(errors: list[str]) -> None:
    kustomization = ROOT / "flux" / "apps" / "base" / "kustomization.yaml"
    text = read_text(kustomization)
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            resource = stripped[2:].strip()
            if not (kustomization.parent / resource).exists():
                errors.append(f"kustomization references missing resource: {resource}")


def validate_flux_secret_flow(errors: list[str]) -> None:
    for path in FLUX_WORKLOADS:
        text = read_text(path)
        if re.search(r"create:\s*true", text):
            errors.append(f"{path.relative_to(ROOT)} enables chart-created secrets in GitOps values")
        if "existingSecretName:" not in text:
            errors.append(f"{path.relative_to(ROOT)} does not bind workloads to External Secrets output")
        if "reconcileStrategy: Revision" not in text:
            errors.append(f"{path.relative_to(ROOT)} should reconcile local Git-backed Helm charts by revision")
        if re.search(r"tag:\s*['\"]?latest['\"]?", text):
            errors.append(f"{path.relative_to(ROOT)} uses an unpinned latest image tag")

    vault_text = read_text(ROOT / "flux" / "apps" / "base" / "platform-vault.yaml")
    for required in ["ClusterSecretStore", "ExternalSecret", "platform/service-desk", "platform/webhook"]:
        if required not in vault_text:
            errors.append(f"platform-vault.yaml is missing required secret-flow marker: {required}")


def validate_operator_hardening_assets(errors: list[str]) -> None:
    required_files = [
        ROOT / ".github" / "workflows" / "hardening.yml",
        ROOT / "docs" / "secrets-promotion.md",
        ROOT / "runbooks" / "incident-drill.md",
        ROOT / "scripts" / "incident-drill.ps1",
    ]
    for path in required_files:
        if not path.exists():
            errors.append(f"missing hardening asset: {path.relative_to(ROOT)}")

    seed_vault = read_text(ROOT / "scripts" / "seed-vault.ps1")
    for marker in ["Environment", "NoPromoteToCurrent", "platform/$Environment/service-desk", "platform/$Environment/webhook"]:
        if marker not in seed_vault:
            errors.append(f"seed-vault.ps1 is missing promotion-flow marker: {marker}")

    incident_drill = read_text(ROOT / "scripts" / "incident-drill.ps1")
    for marker in ["postmortem.md", "timeline.md", "demo-rollout.ps1", "collect-evidence.ps1"]:
        if marker not in incident_drill:
            errors.append(f"incident-drill.ps1 is missing evidence marker: {marker}")


def validate_rendered_manifests(rendered_files: list[Path]) -> list[str]:
    errors: list[str] = []
    for rendered_path in rendered_files:
        text = read_text(rendered_path)
        rel = rendered_path.relative_to(ROOT)

        if re.search(r"image:\s*['\"]?[^'\"\s]+:latest['\"]?", text):
            errors.append(f"{rel} contains a latest image tag")

        for doc in split_documents(text):
            kind = document_kind(doc)
            name = document_name(doc)
            marker = f"{rel} {kind}/{name}"

            if kind == "Secret":
                errors.append(f"{marker} renders a Kubernetes Secret in GitOps hardening mode")

            if kind == "Deployment":
                for required in [
                    "readinessProbe:",
                    "livenessProbe:",
                    "resources:",
                    "requests:",
                    "limits:",
                    "seccompProfile:",
                    "allowPrivilegeEscalation: false",
                    "capabilities:",
                    "- ALL",
                ]:
                    if required not in doc:
                        errors.append(f"{marker} is missing required runtime hardening marker: {required}")
                if "privileged: true" in doc:
                    errors.append(f"{marker} enables privileged mode")

            if kind == "Ingress" and "ingressClassName: traefik" not in doc:
                errors.append(f"{marker} does not use the expected Traefik ingress class")

    return errors


def collect_images(rendered_files: list[Path]) -> list[str]:
    images: set[str] = set()
    for rendered_path in rendered_files:
        text = read_text(rendered_path)
        for match in re.finditer(r"(?m)^\s*image:\s*['\"]?([^'\"\n]+)", text):
            images.add(match.group(1).strip())
    return sorted(images)


def chart_version(chart_path: Path) -> str:
    chart = read_text(chart_path / "Chart.yaml")
    return scalar(chart, "version") or "0.0.0"


def write_sbom(output_dir: Path, rendered_files: list[Path]) -> Path:
    components: list[dict[str, str]] = []
    for image in collect_images(rendered_files):
        repository, _, tag = image.rpartition(":")
        components.append(
            {
                "type": "container",
                "name": repository or image,
                "version": tag or "unpinned",
                "purl": f"pkg:docker/{repository or image}@{tag or 'unpinned'}",
            }
        )

    for chart_name, chart in CHARTS.items():
        version = chart_version(chart["path"])
        components.append(
            {
                "type": "application",
                "name": f"helm-chart/{chart_name}",
                "version": version,
                "purl": f"pkg:generic/{chart_name}@{version}",
            }
        )

    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, 'enterprise-onprem-platform-lab-hardening')}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": "enterprise-onprem-platform-lab",
                "version": "hardening-v1",
            }
        },
        "components": components,
    }
    sbom_path = output_dir / "sbom.cdx.json"
    sbom_path.write_text(json.dumps(sbom, indent=2), encoding="utf-8")
    return sbom_path


def write_report(output_dir: Path, rendered_files: list[Path], errors: list[str], sbom_path: Path) -> Path:
    lines = [
        "# Enterprise Platform Hardening Report",
        "",
        f"Rendered manifests: `{len(rendered_files)}`",
        f"SBOM: `{sbom_path.relative_to(ROOT)}`",
        "",
        "## Policy Result",
        "",
    ]
    if errors:
        lines.append("Status: failed")
        lines.append("")
        lines.extend(f"- {error}" for error in errors)
    else:
        lines.append("Status: passed")
        lines.append("")
        lines.extend(
            [
                "- Helm charts lint and render for `dev` and `demo` values.",
                "- GitOps workload values consume External Secrets output instead of chart-created secrets.",
                "- Rendered workloads avoid `latest` tags and privileged containers.",
                "- Runtime hardening markers are present: probes, resources, seccomp, dropped capabilities, and no privilege escalation.",
                "- Traefik ingress class is explicit.",
            ]
        )

    report_path = output_dir / "hardening-report.md"
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run CI-safe hardening checks for the enterprise platform lab.")
    parser.add_argument("--output-dir", default=str(ROOT / "artifacts" / "hardening"))
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    errors: list[str] = []
    try:
        rendered_files = lint_and_render(output_dir)
        validate_kustomization(errors)
        validate_flux_secret_flow(errors)
        validate_operator_hardening_assets(errors)
        errors.extend(validate_rendered_manifests(rendered_files))
        sbom_path = write_sbom(output_dir, rendered_files)
        report_path = write_report(output_dir, rendered_files, errors, sbom_path)
    except Exception as exc:
        print(f"hardening check failed before report generation: {exc}", file=sys.stderr)
        return 1

    print(f"hardening report: {report_path}")
    print(f"sbom: {sbom_path}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
