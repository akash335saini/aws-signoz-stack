# Internal NLB for ClickHouse HA.
# SigNoz connects to the NLB DNS name; the NLB health-checks each
# CH node and routes traffic only to healthy targets.

resource "aws_lb" "ch" {
  name               = "${var.project}-ch-internal"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = { Name = "${var.project}-ch-nlb" }
}

# --- Native TCP (9000) ---

resource "aws_lb_target_group" "ch_native" {
  name        = "${var.project}-ch-native"
  port        = 9000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    port                = "8123"
    path                = "/ping"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "ch_native" {
  load_balancer_arn = aws_lb.ch.arn
  port              = 9000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ch_native.arn
  }
}

resource "aws_lb_target_group_attachment" "ch_native" {
  for_each = local.nodes

  target_group_arn = aws_lb_target_group.ch_native.arn
  target_id        = aws_network_interface.ch[each.key].private_ip
  port             = 9000
}

# --- HTTP (8123) ---

resource "aws_lb_target_group" "ch_http" {
  name        = "${var.project}-ch-http"
  port        = 8123
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    port                = "8123"
    path                = "/ping"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "ch_http" {
  load_balancer_arn = aws_lb.ch.arn
  port              = 8123
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ch_http.arn
  }
}

resource "aws_lb_target_group_attachment" "ch_http" {
  for_each = local.nodes

  target_group_arn = aws_lb_target_group.ch_http.arn
  target_id        = aws_network_interface.ch[each.key].private_ip
  port             = 8123
}
