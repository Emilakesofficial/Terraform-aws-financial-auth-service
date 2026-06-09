# ECS CELERY BEAT TASK DEFINITION

resource "aws_ecs_task_definition" "beat" {
  family                   = "${var.project_name}-${var.environment}-beat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.beat_cpu
  memory                   = var.beat_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "beat"
      image     = "${aws_ecr_repository.app.repository_url}:${var.ecr_image_tag}"
      essential = true

      cpu    = var.beat_cpu
      memory = var.beat_memory

      command = [
        "celery",
        "-A", "core",
        "beat",
        "--loglevel=info"
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "DJANGO_SETTINGS_MODULE", value = var.django_settings_module },
        { name = "DEBUG", value = "False" },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.main.cache_nodes[0].address },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
        { name = "REDIS_DB", value = "0" },
        { name = "EMAIL_BACKEND", value = var.email_backend },
        { name = "EMAIL_HOST", value = var.email_host },
        { name = "EMAIL_PORT", value = tostring(var.email_port) },
        { name = "EMAIL_USE_TLS", value = "True" },
        { name = "DEFAULT_FROM_EMAIL", value = var.default_from_email },
        { name = "JWT_ACCESS_TOKEN_LIFETIME", value = tostring(var.jwt_access_token_lifetime) },
        { name = "JWT_REFRESH_TOKEN_LIFETIME", value = tostring(var.jwt_refresh_token_lifetime) },
        { name = "MAX_LOGIN_ATTEMPTS", value = tostring(var.max_login_attempts) },
        { name = "LOGIN_LOCKOUT_DURATION", value = tostring(var.login_lockout_duration) }
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "DB_USER", valueFrom = aws_secretsmanager_secret.db_username.arn },
        { name = "SECRET_KEY", valueFrom = aws_secretsmanager_secret.django_secret_key.arn },
        { name = "EMAIL_HOST_PASSWORD", valueFrom = aws_secretsmanager_secret.email_host_password.arn },
        { name = "EMAIL_HOST_USER", valueFrom = aws_secretsmanager_secret.email_host_user.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.beat.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "beat"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-beat-task"
  }
}

# ECS CELERY BEAT SERVICE

resource "aws_ecs_service" "beat" {
  name            = "${var.project_name}-${var.environment}-beat"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.beat.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Prevents two beat tasks from running simultaneously during deployment
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  depends_on = [aws_db_instance.main, aws_elasticache_cluster.main]

  propagate_tags = "SERVICE"

  tags = {
    Name = "${var.project_name}-${var.environment}-beat-service"
  }
}