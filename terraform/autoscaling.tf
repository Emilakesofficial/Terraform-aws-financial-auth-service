# AUTO SCALING TARGET — WEB SERVICE

resource "aws_appautoscaling_target" "web" {
  max_capacity       = var.web_max_count
  min_capacity       = var.web_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CLOUDWATCH ALARMS — WEB CPU
# Alarm: when CPU is HIGH → Scale OUT (add tasks)
resource "aws_cloudwatch_metric_alarm" "web_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-web-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.web_cpu_scale_out_threshold
  alarm_description   = "Scale out web service when CPU >= ${var.web_cpu_scale_out_threshold}%"
  alarm_actions       = [aws_appautoscaling_policy.web_scale_up.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.web.name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-web-cpu-high"
  }
}

# Alarm: CPU is LOW → Scale IN (remove tasks)
resource "aws_cloudwatch_metric_alarm" "web_cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-web-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.web_cpu_scale_in_threshold
  alarm_description   = "Scale in web service when CPU <= ${var.web_cpu_scale_in_threshold}%"
  alarm_actions       = [aws_appautoscaling_policy.web_scale_down.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.web.name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-web-cpu-low"
  }
}

# SCALING POLICIES — WEB
# Scale OUT: Add 1 task when alarm fires
resource "aws_appautoscaling_policy" "web_scale_up" {
  name               = "${var.project_name}-${var.environment}-web-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_out_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

# Scale IN: Remove 1 task when alarm fires
resource "aws_appautoscaling_policy" "web_scale_down" {
  name               = "${var.project_name}-${var.environment}-web-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_in_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# AUTO SCALING TARGET — WORKER SERVICE
resource "aws_appautoscaling_target" "worker" {
  max_capacity       = var.worker_max_count
  min_capacity       = var.worker_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CLOUDWATCH ALARMS — WORKER CPU
resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-worker-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.web_cpu_scale_out_threshold
  alarm_description   = "Scale out worker service when CPU >= ${var.web_cpu_scale_out_threshold}%"
  alarm_actions       = [aws_appautoscaling_policy.worker_scale_up.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.worker.name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-worker-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.web_cpu_scale_in_threshold
  alarm_actions       = [aws_appautoscaling_policy.worker_scale_down.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.worker.name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-cpu-low"
  }
}

# SCALING POLICIES — WORKER
resource "aws_appautoscaling_policy" "worker_scale_up" {
  name               = "${var.project_name}-${var.environment}-worker-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_out_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "worker_scale_down" {
  name               = "${var.project_name}-${var.environment}-worker-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_in_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}