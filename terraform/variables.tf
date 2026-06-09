# GENERAL VARIABLES

variable "aws_region" {
  description = "AWS region where all resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used for naming all resources"
  type        = string
  default     = "financial-auth"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production"
  }
}

# NETWORK VARIABLES

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "availability zones to deploy resources"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# DATABASE VARIABLES

variable "db_name" {
  description = "Name of the PostgreSQL Database"
  type        = string
  default     = "financial_auth_db"
}

variable "db_username" {
  description = "Master username for the Database"
  type        = string
  default     = "financial_auth_user"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the Database"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "Database password must be at least 16 characters."
  }
}

variable "db_port" {
  description = "Port for PostgreSQL Database"
  type        = number
  default     = 5432
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage allocated to RDS in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum storage RDS can autoscale to in GB"
  type        = number
  default     = 100
}

variable "db_backup_retention_days" {
  description = "How many days to retain automated backups"
  type        = number
  default     = 1
}

# REDIS (ELASTICACHE)

variable "redis_node_type" {
  description = "ElasticCache node instance type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes in the cluster"
  type        = number
  default     = 1
}

variable "redis_port" {
  description = "Port Redis listens on"
  type        = number
  default     = 6379
}

# ECR (CONTAINER REGISTRY)

variable "ecr_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "ecr_retention_count" {
  description = "Number of images to retain in ECR"
  type        = number
  default     = 10
}

# ECS GENERAL

variable "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution IAM role"
  type        = string
  default     = "financial-auth-ecs-execution-role"
}

variable "ecs_task_role_name" {
  description = "Name of the ECS task IAM role"
  type        = string
  default     = "financial-auth-ecs-task-role"
}

variable "logs_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
}

# ECS WEB SERVICE (DJANGO)

variable "web_cpu" {
  description = "CPU units for web task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "web_memory" {
  description = "Memory in MB for wen task"
  type        = number
  default     = 1024
}

variable "web_desired_count" {
  description = "Desired number of web tasks"
  type        = number
  default     = 2
}

variable "web_min_count" {
  description = "Minimum number of web tasks"
  type        = number
  default     = 2
}

variable "web_max_count" {
  description = "Maximum number of web tasks"
  type        = number
  default     = 6
}

variable "web_container_port" {
  description = "Port the Django app listens on"
  type        = number
  default     = 8000
}

# ECS CELERY WORKER

variable "worker_cpu" {
  description = "CPU units for celery worker task"
  type        = number
  default     = 250
}

variable "worker_memory" {
  description = "Memory in MB for celery worker task"
  type        = number
  default     = 512
}

variable "worker_desired_count" {
  description = "Desired number of celery worker tasks"
  type        = number
  default     = 1
}

variable "worker_min_count" {
  description = "Minimum number of celery worker tasks"
  type        = number
  default     = 1
}

variable "worker_max_count" {
  description = "Maximum number of celery worker tasks"
  type        = number
  default     = 4
}

# ECS CELERY BEAT

variable "beat_cpu" {
  description = "CPU units for celery beat task"
  type        = number
  default     = 256
}

variable "beat_memory" {
  description = "Memory in MB for celery beat task"
  type        = number
  default     = 512
}

# ECS FLOWER

variable "flower_cpu" {
  description = "CPU units for flower task"
  type        = number
  default     = 256
}

variable "flower_memory" {
  description = "Memory in MB for flower task"
  type        = number
  default     = 512
}

variable "flower_port" {
  description = "Port flower listens on"
  type        = number
  default     = 5555
}

# AUTO SCALING

variable "web_cpu_scale_out_threshold" {
  description = "CPU % to trigger scaling out (add tasks)"
  type        = number
  default     = 75
}

variable "web_cpu_scale_in_threshold" {
  description = "CPU % to trigger scaling in (remove tasks)"
  type        = number
  default     = 30
}

variable "scale_out_cooldown" {
  description = "Seconds to wait after scaling out before scaling again"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds to wait after scaling in before scaling again"
  type        = number
  default     = 120
}

# APPLICATION VARIABLES

variable "django_secret_key" {
  description = "Django SECRET_KEY"
  type        = string
  sensitive   = true
}

variable "django_allowed_hosts" {
  description = "Django ALLOWED_HOSTS value"
  type        = string
  default     = "*"
}

variable "django_settings_module" {
  description = "Django settings module to use"
  type        = string
  default     = "core.settings.production"
}

variable "cors_allowed_origins" {
  description = "Allowed CORS origins"
  type        = string
  default     = ""
}

variable "email_backend" {
  description = "Django email backend"
  type        = string
  default     = "django.core.mail.backends.smtp.EmailBackend"
}

variable "email_port" {
  description = "Port email SMTP listens to"
  type        = number
  default     = 587
}

variable "email_use_tls" {
  description = "Does email use TLS"
  type        = bool
  default     = true
}

variable "email_host" {
  description = "SMTP Email host"
  type        = string
  default     = "smtp.gmail.com"
}
variable "email_host_user" {
  description = "Gmail address for sending emails"
  type        = string
  sensitive   = true
}

variable "email_host_password" {
  description = "Gmail app password for SMTP"
  type        = string
  sensitive   = true
}

variable "default_from_email" {
  description = "The default FROM email address"
  type        = string
  sensitive   = true
}

variable "jwt_access_token_lifetime" {
  description = "JWT access token lifetime in minutes"
  type        = number
  default     = 30
}

variable "jwt_refresh_token_lifetime" {
  description = "JWT refresh token lifetime in days"
  type        = number
  default     = 7
}

variable "max_login_attempts" {
  description = "Maximum failed login attempts before lockout"
  type        = number
  default     = 5
}

variable "login_lockout_duration" {
  description = "Login lockout duration in minutes"
  type        = number
  default     = 10
}