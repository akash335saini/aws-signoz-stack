resource "aws_instance" "ch" {
  for_each = local.nodes

  ami                  = local.ami
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ch.name

  network_interface {
    network_interface_id = aws_network_interface.ch[each.key].id
    device_index         = 0
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/bootstrap.sh.tpl", {
    node_id       = each.value.id
    node_name     = each.value.name
    cluster_name  = var.cluster_name
    password_hash = local.password_hash
    node1_ip      = aws_network_interface.ch["0"].private_ip
    node2_ip      = aws_network_interface.ch["1"].private_ip
    node3_ip      = aws_network_interface.ch["2"].private_ip
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${var.project}-${each.value.name}", Role = "clickhouse" }

  lifecycle { ignore_changes = [ami] }
}

# Separate data volumes so they survive instance replacement.
resource "aws_ebs_volume" "ch_data" {
  for_each = local.nodes

  availability_zone = data.aws_subnet.ch[each.key].availability_zone
  size              = var.data_volume_gb
  type              = var.data_volume_type
  iops              = var.data_volume_iops
  throughput        = var.data_volume_type == "gp3" ? var.data_volume_throughput : null
  encrypted         = true

  tags = { Name = "${var.project}-${each.value.name}-data" }

  lifecycle { prevent_destroy = true }
}

resource "aws_volume_attachment" "ch_data" {
  for_each = local.nodes

  device_name  = "/dev/xvdf"
  instance_id  = aws_instance.ch[each.key].id
  volume_id    = aws_ebs_volume.ch_data[each.key].id
  force_detach = false
}
