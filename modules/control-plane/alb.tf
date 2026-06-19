# Internal ALB fronting the control plane. The dashboard is gated by Vouch OIDC;
# the API and health path bypass OIDC (programmatic clients / health probes) and
# are protected by network isolation (internal ALB) until app-level API auth
# lands. The ALB lives in egress private subnets so it can reach the Vouch token
# endpoint via NAT for the OIDC code exchange.

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Internal ALB for the devbox control plane"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from allowed networks"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP (redirected to HTTPS) from allowed networks"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "ALB egress to targets and the OIDC provider"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "service" {
  name        = "${local.name_prefix}-service"
  description = "Devbox control plane Fargate tasks"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-service" })
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "service_https" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound HTTPS (AWS APIs, ECR, DSQL token signing)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "service_dsql" {
  security_group_id = aws_security_group.service.id
  description       = "Outbound to Aurora DSQL (PostgreSQL wire protocol)"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-cp"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "server" {
  name        = "${var.name_prefix}-cp-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  # Default: require a Vouch OIDC session (protects the dashboard).
  default_action {
    type  = "authenticate-oidc"
    order = 1

    authenticate_oidc {
      issuer                     = var.oidc_issuer
      authorization_endpoint     = var.oidc_authorization_endpoint
      token_endpoint             = var.oidc_token_endpoint
      user_info_endpoint         = var.oidc_user_info_endpoint
      client_id                  = var.oidc_client_id
      client_secret              = var.oidc_client_secret
      scope                      = var.oidc_scope
      on_unauthenticated_request = "authenticate"
    }
  }

  default_action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.server.arn
  }

  tags = local.tags
}

# Programmatic + health paths bypass OIDC (the CLI/agents can't do the
# interactive browser flow). Safe because the ALB is internal.
resource "aws_lb_listener_rule" "api_bypass" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/health"]
    }
  }

  tags = local.tags
}
