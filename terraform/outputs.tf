# OUTPUTS
# Application Load Balancer URL - # API endpoint
output "alb_url" {
  description = "Application Load Balancer DNS name (API endpoint)"
  value       = aws_lb.main.dns_name
}

# ECS Repository URL - Docker images location
output "ecr_repository_url" {
  description = "URL of the ECR repository for Docker images"
  value       = aws_ecr_repository.app.repository_url
}

# RDS Endpoint - PostgreSQL database connection
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (internal only, not publicly accessible)"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

# ElasticCache Endpoint - Redis connection
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint (internal only)"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
  sensitive   = true
}

# ECS Cluster Name
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

# ECS Web Service Name
output "ecs_web_service" {
  description = "Name of the ECS web service"
  value       = aws_ecs_service.web.name
}

# CloudWatch Log Groups - where to find logs
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for viewing container logs"
  value = {
    web    = aws_cloudwatch_log_group.web.name
    worker = aws_cloudwatch_log_group.worker.name
    beat   = aws_cloudwatch_log_group.beat.name
    flower = aws_cloudwatch_log_group.flower.name
  }
}

# VPC ID
output "vpc_id" {
  description = "VPC ID for references"
  value       = aws_vpc.main.id
}

# Security Group IDs
output "security_groups" {
  description = "Security group IDs for references"
  value = {
    alb   = aws_security_group.alb.id
    ecs   = aws_security_group.ecs_tasks.id
    rds   = aws_security_group.rds.id
    redis = aws_security_group.redis.id
  }
}