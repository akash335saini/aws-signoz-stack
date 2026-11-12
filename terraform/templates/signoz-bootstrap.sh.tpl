#!/bin/bash
set -euxo pipefail
export HOME="$${HOME:-/root}"
exec > >(tee /var/log/signoz-bootstrap.log) 2>&1

###
### 1. Install Docker Engine + Compose v2
###

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg python3

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

###
### 2. Install foundryctl
###

curl -fsSL https://signoz.io/foundry.sh | bash
export PATH="$HOME/.local/bin:$PATH"

###
### 3. Generate compose files (forge only, don't start)
###

mkdir -p /opt/signoz
cat > /opt/signoz/casting.yaml <<'CASTING'
apiVersion: v1alpha1
kind: Installation
metadata:
  name: signoz
spec:
  deployment:
    flavor: compose
    mode: docker
CASTING

cd /opt/signoz
foundryctl gauge -f casting.yaml
foundryctl forge -f casting.yaml

###
### 4. Strip ClickHouse and Keeper services, point to external CH
###

COMPOSE_FILE="/opt/signoz/pours/deployment/compose.yaml"

python3 <<PYEOF
import yaml, sys, copy

with open("$COMPOSE_FILE") as f:
    doc = yaml.safe_load(f)

# Services to remove (ClickHouse, Keeper, and the init container)
remove_prefixes = ("telemetrystore-clickhouse", "telemetrykeeper", "init-")
services = doc.get("services", {})
to_delete = [name for name in services if any(name.startswith(p) or name.startswith("signoz-" + p) for p in remove_prefixes)]
for name in to_delete:
    del services[name]
    print(f"Removed service: {name}")

# External ClickHouse DSN
CH_DSN = "tcp://default:${clickhouse_password}@${nlb_dns}:9000"

# Patch remaining services: remove depends_on refs to deleted services, set CH env
for name, svc in services.items():
    # Clean depends_on
    deps = svc.get("depends_on")
    if isinstance(deps, dict):
        svc["depends_on"] = {k: v for k, v in deps.items() if k not in to_delete}
        if not svc["depends_on"]:
            del svc["depends_on"]
    elif isinstance(deps, list):
        svc["depends_on"] = [d for d in deps if d not in to_delete]
        if not svc["depends_on"]:
            del svc["depends_on"]

    # Set ClickHouse env on signoz + ingester + migrator services
    env = svc.get("environment")
    if env is None:
        continue

    if isinstance(env, list):
        env_dict = {}
        for item in env:
            if "=" in item:
                k, v = item.split("=", 1)
                env_dict[k] = v
            else:
                env_dict[item] = ""
        env = env_dict
        svc["environment"] = env

    # SigNoz query service
    if "SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN" in env:
        env["SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN"] = CH_DSN
        env["SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_CLUSTER"] = "${cluster_name}"

    # OTel collector (ingester + migrator)
    if "SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN" in env:
        env["SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN"] = CH_DSN
        env["SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER"] = "${cluster_name}"
        env["SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION"] = "true"

# Remove volumes that belong to deleted services
volumes = doc.get("volumes", {})
vol_delete = [v for v in volumes if any(p.replace("-", "") in v.replace("-", "") for p in ("clickhouse", "keeper", "zookeeper"))]
for v in vol_delete:
    del volumes[v]
    print(f"Removed volume: {v}")

with open("$COMPOSE_FILE", "w") as f:
    yaml.dump(doc, f, default_flow_style=False, sort_keys=False)

print("Compose file patched for external ClickHouse")
PYEOF

echo "--- Final compose.yaml ---"
cat "$COMPOSE_FILE"

###
### 5. Start SigNoz
###

cd /opt/signoz/pours/deployment
docker compose up -d

echo "signoz bootstrap done"
