#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/signoz-bootstrap.log) 2>&1

###
### 1. Install Docker Engine + Compose v2
###

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg

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

###
### 3. Write casting.yaml
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
  telemetrystore:
    spec:
      enabled: false
  telemetrykeeper:
    spec:
      enabled: false
  signoz:
    spec:
      env:
        SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN: "tcp://default:${clickhouse_password}@${nlb_dns}:9000"
        SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_CLUSTER: "${cluster_name}"
  ingester:
    spec:
      env:
        SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN: "tcp://default:${clickhouse_password}@${nlb_dns}:9000"
        SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER: "${cluster_name}"
        SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION: "true"
CASTING

###
### 4. Deploy SigNoz
###

cd /opt/signoz
foundryctl cast -f casting.yaml

echo "signoz bootstrap done"
