output "node_ips" {
  description = "Private IPs of the ClickHouse nodes"
  value       = { for k, v in aws_network_interface.ch : local.nodes[k].name => v.private_ip }
}

output "node_ids" {
  description = "EC2 instance IDs"
  value       = { for k, v in aws_instance.ch : local.nodes[k].name => v.id }
}

output "security_group_id" {
  value = aws_security_group.ch.id
}

output "iam_role_arn" {
  value = aws_iam_role.ch.arn
}

output "signoz_config" {
  description = "Connection details for SigNoz"
  value = {
    host    = aws_network_interface.ch["0"].private_ip
    port    = 9000
    user    = "default"
    cluster = var.cluster_name
  }
}
