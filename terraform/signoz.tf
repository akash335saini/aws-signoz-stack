resource "aws_instance" "signoz" {
  ami                    = local.ami
  instance_type          = var.signoz_instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.signoz.id]
  iam_instance_profile   = aws_iam_instance_profile.ch.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/signoz-bootstrap.sh.tpl", {
    nlb_dns             = aws_lb.ch.dns_name
    clickhouse_password = var.clickhouse_password
    cluster_name        = var.cluster_name
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${var.project}-signoz", Role = "signoz" }

  lifecycle { ignore_changes = [ami] }
}

# --- SigNoz security group ---

resource "aws_security_group" "signoz" {
  name_prefix = "${var.project}-signoz-"
  description = "SigNoz UI and OTLP ingestion"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project}-signoz" }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "signoz_ui" {
  security_group_id = aws_security_group.signoz.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_blocks       = var.allowed_cidrs
  description       = "SigNoz UI"
}

resource "aws_security_group_rule" "signoz_otlp_grpc" {
  security_group_id = aws_security_group.signoz.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 4317
  to_port           = 4317
  cidr_blocks       = var.allowed_cidrs
  description       = "OTLP gRPC"
}

resource "aws_security_group_rule" "signoz_otlp_http" {
  security_group_id = aws_security_group.signoz.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 4318
  to_port           = 4318
  cidr_blocks       = var.allowed_cidrs
  description       = "OTLP HTTP"
}

resource "aws_security_group_rule" "signoz_ssh" {
  count = length(var.ssh_cidrs) > 0 ? 1 : 0

  security_group_id = aws_security_group.signoz.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = var.ssh_cidrs
  description       = "SSH"
}

resource "aws_security_group_rule" "signoz_egress" {
  security_group_id = aws_security_group.signoz.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}
