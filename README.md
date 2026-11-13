# aws-signoz-stack

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-844FBA.svg)](https://www.terraform.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-LTS-FFCC00.svg)](https://clickhouse.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-Foundry-F76B1C.svg)](https://signoz.io)

Terraform module that deploys a **3-node ClickHouse cluster** with an **internal NLB** and a **SigNoz observability stack** on AWS EC2. SigNoz runs via [Foundry](https://github.com/SigNoz/foundry) (Docker Compose) and connects to the external ClickHouse cluster through the NLB for automatic HA failover.

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Verification](#verification)
- [Operations](#operations)
- [Design Decisions](#design-decisions)
- [Contributing](#contributing)
- [License](#license)

## Architecture

```
                              VPC (bring your own)
  ┌────────────────────────────────────────────────────────────┐
  │                                                            │
  │  ┌──────────────┐         ┌──────────────────────────┐     │
  │  │  SigNoz EC2  │         │     Internal NLB         │     │
  │  │  t3a.medium  │────────►│  :9000 (native TCP)      │     │
  │  │              │         │  :8123 (HTTP)             │     │
  │  │  - SigNoz UI │         └──────┬───────┬───────┬────┘     │
  │  │  - OTel Coll │               │       │       │          │
  │  │  - PostgreSQL│         ┌─────┘       │       └─────┐    │
  │  └──────────────┘         ▼             ▼             ▼    │
  │       AZ-a             ch-1          ch-2          ch-3    │
  │                        AZ-a          AZ-b          AZ-c    │
  │                     ┌─────────┐  ┌─────────┐  ┌─────────┐ │
  │                     │ CH + K1 │  │ CH + K2 │  │ CH + K3 │ │
  │                     │ EBS gp3 │  │ EBS gp3 │  │ EBS gp3 │ │
  │                     └─────────┘  └─────────┘  └─────────┘ │
  └────────────────────────────────────────────────────────────┘
```

### ClickHouse Cluster

| | |
|---|---|
| **Topology** | 1 shard, 3 replicas |
| **Cluster name** | `cluster` (SigNoz requirement) |
| **Coordination** | Embedded ClickHouse Keeper (3-node Raft) |
| **Default instance** | `c6a.large` (2 vCPU / 4 GB) |
| **Data volume** | 100 GB gp3, separate from root |

### SigNoz

| | |
|---|---|
| **Instance** | `t3a.medium` (2 vCPU / 4 GB) |
| **Deployment** | Docker Compose via [Foundry](https://github.com/SigNoz/foundry) |
| **ClickHouse connection** | Via internal NLB (HA failover) |
| **UI** | Port 8080 |
| **OTLP ingestion** | gRPC 4317, HTTP 4318 |

### What gets created

| Resource | Count | Purpose |
|----------|-------|---------|
| `aws_network_interface` | 3 | Stable private IPs for CH nodes |
| `aws_instance` | 3 + 1 | ClickHouse nodes + SigNoz |
| `aws_ebs_volume` | 3 | Persistent CH data volumes |
| `aws_lb` | 1 | Internal NLB for ClickHouse HA |
| `aws_lb_target_group` | 2 | TCP/9000 (native) + TCP/8123 (HTTP) |
| `aws_security_group` | 2 | ClickHouse cluster + SigNoz |
| `aws_iam_role` | 1 | SSM + CloudWatch + EC2 describe |

## Prerequisites

- **Terraform** >= 1.5
- **AWS CLI** configured with credentials that can create EC2, EBS, IAM, ELB, and SG resources
- An existing **VPC** with **3 subnets** in different Availability Zones
- An **SSH key pair** registered in the target AWS region

## Quick Start

```bash
git clone https://github.com/akash335saini/aws-signoz-stack.git
cd aws-signoz-stack/terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in vpc_id, subnet_ids, key_name, allowed_cidrs

terraform init
terraform plan  -var 'clickhouse_password=<your-password>'
terraform apply -var 'clickhouse_password=<your-password>'
```

After apply, open SigNoz at `http://<signoz-ip>:8080` (get the IP from `terraform output signoz_url`).

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `vpc_id` | ID of your existing VPC |
| `subnet_ids` | List of exactly 3 subnet IDs across different AZs |
| `key_name` | SSH key pair name in the target region |
| `allowed_cidrs` | CIDRs allowed to reach ClickHouse and SigNoz ports |
| `clickhouse_password` | Password for the `default` ClickHouse user (sensitive) |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `instance_type` | `c6a.large` | EC2 instance type for ClickHouse nodes |
| `signoz_instance_type` | `t3a.medium` | EC2 instance type for SigNoz |
| `ami_id` | `ami-02a9cdd4e98bc3c78` | Ubuntu 24.04 AMI (us-east-1) |
| `data_volume_gb` | `100` | CH data volume size in GB |
| `data_volume_type` | `gp3` | EBS volume type |
| `data_volume_iops` | `3000` | Provisioned IOPS |
| `data_volume_throughput` | `125` | Throughput in MB/s (gp3 only) |
| `ssh_cidrs` | `[]` | CIDRs allowed SSH access (empty = no SSH rule) |
| `cluster_name` | `cluster` | ClickHouse cluster name (must be `cluster` for SigNoz) |
| `project` | `clickhouse` | Prefix for resource names and tags |
| `env` | `production` | Environment tag |

### Outputs

| Output | Description |
|--------|-------------|
| `node_ips` | Map of CH node name to private IP |
| `node_ids` | Map of CH node name to EC2 instance ID |
| `nlb_dns` | Internal NLB DNS name for ClickHouse |
| `signoz_url` | SigNoz UI URL |
| `signoz_otlp_grpc` | OTLP gRPC endpoint (for instrumented apps) |
| `signoz_otlp_http` | OTLP HTTP endpoint |
| `signoz_instance_id` | SigNoz EC2 instance ID |
| `security_group_id` | ClickHouse security group ID |
| `iam_role_arn` | IAM role ARN |

## Verification

### ClickHouse Cluster

After `terraform apply`, check the CH bootstrap log on any node:

```bash
cat /var/log/clickhouse-bootstrap.log
```

Run the smoke-test script from a host that can reach all three nodes:

```bash
./scripts/verify-cluster.sh <node1-ip> <node2-ip> <node3-ip> <password>
```

### NLB Health

```bash
# Check all 3 CH targets are healthy
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw nlb_native_tg_arn 2>/dev/null || echo "check console")
```

### SigNoz

Check the SigNoz bootstrap log:

```bash
ssh -i <key> ubuntu@<signoz-ip> "cat /var/log/signoz-bootstrap.log"
```

Verify containers are running:

```bash
ssh -i <key> ubuntu@<signoz-ip> "docker ps"
```

Expected containers: `signoz-signoz-0`, `signoz-ingester-1`, `signoz-metastore-postgres-0`.
Should **not** have clickhouse or keeper containers (those run on the external CH cluster).

Check SigNoz health:

```bash
curl http://<signoz-ip>:8080/api/v1/health
```

Open the UI at `http://<signoz-ip>:8080`, create the admin user, and verify the ClickHouse connection under Settings.

### Sending Test Telemetry

From any host that can reach SigNoz:

```bash
# OTLP HTTP
curl -X POST http://<signoz-ip>:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d '{"resourceSpans":[]}'
```

Or configure your application's OpenTelemetry SDK:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<signoz-ip>:4317  # gRPC
# or
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<signoz-ip>:4318  # HTTP
```

### Ports

| Port | Service | Purpose |
|------|---------|---------|
| 8080 | SigNoz | UI and API |
| 4317 | SigNoz | OTLP gRPC ingestion |
| 4318 | SigNoz | OTLP HTTP ingestion |
| 8123 | ClickHouse | HTTP interface, health checks |
| 9000 | ClickHouse | Native TCP |
| 9009 | ClickHouse | Inter-server replication |
| 9181 | ClickHouse | Keeper client |
| 9234 | ClickHouse | Keeper Raft consensus |

## Operations

| Task | How |
|------|-----|
| **Scale CH storage** | Bump `data_volume_gb` in tfvars, `terraform apply`, then `resize2fs` on each node |
| **Scale CH compute** | Change `instance_type`, `terraform apply` (instances replaced, data volumes persist) |
| **Scale SigNoz** | Change `signoz_instance_type`, `terraform apply` |
| **Backups** | AWS Backup / DLM on the `*-data` EBS volumes. For consistency: `ALTER TABLE ... FREEZE PARTITION` first |
| **CH Monitoring** | Prometheus metrics at `:8123/metrics`. Keeper: `echo mntr \| nc <host> 9181` |
| **SSH-less access** | `aws ssm start-session --target <instance-id>` (IAM role includes SSM) |
| **SigNoz logs** | `ssh ubuntu@<signoz-ip> "cd /opt/signoz/pours/deployment && docker compose logs -f"` |

## Design Decisions

**ENIs for stable IPs** -- Each CH node's config references all three peers. Creating `aws_network_interface` resources first gives Terraform the IPs before instances exist, so `user_data` renders cleanly without circular dependencies or SSH provisioners.

**Internal NLB for ClickHouse HA** -- SigNoz connects to the NLB DNS name instead of individual node IPs. The NLB health-checks each CH node on port 8123 (`/ping`) and stops routing to unhealthy targets. If a CH node goes down, SigNoz automatically uses the remaining healthy nodes with zero config changes.

**Separate EBS volumes** -- Data volumes are independent resources with `prevent_destroy`. Instance replacement (AMI update, type change) doesn't touch data. The bootstrap waits up to 2 minutes for the device to appear after boot.

**Password hashing in Terraform** -- `sha256()` runs in Terraform; only the hash reaches the CH instances. No cleartext password in shell commands or `/proc`.

**Foundry for SigNoz** -- SigNoz's supported deployment method since v0.130.0. The `casting.yaml` disables the built-in ClickHouse/Keeper containers and configures the SigNoz query service and OTel collector to connect to the external cluster via the NLB. PostgreSQL (for SigNoz metadata) runs locally in Docker on the SigNoz instance.

**Replication-aware schema migration** -- `SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_REPLICATION=true` ensures SigNoz creates `ReplicatedMergeTree` tables instead of plain `MergeTree`. Without this flag, data would not replicate across the 3 CH nodes.

## Repository Layout

```
.
├── README.md
├── scripts/
│   └── verify-cluster.sh              # post-deploy smoke test
└── terraform/
    ├── versions.tf                     # required providers
    ├── main.tf                         # provider, locals, data sources
    ├── variables.tf                    # input variables
    ├── network.tf                      # CH security group + ENIs
    ├── iam.tf                          # IAM role + instance profile
    ├── instances.tf                    # CH EC2 + EBS + volume attachments
    ├── nlb.tf                          # internal NLB for ClickHouse HA
    ├── signoz.tf                       # SigNoz EC2 + security group
    ├── outputs.tf                      # outputs
    ├── templates/
    │   ├── bootstrap.sh.tpl            # CH cloud-init bootstrap
    │   └── signoz-bootstrap.sh.tpl     # SigNoz Docker + Foundry bootstrap
    └── terraform.tfvars.example        # example variable values
```

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Run `terraform fmt -recursive` and `terraform validate` before committing
4. Open a pull request
