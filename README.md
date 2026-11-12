# aws-signoz-stack

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-844FBA.svg)](https://www.terraform.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-LTS-FFCC00.svg)](https://clickhouse.com)

Terraform module that deploys a **3-node ClickHouse cluster** (1 shard, 3 replicas) on AWS EC2 with embedded ClickHouse Keeper. Built to serve as an external ClickHouse backend for [SigNoz](https://signoz.io), but works as a standalone cluster too.

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Verification](#verification)
- [Connecting SigNoz](#connecting-signoz)
- [Operations](#operations)
- [Design Decisions](#design-decisions)
- [Contributing](#contributing)
- [License](#license)

## Architecture

```
                           VPC (bring your own)
   ┌───────────────────┬───────────────────┬───────────────────┐
   │    AZ-a           │    AZ-b           │    AZ-c           │
   │                   │                   │                   │
   │  ┌─────────────┐  │  ┌─────────────┐  │  ┌─────────────┐  │
   │  │   ch-1      │  │  │   ch-2      │  │  │   ch-3      │  │
   │  │  ClickHouse │◄─┼──┤  ClickHouse │◄─┼──┤  ClickHouse │  │
   │  │  + Keeper 1 │──┼─►│  + Keeper 2 │──┼─►│  + Keeper 3 │  │
   │  │  EBS (gp3)  │  │  │  EBS (gp3)  │  │  │  EBS (gp3)  │  │
   │  └─────────────┘  │  └─────────────┘  │  └─────────────┘  │
   └───────────────────┴───────────────────┴───────────────────┘
```

| | |
|---|---|
| **Topology** | 1 shard, 3 replicas |
| **Cluster name** | `cluster` (SigNoz requirement) |
| **Coordination** | Embedded ClickHouse Keeper (3-node Raft) |
| **Default instance** | `m6i.2xlarge` (8 vCPU / 32 GB) |
| **Default AMI** | Ubuntu 24.04 (`ami-02a9cdd4e98bc3c78`) |
| **Data volume** | 500 GB gp3, separate from root, `prevent_destroy` |

### What gets created

| Resource | Count | Purpose |
|----------|-------|---------|
| `aws_network_interface` | 3 | Stable private IPs (known before boot) |
| `aws_instance` | 3 | ClickHouse nodes, one per AZ |
| `aws_ebs_volume` | 3 | Persistent data volumes |
| `aws_security_group` | 1 | Client + inter-node port rules |
| `aws_iam_role` | 1 | SSM + CloudWatch + EC2 describe |

## Prerequisites

- **Terraform** >= 1.5
- **AWS CLI** configured with credentials that can create EC2, EBS, IAM, and SG resources
- An existing **VPC** with **3 subnets** in different Availability Zones
- An **SSH key pair** registered in the target AWS region

## Quick Start

```bash
git clone https://github.com/<your-org>/aws-signoz-stack.git
cd aws-signoz-stack/terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in vpc_id, subnet_ids, key_name, allowed_cidrs

terraform init
terraform plan  -var 'clickhouse_password=<your-password>'
terraform apply -var 'clickhouse_password=<your-password>'
```

Or use the Makefile from the repo root:

```bash
cd aws-signoz-stack
make init
make plan    # prompts for clickhouse_password
make apply
```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `vpc_id` | ID of your existing VPC |
| `subnet_ids` | List of exactly 3 subnet IDs across different AZs |
| `key_name` | SSH key pair name in the target region |
| `allowed_cidrs` | CIDRs allowed to reach ClickHouse ports (8123, 9000) |
| `clickhouse_password` | Password for the `default` ClickHouse user (sensitive) |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `instance_type` | `m6i.2xlarge` | EC2 instance type |
| `ami_id` | `ami-02a9cdd4e98bc3c78` | Ubuntu 24.04 AMI (us-east-1) |
| `data_volume_gb` | `500` | EBS data volume size in GB |
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
| `node_ips` | Map of node name to private IP |
| `node_ids` | Map of node name to EC2 instance ID |
| `security_group_id` | ID of the ClickHouse security group |
| `iam_role_arn` | ARN of the IAM role attached to nodes |
| `signoz_config` | Object with `host`, `port`, `user`, `cluster` for SigNoz |

## Verification

After `terraform apply`, SSH into any node (or use SSM Session Manager) and check the bootstrap log:

```bash
cat /var/log/clickhouse-bootstrap.log
```

Run the included smoke-test script from any host that can reach all three nodes:

```bash
./scripts/verify-cluster.sh <node1-ip> <node2-ip> <node3-ip> <password>
```

This checks Keeper quorum, cluster topology (3 replicas in `system.clusters`), and a round-trip replication test.

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8123 | TCP | HTTP interface, health checks (`/ping`), Prometheus metrics |
| 9000 | TCP | Native TCP (SigNoz, `clickhouse-client`) |
| 9009 | TCP | Inter-server replication (node-to-node) |
| 9181 | TCP | Keeper client (node-to-node) |
| 9234 | TCP | Keeper Raft consensus (node-to-node) |

## Connecting SigNoz

### Docker Compose

Comment out the built-in `clickhouse` / `zookeeper` services in your SigNoz `docker-compose.yml` and set:

```yaml
environment:
  - CLICKHOUSE_HOST=<node1-ip>    # from terraform output -json | jq '.signoz_config'
  - CLICKHOUSE_PORT=9000
  - CLICKHOUSE_USER=default
  - CLICKHOUSE_PASSWORD=<password>
```

### Helm

```yaml
# signoz-values.yaml
clickhouse:
  enabled: false
  host: <node1-ip>
  port: 9000
  user: default
  password: <password>

schemaMigrator:
  enableReplication: true
```

> **Important:** `enableReplication: true` makes SigNoz create `ReplicatedMergeTree` tables. Without it you get plain `MergeTree` and replication silently does nothing.

## Operations

| Task | How |
|------|-----|
| **Scale storage** | Bump `data_volume_gb` in tfvars, `make apply`, then `resize2fs` on each node |
| **Scale compute** | Change `instance_type`, `make apply` (instances replaced, data volumes persist) |
| **Backups** | AWS Backup / DLM on the `*-data` EBS volumes. For consistency: `ALTER TABLE ... FREEZE PARTITION` first |
| **Monitoring** | Prometheus metrics at `:8123/metrics`. Keeper: `echo mntr \| nc <host> 9181` |
| **SSH-less access** | `aws ssm start-session --target <instance-id>` (IAM role includes SSM) |

## Design Decisions

**ENIs for stable IPs** -- Each node's config references all three peers. Creating `aws_network_interface` resources first gives Terraform the IPs before instances exist, so `user_data` renders cleanly without circular dependencies or SSH provisioners.

**Separate EBS volumes** -- Data volumes are independent resources with `prevent_destroy`. Instance replacement (AMI update, type change) doesn't touch data. The bootstrap waits up to 2 minutes for the device to appear after boot.

**Password hashing in Terraform** -- `sha256()` runs in Terraform; only the hash reaches the instance. No cleartext password in shell commands or `/proc`.

**Embedded Keeper** -- ClickHouse Keeper runs inside the ClickHouse process on all 3 nodes (3-node Raft quorum, tolerates 1 failure). For heavy workloads, move Keeper to dedicated instances.

## Repository Layout

```
.
├── LICENSE
├── Makefile
├── README.md
├── scripts/
│   └── verify-cluster.sh          # post-deploy smoke test
└── terraform/
    ├── versions.tf                 # required providers
    ├── main.tf                     # provider, locals, data sources
    ├── variables.tf                # input variables
    ├── network.tf                  # security group + ENIs
    ├── iam.tf                      # IAM role + instance profile
    ├── instances.tf                # EC2 + EBS + volume attachments
    ├── outputs.tf                  # outputs
    ├── templates/
    │   └── bootstrap.sh.tpl        # cloud-init bootstrap script
    └── terraform.tfvars.example    # example variable values
```

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Run `make fmt` and `make validate` before committing
4. Open a pull request

## License

[MIT](LICENSE)
