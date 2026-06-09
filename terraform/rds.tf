locals {
  rds_name_prefix = replace("${var.project_name}-${var.environment}", "_", "-")
}

# RDS 
# DB Subnet Group - tell RDS which subnets it can use
resource "aws_db_subnet_group" "main" {
  name        = "${local.rds_name_prefix}-db-subnet-group"
  description = "Subnet group for RDS PostgreSQL"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# DB Parameter Group - PostgreSQL configuration
resource "aws_db_parameter_group" "main" {
  name        = "${local.rds_name_prefix}-db-params"
  family      = "postgres15"
  description = "Parameter group for financial auth PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_checkpoints"
    value = "1"
  }

  tags = {
    Name = "${local.rds_name_prefix}-db-params"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier = "${local.rds_name_prefix}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = "15.8"
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  # Configuration
  parameter_group_name = aws_db_parameter_group.main.name

  # Backups
  backup_retention_period  = var.db_backup_retention_days
  backup_window            = "03:00-04:00"
  maintenance_window       = "Mon:04:00-Mon:05:00"
  delete_automated_backups = false

  # High availability
  multi_az = false

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Updates
  auto_minor_version_upgrade = true
  apply_immediately          = false

  # Protection
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.rds_name_prefix}-final-snapshot"

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}

# CloudWatch Log Group for RDS logs
resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/instance/${var.project_name}-${var.environment}-postgres/postgresql"
  retention_in_days = var.logs_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-logs"
  }
}