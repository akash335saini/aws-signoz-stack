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

output "nlb_dns" {
  description = "Internal NLB DNS name for ClickHouse"
  value       = aws_lb.ch.dns_name
}

output "signoz_url" {
  description = "SigNoz UI URL"
  value       = "http://${aws_instance.signoz.private_ip}:8080"
}

output "signoz_otlp_grpc" {
  description = "OTLP gRPC endpoint"
  value       = "${aws_instance.signoz.private_ip}:4317"
}

output "signoz_otlp_http" {
  description = "OTLP HTTP endpoint"
  value       = "${aws_instance.signoz.private_ip}:4318"
}

output "signoz_instance_id" {
  value = aws_instance.signoz.id
}
