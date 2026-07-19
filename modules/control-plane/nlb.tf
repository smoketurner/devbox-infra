# Internet-facing Network Load Balancer fronting the control plane. It terminates
# TLS with the ACM cert (see dns.tf) on a static Elastic IP, so the hostname has a
# stable address, and forwards TCP to the Fargate tasks. The tasks themselves run
# in a public subnet with public IPs for direct egress to DSQL's public endpoint
# and ECR (the NLB is L4, so there is no dashboard OIDC gate here — the API is
# bearer-token validated app-side; see the AUTH_* env in ecs.tf).

resource "aws_security_group" "nlb" {
  name        = "${local.name_prefix}-nlb"
  description = "Internet-facing NLB for the devbox control plane"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nlb" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "HTTPS from allowed networks"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv6" {
  for_each = toset(var.ingress_ipv6_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "HTTPS from allowed networks (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_tasks" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Forward to the control-plane tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.service.id
}

# Egress proxy: reachable only from the pool's NAT egress IP (not the open API
# ingress), and forwarded to the tasks on the proxy port.
# Open to the same networks as the API: the proxy is reached over the internet
# (hosts egress via NAT in a separate VPC), and destination control is the proxy's
# own allowlist, not this SG. Fine for dev; a private path would restrict the source.
resource "aws_vpc_security_group_ingress_rule" "nlb_proxy" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "CONNECT egress proxy"
  ip_protocol       = "tcp"
  from_port         = var.egress_proxy_port
  to_port           = var.egress_proxy_port
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nlb_proxy_ipv6" {
  for_each = toset(var.ingress_ipv6_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "CONNECT egress proxy (IPv6)"
  ip_protocol       = "tcp"
  from_port         = var.egress_proxy_port
  to_port           = var.egress_proxy_port
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_tasks_proxy" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Forward the egress proxy port to the tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.egress_proxy_port
  to_port                      = var.egress_proxy_port
  referenced_security_group_id = aws_security_group.service.id
}

resource "aws_security_group" "service" {
  name        = "${local.name_prefix}-service"
  description = "Devbox control plane Fargate tasks"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-service" })
}

resource "aws_vpc_security_group_ingress_rule" "service_from_nlb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the NLB (data + health checks)"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "service_proxy_from_nlb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Egress proxy port from the NLB (data + health checks)"
  ip_protocol                  = "tcp"
  from_port                    = var.egress_proxy_port
  to_port                      = var.egress_proxy_port
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_egress_rule" "service_https" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound HTTPS (AWS APIs, ECR, DSQL token signing)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "service_https_ipv6" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound HTTPS (AWS APIs, ECR, DSQL token signing) (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_egress_rule" "service_dsql" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound to Aurora DSQL public endpoint (PostgreSQL wire protocol)"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "service_dsql_ipv6" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound to Aurora DSQL public endpoint (PostgreSQL wire protocol) (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv6         = "::/0"
}

# Static public IP for the NLB so the hostname maps to a stable address.
resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name_prefix}-nlb" })
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-cp"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]
  ip_address_type    = "dualstack"

  # The EIP carries the static IPv4; AWS auto-assigns the node's IPv6 from the
  # subnet's IPv6 CIDR (the control-plane VPC's public subnet is dual-stack).
  subnet_mapping {
    subnet_id     = var.subnet_ids[0]
    allocation_id = aws_eip.nlb.id
  }

  tags = local.tags
}

resource "aws_lb_target_group" "server" {
  name        = "${var.name_prefix}-cp-tg"
  port        = var.container_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server.arn
  }

  tags = local.tags
}

# Egress proxy: raw TCP passthrough (the client tunnels its own TLS through the
# CONNECT proxy), so a TCP listener with a TCP health check — the API's HTTP
# /health check does not apply to this port.
resource "aws_lb_target_group" "proxy" {
  name        = "${var.name_prefix}-cp-proxy"
  port        = var.egress_proxy_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "proxy" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.egress_proxy_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  tags = local.tags
}
