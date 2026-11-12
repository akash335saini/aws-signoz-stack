#!/bin/bash
set -euo pipefail

# Quick post-deploy smoke test for the 3-node ClickHouse cluster.
# Usage: ./verify-cluster.sh <node1-ip> <node2-ip> <node3-ip> [password]

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <ip1> <ip2> <ip3> [password]"
  exit 1
fi

IPS=("$1" "$2" "$3")
PW="${4:-}"
PW_FLAG=""
[[ -n "$PW" ]] && PW_FLAG="--password $PW"

FAIL=0
ok()   { echo "  [ok]   $1"; }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "--- keeper health ---"
for ip in "${IPS[@]}"; do
  resp=$(echo ruok | nc -w3 "$ip" 9181 2>/dev/null || true)
  [[ "$resp" == "imok" ]] && ok "keeper $ip" || fail "keeper $ip (got: $resp)"
done

echo "--- cluster topology ---"
COUNT=$(clickhouse-client --host "${IPS[0]}" $PW_FLAG \
  --query "SELECT count() FROM system.clusters WHERE cluster='cluster'" \
  --format TabSeparated 2>/dev/null || echo 0)
[[ "$COUNT" -eq 3 ]] && ok "3 replicas in cluster" || fail "expected 3 replicas, got $COUNT"

echo "--- replication ---"
TABLE="_verify_$(date +%s)"
clickhouse-client --host "${IPS[0]}" $PW_FLAG --query "
  CREATE TABLE $TABLE ON CLUSTER 'cluster'
  (id UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/$TABLE', '{replica}')
  ORDER BY id" 2>/dev/null && ok "DDL on cluster" || fail "DDL on cluster"

clickhouse-client --host "${IPS[0]}" $PW_FLAG \
  --query "INSERT INTO $TABLE VALUES (1),(2),(3)" 2>/dev/null
sleep 3

for ip in "${IPS[@]}"; do
  n=$(clickhouse-client --host "$ip" $PW_FLAG \
    --query "SELECT count() FROM $TABLE" --format TabSeparated 2>/dev/null || echo 0)
  [[ "$n" -ge 3 ]] && ok "replication $ip ($n rows)" || fail "replication $ip ($n rows)"
done

clickhouse-client --host "${IPS[0]}" $PW_FLAG \
  --query "DROP TABLE $TABLE ON CLUSTER 'cluster' SYNC" 2>/dev/null

echo "---"
[[ $FAIL -eq 0 ]] && echo "all checks passed" || echo "$FAIL check(s) failed"
exit "$FAIL"
