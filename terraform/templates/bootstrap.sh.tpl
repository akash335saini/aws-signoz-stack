#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/clickhouse-bootstrap.log) 2>&1

DATA_DIR="/var/lib/clickhouse"
CONF_DIR="/etc/clickhouse-server/config.d"
USERS_DIR="/etc/clickhouse-server/users.d"

###
### 1. Mount data volume
###

# Nitro instances surface EBS as /dev/nvme*; the attachment may lag behind boot.
DEVICE=""
for _ in $(seq 1 60); do
  for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    [ -b "$dev" ] && DEVICE="$dev" && break 2
  done
  sleep 2
done
[ -z "$DEVICE" ] && { echo "data volume never appeared"; exit 1; }

blkid "$DEVICE" >/dev/null 2>&1 || mkfs.ext4 -m 0 -F "$DEVICE"
mkdir -p "$DATA_DIR"
mountpoint -q "$DATA_DIR" || mount "$DEVICE" "$DATA_DIR"

UUID=$(blkid -s UUID -o value "$DEVICE")
grep -q "$UUID" /etc/fstab || \
  echo "UUID=$UUID $DATA_DIR ext4 defaults,noatime,nofail 0 2" >> /etc/fstab

###
### 2. Install ClickHouse LTS
###

apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg netcat-openbsd

curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' \
  | gpg --dearmor --yes -o /usr/share/keyrings/clickhouse-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb lts main" \
  > /etc/apt/sources.list.d/clickhouse.list

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  clickhouse-server clickhouse-client clickhouse-common-static

systemctl stop clickhouse-server 2>/dev/null || true
systemctl enable clickhouse-server
chown -R clickhouse:clickhouse "$DATA_DIR"

###
### 3. Cluster config
###

mkdir -p "$CONF_DIR" "$USERS_DIR"

cat > "$CONF_DIR/cluster.xml" <<'CONF'
<clickhouse>
  <remote_servers>
    <${cluster_name}>
      <shard>
        <internal_replication>true</internal_replication>
        <replica><host>${node1_ip}</host><port>9000</port></replica>
        <replica><host>${node2_ip}</host><port>9000</port></replica>
        <replica><host>${node3_ip}</host><port>9000</port></replica>
      </shard>
    </${cluster_name}>
  </remote_servers>
  <distributed_ddl>
    <path>/clickhouse/task_queue/ddl</path>
  </distributed_ddl>
  <zookeeper>
    <node><host>${node1_ip}</host><port>9181</port></node>
    <node><host>${node2_ip}</host><port>9181</port></node>
    <node><host>${node3_ip}</host><port>9181</port></node>
  </zookeeper>
</clickhouse>
CONF

cat > "$CONF_DIR/macros.xml" <<'CONF'
<clickhouse>
  <macros>
    <cluster>${cluster_name}</cluster>
    <shard>1</shard>
    <replica>${node_name}</replica>
  </macros>
</clickhouse>
CONF

cat > "$CONF_DIR/keeper.xml" <<'CONF'
<clickhouse>
  <keeper_server>
    <tcp_port>9181</tcp_port>
    <server_id>${node_id}</server_id>
    <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
    <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
    <coordination_settings>
      <operation_timeout_ms>10000</operation_timeout_ms>
      <session_timeout_ms>30000</session_timeout_ms>
      <raft_logs_level>warning</raft_logs_level>
    </coordination_settings>
    <raft_configuration>
      <server><id>1</id><hostname>${node1_ip}</hostname><port>9234</port></server>
      <server><id>2</id><hostname>${node2_ip}</hostname><port>9234</port></server>
      <server><id>3</id><hostname>${node3_ip}</hostname><port>9234</port></server>
    </raft_configuration>
  </keeper_server>
</clickhouse>
CONF

cat > "$CONF_DIR/listen.xml" <<'CONF'
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  <http_port>8123</http_port>
  <tcp_port>9000</tcp_port>
  <interserver_http_port>9009</interserver_http_port>
</clickhouse>
CONF

cat > "$USERS_DIR/default.xml" <<'CONF'
<clickhouse>
  <users>
    <default>
      <password_sha256_hex>${password_hash}</password_sha256_hex>
      <networks><ip>::/0</ip></networks>
      <profile>default</profile>
      <quota>default</quota>
      <access_management>1</access_management>
    </default>
  </users>
</clickhouse>
CONF

chown -R clickhouse:clickhouse "$CONF_DIR" "$USERS_DIR" "$DATA_DIR"

###
### 4. Start
###

systemctl start clickhouse-server

for _ in $(seq 1 30); do
  curl -sf http://localhost:8123/ping >/dev/null 2>&1 && break
  sleep 5
done

echo "bootstrap done: node ${node_id} (${node_name})"
