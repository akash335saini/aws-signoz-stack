variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "clickhouse"
}

variable "env" {
  description = "Environment (dev, staging, production)"
  type        = string
  default     = "production"
}

# --- Networking (bring your own) ---

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "Exactly 3 subnet IDs in different AZs"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "Provide exactly 3 subnets."
  }
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach ClickHouse ports (8123, 9000)"
  type        = list(string)
}

variable "ssh_cidrs" {
  description = "CIDRs allowed SSH access (leave empty to disable)"
  type        = list(string)
  default     = []
}

# --- EC2 ---

variable "instance_type" {
  description = "EC2 instance type for ClickHouse nodes"
  type        = string
  default     = "m6i.2xlarge"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "ami_id" {
  description = "Override AMI (defaults to Ubuntu 24.04 in us-east-1)"
  type        = string
  default     = "ami-02a9cdd4e98bc3c78"
}

# --- EBS data volume ---

variable "data_volume_gb" {
  description = "Data volume size in GB"
  type        = number
  default     = 500
}

variable "data_volume_type" {
  description = "EBS type for data volume"
  type        = string
  default     = "gp3"
}

variable "data_volume_iops" {
  type    = number
  default = 3000
}

variable "data_volume_throughput" {
  description = "MB/s (gp3 only)"
  type        = number
  default     = 125
}

# --- ClickHouse ---

variable "clickhouse_password" {
  description = "Password for the default ClickHouse user"
  type        = string
  sensitive   = true
}

# SigNoz hardcodes this name in its migration SQL.
variable "cluster_name" {
  type    = string
  default = "cluster"
}
