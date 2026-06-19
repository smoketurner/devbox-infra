resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_ecs_task_definition" "server" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # arm64 (Graviton) Fargate — cheaper, and consistent with the pool.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "devbox-server"
    image     = local.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "DATABASE_URL", value = local.database_url },
      { name = "PORT", value = tostring(var.container_port) },
      { name = "AWS_REGION", value = local.aws_region },
      { name = "POOL_ID", value = var.pool_id },
      { name = "POOL_TARGET_WARM_SIZE", value = tostring(var.target_warm_pool_size) },
      { name = "RUST_LOG", value = "info,devbox_server=info" },
      # API authentication (the dashboard is also gated by Vouch OIDC at the ALB).
      { name = "AUTH_ENABLED", value = "true" },
      { name = "AUTH_OIDC_ISSUER", value = var.oidc_issuer },
      { name = "AUTH_OIDC_JWKS_URI", value = var.oidc_jwks_uri },
      { name = "AUTH_OIDC_AUDIENCE", value = var.oidc_client_id },
      { name = "AUTH_PRINCIPAL_CLAIM", value = var.auth_principal_claim },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.server.name
        "awslogs-region"        = local.aws_region
        "awslogs-stream-prefix" = "devbox-server"
      }
    }
  }])

  tags = local.tags
}

resource "aws_ecs_service" "server" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.server.arn
    container_name   = "devbox-server"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Roll back automatically if a new deployment fails to stabilize.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.https]

  # CI deploys immutable, sha-pinned task-definition revisions (see
  # .github/workflows/deploy.yml); Terraform sets only the initial revision.
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = local.tags
}
