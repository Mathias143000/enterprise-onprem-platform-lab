import json
import os
import subprocess
import time
import urllib.request


def run(*args: str) -> str:
    completed = subprocess.run(args, check=True, capture_output=True, text=True)
    return completed.stdout.strip()


def get_jsonpath(kind: str, name: str, namespace: str, expression: str) -> str:
    return run(
        "kubectl",
        "get",
        kind,
        name,
        "-n",
        namespace,
        "-o",
        f"jsonpath={expression}",
    )


def wait_ready(kind: str, name: str, namespace: str, expression: str, expected: str = "True", timeout: int = 600) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            value = get_jsonpath(kind, name, namespace, expression)
            if value == expected:
                return
        except subprocess.CalledProcessError:
            pass
        time.sleep(5)
    raise RuntimeError(f"Timed out waiting for {kind}/{name} in {namespace}")


def http_get(url: str, host: str) -> str:
    request = urllib.request.Request(url, headers={"Host": host})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=30) as response:
        return response.read().decode("utf-8")


def main() -> None:
    result: dict[str, object] = {}
    traefik_ip = get_jsonpath("svc", "traefik", "kube-system", "{.status.loadBalancer.ingress[0].ip}")
    if not traefik_ip:
        raise RuntimeError("Traefik external IP is not assigned")
    ingress_base_url = os.environ.get("INGRESS_BASE_URL", "http://127.0.0.1:18080").rstrip("/")

    checks = [
        ("gitrepository", "platform-repo", "flux-system"),
        ("kustomization", "enterprise-platform", "flux-system"),
        ("helmrelease", "prometheus", "observability"),
        ("helmrelease", "loki-stack", "observability"),
        ("helmrelease", "grafana", "observability"),
        ("externalsecret", "service-desk-secrets", "service-desk"),
        ("externalsecret", "webhook-ingestion-secrets", "webhook"),
        ("helmrelease", "service-desk-api", "service-desk"),
        ("helmrelease", "webhook-ingestion-service", "webhook"),
    ]
    for kind, name, namespace in checks:
        wait_ready(kind, name, namespace, "{.status.conditions[?(@.type=='Ready')].status}")

    wait_ready("deployment", "jaeger", "observability", "{.status.readyReplicas}", expected="1")
    wait_ready("deployment", "minio", "platform", "{.status.readyReplicas}", expected="1")

    result["traefik_ip"] = traefik_ip
    result["ingress_base_url"] = ingress_base_url
    result["service_desk_health"] = json.loads(
        http_get(f"{ingress_base_url}/api/health/", "service-desk.platform.lab")
    )
    result["webhook_health"] = json.loads(
        http_get(f"{ingress_base_url}/health", "webhook.platform.lab")
    )

    run(
        "kubectl",
        "exec",
        "-n",
        "platform",
        "deploy/minio",
        "--",
        "sh",
        "-c",
        "echo enterprise-lab > /data/persistence-check.txt",
    )
    run("kubectl", "rollout", "restart", "deployment/minio", "-n", "platform")
    run("kubectl", "rollout", "status", "deployment/minio", "-n", "platform", "--timeout=180s")
    persisted = run(
        "kubectl",
        "exec",
        "-n",
        "platform",
        "deploy/minio",
        "--",
        "cat",
        "/data/persistence-check.txt",
    )
    result["minio_persistence"] = persisted

    deadline = time.time() + 120
    jaeger_services = ""
    while time.time() < deadline:
        jaeger_services = http_get(f"{ingress_base_url}/api/services", "jaeger.platform.lab")
        if "service-desk-api" in jaeger_services or "webhook-ingestion-service" in jaeger_services:
            break
        http_get(f"{ingress_base_url}/api/health/", "service-desk.platform.lab")
        http_get(f"{ingress_base_url}/health", "webhook.platform.lab")
        time.sleep(5)
    if "service-desk-api" not in jaeger_services and "webhook-ingestion-service" not in jaeger_services:
        raise RuntimeError("Jaeger did not report traces for the demo workloads")
    result["jaeger_services"] = json.loads(jaeger_services)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
