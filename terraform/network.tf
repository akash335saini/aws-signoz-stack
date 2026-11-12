# ENIs give us stable private IPs before the instances exist,
# which lets user_data reference all three peer addresses without
# circular dependencies or SSH provisioners.

resource "aws_network_interface" "ch" {
  for_each = local.nodes

  subnet_id       = each.value.subnet
  security_groups = [aws_security_group.ch.id]

  tags = { Name = "${var.project}-${each.value.name}" }
}

resource "aws_security_group" "ch" {
  name_prefix = "${var.project}-ch-"
  description = "ClickHouse cluster"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.project}-ch" }

  lifecycle { create_before_destroy = true }
}

# --- client-facing ports (from allowed CIDRs) ---

resource "aws_security_group_rule" "ch_http_in" {
  security_group_id = aws_security_group.ch.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 8123
  to_port           = 8123
  cidr_blocks       = var.allowed_cidrs
  description       = "CH HTTP"
}

resource "aws_security_group_rule" "ch_native_in" {
  security_group_id = aws_security_group.ch.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 9000
  to_port           = 9000
  cidr_blocks       = var.allowed_cidrs
  description       = "CH native TCP"
}

# --- inter-node ports (self-referencing) ---

resource "aws_security_group_rule" "ch_native_self" {
  security_group_id        = aws_security_group.ch.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 9000
  to_port                  = 9000
  source_security_group_id = aws_security_group.ch.id
  description              = "CH native (inter-node)"
}

resource "aws_security_group_rule" "ch_replication" {
  security_group_id        = aws_security_group.ch.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 9009
  to_port                  = 9009
  source_security_group_id = aws_security_group.ch.id
  description              = "inter-server replication"
}

resource "aws_security_group_rule" "keeper_client" {
  security_group_id        = aws_security_group.ch.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 9181
  to_port                  = 9181
  source_security_group_id = aws_security_group.ch.id
  description              = "Keeper client"
}

resource "aws_security_group_rule" "keeper_raft" {
  security_group_id        = aws_security_group.ch.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 9234
  to_port                  = 9234
  source_security_group_id = aws_security_group.ch.id
  description              = "Keeper Raft"
}

# --- SSH (optional) ---

resource "aws_security_group_rule" "ssh" {
  count = length(var.ssh_cidrs) > 0 ? 1 : 0

  security_group_id = aws_security_group.ch.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = var.ssh_cidrs
  description       = "SSH"
}

# --- egress ---

resource "aws_security_group_rule" "egress" {
  security_group_id = aws_security_group.ch.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}
