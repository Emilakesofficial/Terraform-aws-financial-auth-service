# ECS CLUSTER

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name   = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment} - cluster"
  }
}

# CloudWatch Log Groups for ECS services
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.project_name}-${var.environment}-web"
  retention_in_days = var.logs_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-web-logs"
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project_name}-${var.environment}-worker"
  retention_in_days = var.logs_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-logs"
  }
}

resource "aws_cloudwatch_log_group" "beat" {
  name              = "/ecs/${var.project_name}-${var.environment}-beat"
  retention_in_days = var.logs_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-beat-logs"
  }
}

resource "aws_cloudwatch_log_group" "flower" {
  name              = "/ecs/${var.project_name}-${var.environment}-flower"
  retention_in_days = var.logs_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-flower-logs"
  }
}