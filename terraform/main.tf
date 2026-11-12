provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

locals {
  nodes = { for i in range(3) : tostring(i) => {
    id     = i + 1
    name   = "ch-${i + 1}"
    subnet = var.subnet_ids[i]
  } }

  password_hash = sha256(var.clickhouse_password)
  ami           = var.ami_id
}

data "aws_subnet" "ch" {
  for_each = local.nodes
  id       = each.value.subnet
}
