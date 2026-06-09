# SECRETS MANAGER
# Django Secret Key
resource "aws_secretsmanager_secret" "django_secret_key" {
  name        = "${var.project_name}-${var.environment}-django-secret-key"
  description = "Django SECRET_KEY for financial auth service"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-django-secret-key"
  }
}

resource "aws_secretsmanager_secret_version" "django_secret_key" {
  secret_id     = aws_secretsmanager_secret.django_secret_key.id
  secret_string = var.django_secret_key
}

# Database Password
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-${var.environment}-db-password"
  description             = "RDS PostgreSQL password for financial auth service"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# Database Username
resource "aws_secretsmanager_secret" "db_username" {
  name                    = "${var.project_name}-${var.environment}-db-username"
  description             = "RDS PostgreSQL username for financial auth service"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-username"
  }
}

resource "aws_secretsmanager_secret_version" "db_username" {
  secret_id     = aws_secretsmanager_secret.db_username.id
  secret_string = var.db_username
}

# Email Host User
resource "aws_secretsmanager_secret" "email_host_user" {
  name                    = "${var.project_name}-${var.environment}-email-host-user"
  description             = "Gmail address for sending emails"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-email-host-user"
  }
}

resource "aws_secretsmanager_secret_version" "email_host_user" {
  secret_id     = aws_secretsmanager_secret.email_host_user.id
  secret_string = var.email_host_user
}

# Email Host Password
resource "aws_secretsmanager_secret" "email_host_password" {
  name                    = "${var.project_name}-${var.environment}-email-host-password"
  description             = "Gmail app password for SMTP"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-email-host-password"
  }
}

resource "aws_secretsmanager_secret_version" "email_host_password" {
  secret_id     = aws_secretsmanager_secret.email_host_password.id
  secret_string = var.email_host_password
}

# LOCAL VALUES
# Collect all secret ARNs in one place
# Referenced by ECS task definitions

locals {
  secret_arns = {
    django_secret_key   = aws_secretsmanager_secret.django_secret_key.arn
    db_password         = aws_secretsmanager_secret.db_password.arn
    db_username         = aws_secretsmanager_secret.db_username.arn
    email_host_user     = aws_secretsmanager_secret.email_host_user.arn
    email_host_password = aws_secretsmanager_secret.email_host_password.arn
  }
}