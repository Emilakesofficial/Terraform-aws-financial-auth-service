# ECS WEB TASK DEFINITION
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project_name}-${var.environment}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.app.repository_url}:${var.ecr_image_tag}"
      essential = true

      cpu    = var.web_cpu
      memory = var.web_memory

      portMappings = [
        {
          containerPort = var.web_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "DJANGO_SETTINGS_MODULE", value = var.django_settings_module },
        { name = "DEBUG", value = "False" },
        { name = "ALLOWED_HOSTS", value = var.django_allowed_hosts },
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
        { name = "CORS_ALLOWED_ORIGINS", value = var.cors_allowed_origins },
        { name = "JWT_ACCESS_TOKEN_LIFETIME", value = tostring(var.jwt_access_token_lifetime) },
        { name = "JWT_REFRESH_TOKEN_LIFETIME", value = tostring(var.jwt_refresh_token_lifetime) },
        { name = "MAX_LOGIN_ATTEMPTS", value = tostring(var.max_login_attempts) },
        { name = "LOGIN_LOCKOUT_DURATION", value = tostring(var.login_lockout_duration) },
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "DB_USER", valueFrom = aws_secretsmanager_secret.db_username.arn },
        { name = "SECRET_KEY", valueFrom = aws_secretsmanager_secret.django_secret_key.arn },
        { name = "EMAIL_HOST_PASSWORD", valueFrom = aws_secretsmanager_secret.email_host_password.arn },
        { name = "EMAIL_HOST_USER", valueFrom = aws_secretsmanager_secret.email_host_user.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-web-task"
  }
}

# ECS WEB SERVICE
resource "aws_ecs_service" "web" {
  name            = "${var.project_name}-${var.environment}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = var.web_container_port
  }

  health_check_grace_period_seconds = 120

  depends_on = [aws_lb_listener.http]

  propagate_tags = "SERVICE"

  tags = {
    Name = "${var.project_name}-${var.environment}-web-service"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}