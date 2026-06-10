# Financial Auth Service — AWS ECS Fargate Infrastructure

> **Terraform-based, production-grade containerized deployment of a Django REST API with Celery workers, PostgreSQL, and Redis on AWS.**

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Design](#system-design)
3. [Network Architecture](#network-architecture)
4. [Security Model](#security-model)
5. [Service Architecture](#service-architecture)
6. [Auto-Scaling Design](#auto-scaling-design)
7. [Technology Decisions](#technology-decisions)
8. [Deployment Flow](#deployment-flow)
9. [Cost Overview](#cost-overview)
10. [Operational Runbook](#operational-runbook)
11. [File Structure](#file-structure)

---

## Architecture Overview

This infrastructure deploys a financial authentication service (Django REST API) to AWS using a fully containerized, serverless compute model. The design prioritizes security, high availability, zero-downtime deployments, and cost efficiency.

### High-Level Diagram

```
                              INTERNET
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │   Application Load        │
                    │   Balancer (ALB)          │ ◄── Public Subnets, Port 80
                    │   Health checks: /api/    │     Later: 443 with ACM SSL
                    │   auth/health/            │
                    └────────────┬───────────────┘
                                 │
            ┌────────────────────┼────────────────────┐
            │                    │                    │
            ▼                    ▼                    ▼
     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
     │   Web 1     │     │   Web 2     │     │   Web N     │ ◄── ECS Fargate
     │  Django     │     │  Django     │     │  Django     │     Private Subnets
     │  Gunicorn   │     │  Gunicorn   │     │  Gunicorn   │     Port 8000
     │ :8000       │     │ :8000       │     │ :8000       │
     └──────┬──────┘     └──────┬──────┘     └──────┬──────┘
            │                    │                    │
            └────────────────────┼────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
 ┌──────────────┐      ┌──────────────┐        ┌──────────────┐
 │ Celery Worker│      │ Celery Beat  │        │    Flower    │
 │ (Background) │      │ (Scheduler)  │        │ (Monitoring) │
 │ 1-N tasks    │      │ Exactly 1    │        │ Internal only│
 └──────┬───────┘      └──────┬───────┘        └──────────────┘
        │                     │
        │                     │
        └──────────┬──────────┘
                   │
                   ▼
        ┌─────────────────────┐
        │   ElastiCache       │
        │   Redis 7           │ ◄── Celery Broker, Cache
        │   Port 6379         │     Private Subnets    │
        └─────────────────────┘
                   │
                   │ (DB queries)
                   ▼
        ┌─────────────────────┐
        │   RDS PostgreSQL    │
        │   15.8              │ ◄── User data, auth tokens, audit logs
        │                    │     Private Subnets, Encrypted
        │   Multi-AZ capable  │     Automated backups
        └─────────────────────┘
```

---

## System Design

### Design Principles

| Principle | Implementation |
|-----------|---------------|
 **Defense in Depth** | Multiple security layers: private subnets, security groups, IAM roles, Secrets Manager
 **Least Privilege** | Every component has only the permissions it strictly needs
 **High Availability** | Multi-AZ subnets, ALB across AZs, ECS service auto-healing
 **Zero-Downtime Deploy** | Rolling updates with circuit breaker rollback
 **Cost Optimization** | Fargate (no server management), smallest production-grade instances, log retention limits
 **Infrastructure as Code** | 100% Terraform — no manual console clicks for production resources

### Why This Architecture for a Financial Auth Service

Financial authentication services handle **credentials, JWT tokens, PII, and audit trails**. A single misconfiguration can expose user data or allow unauthorized access. This architecture makes direct database access **physically impossible** from the internet, encrypts all secrets at rest and in transit, and provides complete audit trails through CloudWatch logs and IAM access logs.

---

## Network Architecture

### VPC (10.0.0.0/16)

The entire system lives inside a single VPC with **65,536 IP addresses**. Nothing enters or leaves without explicit firewall rules.

| Tier | CIDR | AZ | Purpose |
|------|------|-----|---------|
| Public Subnet 1 | 10.0.1.0/24 | us-east-1a | ALB, NAT Gateway |
| Public Subnet 2 | 10.0.2.0/24 | us-east-1b | ALB (HA) |
| Private Subnet 1 | 10.0.3.0/24 | us-east-1a | ECS tasks, RDS, ElastiCache |
| Private Subnet 2 | 10.0.4.0/24 | us-east-1b | ECS tasks, RDS, ElastiCache (HA) |

### Public vs Private Subnets

**Public Subnets**
- Have a route to the **Internet Gateway (IGW)**
- Resources can receive inbound traffic from the internet
- Host only the **Application Load Balancer** and **NAT Gateway**
- ALB has public IP addresses

**Private Subnets**
- **No route to the Internet Gateway**
- Resources cannot be reached directly from the internet
- Host all application containers, the database, and Redis
- Outbound internet access only through **NAT Gateway** (one-way)

### Why Separate Public and Private?

A Django application containers should **never** be directly accessible from the internet. The only entry point is the ALB. If an attacker discovers the container's IP address, they cannot reach it because:
1. It has no public IP (private subnet)
2. Its security group only allows traffic from the ALB
3. Even within the VPC, the database security group only allows traffic from the ECS security group

This is **defense in depth** for a financial service.

### NAT Gateway

- Lives in the **public subnet** (needs internet access to work)
- Allows **outbound-only** traffic from private subnets
- The containers use this to:
  - Pull Docker images from ECR
  - Send emails via Gmail SMTP (port 587)
  - Call external payment APIs (if applicable)
- **Blocks all inbound traffic** from the internet
- Single NAT Gateway for cost savings (~$32/month). For true HA, use one per AZ.

---

## Security Model

### Security Group Architecture

Security groups act as **stateful firewalls** (virtual bouncers) for every resource.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ALB Security Group                           │
├─────────────────────────────────────────────────────────────────────┤
│ INGRESS:                                                             │
│   • Port 80 (HTTP)   ← 0.0.0.0/0 (Internet)                       │
│   • Port 443 (HTTPS) ← 0.0.0.0/0 (Ready for future SSL)             │
│ EGRESS:                                                              │
│   • All traffic → Anywhere (to reach ECS tasks)                      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Forwards traffic
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     ECS Tasks Security Group                        │
├─────────────────────────────────────────────────────────────────────┤
│ INGRESS:                                                             │
│   • Port 8000 ← ONLY from ALB Security Group                        │
│   • All ports ← Self (other ECS tasks: worker→web communication)   │
│ EGRESS:                                                              │
│   • All traffic → Anywhere (to reach RDS, Redis, SMTP, ECR)        │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Reads/Writes
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      RDS Security Group                             │
├─────────────────────────────────────────────────────────────────────┤
│ INGRESS:                                                             │
│   • Port 5432 ← ONLY from ECS Tasks Security Group                │
│ EGRESS:                                                              │
│   • All traffic → Anywhere                                         │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                   ElastiCache Security Group                        │
├─────────────────────────────────────────────────────────────────────┤
│ INGRESS:                                                             │
│   • Port 6379 ← ONLY from ECS Tasks Security Group                │
│ EGRESS:                                                              │
│   • All traffic → Anywhere                                         │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Security Rules

| Resource | Who Can Reach It | How |
|----------|-----------------|-----|
| ALB | Anyone on the internet | HTTP/HTTPS ports |
| Django Containers | Only the ALB | Port 8000, security group reference |
| PostgreSQL Database | Only ECS containers | Port 5432, security group reference |
| Redis | Only ECS containers | Port 6379, security group reference |
| Your laptop | Nothing directly | No bastion host, no public DB access |

### IAM Roles (Permission Boundaries)

Two distinct roles prevent privilege escalation:

**ECS Task Execution Role** (AWS-managed setup)
- Pulls Docker images from ECR
- Writes CloudWatch logs
- Reads secrets from AWS Secrets Manager
- Used **before** your code starts

**ECS Task Role** (Your application runtime)
- Writes CloudWatch logs (application logs)
- Used **while** the code is running
- If compromised, an attacker can only do what this role allows — they cannot read other secrets or access other AWS services unless explicitly permitted

### Secrets Management

**No secrets in code. No secrets in environment variables visible in the console.**

All sensitive values live in **AWS Secrets Manager**:

| Secret | Purpose | Rotation |
|--------|---------|----------|
| Django SECRET_KEY | Cryptographic signing (JWT, sessions) | Manual |
| DB Password | PostgreSQL master password | Manual |
| DB Username | PostgreSQL master username | Manual |
| Gmail App Password | SMTP authentication | Manual |
| Gmail Address | SMTP sender identity | Manual |

- Secrets are **encrypted at rest** with AWS KMS
- ECS pulls them at container startup and injects as environment variables
- **Never stored in Terraform state** as plaintext (marked `sensitive = true`)
- **Never committed to Git** (terraform.tfvars is gitignored)
- Recovery window: 7 days (prevents accidental deletion)

### Database Security

- **RDS is not publicly accessible** (`publicly_accessible = false`)
- **Encryption at rest** enabled (AES-256)
- **Automated backups** daily (1-day retention for Free Tier, 7+ recommended for production)
- **Deletion protection** enabled (prevents `terraform destroy` from accidentally deleting user data)
- **Final snapshot** taken before any deletion
- Enhanced monitoring logs every connection and slow query

---

## Service Architecture

### Four ECS Services

The monolithic Docker image contains all Django code, but we run **four distinct services** with different commands and scaling rules.

#### 1. Web Service (Django + Gunicorn)

```
Image: financial-auth-production:latest
Command: gunicorn core.wsgi:application --bind 0.0.0.0:8000 --workers 4
Min: 2 | Desired: 2 | Max: 6 (auto-scaling)
CPU: 512 (0.5 vCPU) | Memory: 1024 MB
```

- **Handles HTTP requests** from the ALB
- **Minimum 2 tasks** ensures zero downtime during deployments or crashes
- **Health checks** at `/api/auth/health/` every 30 seconds
- **Circuit breaker** rolls back failed deployments automatically
- **Rolling updates**: starts new tasks before stopping old ones (100%-200% deployment window)

#### 2. Celery Worker Service

```
Image: financial-auth-production:latest
Command: celery -A core worker --loglevel=info
Min: 1 | Desired: 1 | Max: 4 (auto-scaling)
CPU: 256 (0.25 vCPU) | Memory: 512 MB
```

- **Background task processor**
- Handles: email sending, token cleanup, audit log archiving
- **No ALB attachment** — does not accept HTTP requests
- Pulls tasks from Redis queue and executes them

#### 3. Celery Beat Service (Scheduler)

```
Image: financial-auth-production:latest
Command: celery -A core beat --loglevel=info
Count: Exactly 1 (never more, never less)
CPU: 256 | Memory: 512 MB
```

- **The heartbeat of scheduled tasks**
- Reads the `celery.py` `beat_schedule` (e.g., "clean expired tokens at 2 AM daily")
- **Critical rule: exactly 1 instance**
  - Two beat schedulers = every task runs twice
  - Duplicate emails, duplicate token cleanup, data corruption
- **Deployment max: 100%** — forces AWS to stop the old task before starting the new one

#### 4. Flower Service (Internal Monitoring)

```
Image: financial-auth-production:latest
Command: celery -A core flower --port=5555
Count: 1
CPU: 256 | Memory: 512 MB
```

- **Celery monitoring dashboard** on port 5555
- **Not exposed to the internet** (no ALB listener, no public DNS)
- Accessed via AWS Systems Manager Session Manager or VPN only
- Shows task queues, worker status, and scheduled task timing
- For a financial service, this data is sensitive and must remain internal

### Why Fargate (Not EC2)?

| Aspect | Fargate | EC2 Alternative |
|--------|---------|-----------------|
| Server management | None (AWS manages) | You manage OS patching, scaling, capacity |
| Billing | Per task CPU/memory | Per EC2 instance (hourly) |
| Scaling | Task-level, instant | Instance-level, slower |
| Security | Each task isolated | Shared kernel, larger blast radius |
| Cost at low traffic | Cheaper (pay per task) | Expensive (running 24/7 instances) |
| Best for | Variable/unknown traffic, small teams | Predictable high throughput, large teams |

For a financial auth startup or learning project, **Fargate eliminates operational toil** while maintaining production-grade isolation.

---

## Auto-Scaling Design

### Scale-Out Policy (Add Tasks When Busy)

```
CloudWatch Metric: CPUUtilization (Average across all tasks)
Threshold: >= 75%
Evaluation Periods: 2 consecutive minutes
Action: Add 1 task
Cooldown: 60 seconds (before scaling again)
Maximum: 6 web tasks, 4 worker tasks
```

**Why these numbers?**
- **75% threshold**: Auth services are latency-sensitive. Users won't tolerate slow login responses. We scale early.
- **2-minute evaluation**: Prevents reacting to brief spikes (e.g., a single heavy report)
- **60-second cooldown**: New tasks need ~30-45 seconds to boot and start receiving traffic. We don't add more before they're ready.
- **Add 1 task (not 10)**: Gradual, predictable scaling. Prevents overshooting and wasting money.

### Scale-In Policy (Remove Tasks When Quiet)

```
CloudWatch Metric: CPUUtilization (Average across all tasks)
Threshold: <= 30%
Evaluation Periods: 2 consecutive minutes
Action: Remove 1 task
Cooldown: 120 seconds (twice as long as scale-out)
Minimum: 2 web tasks, 1 worker task
```

**Why different cooldowns?**
- **Scale-out**: Aggressive. Traffic spikes are real; add capacity fast.
- **Scale-in**: Conservative. An extra idle task costs pennies. Accidentally dropping below minimum capacity during a traffic dip causes outages. The 2-minute cooldown prevents "thrashing" (constantly adding and removing tasks).

### Example Timeline

```
Time    Traffic     Web Tasks   Avg CPU     Action
─────────────────────────────────────────────────────
09:00   Light       2           15%         Steady
10:00   Morning     2           82%         Alarm (1st period)
10:01   Spike       2           85%         Alarm (2nd period) → Scale OUT to 3
10:02   Spike       3           55%         Cooldown active
10:04   Spike       3           78%         Scale OUT to 4
11:00   Lunch       4           25%         Alarm low (1st period)
11:01   Lunch       4           22%         Alarm low (2nd period) → Scale IN to 3
11:03   Lunch       3           18%         Cooldown active
11:05   Lunch       3           15%         Scale IN to 2 (minimum reached, stops)
```

### Lifecycle Ignore on Desired Count

Terraform sets `desired_count = 2` in the web service, but auto-scaling will change it to 3, 4, 5, etc. We added `lifecycle { ignore_changes = [desired_count] }` so Terraform doesn't fight the auto-scaler and reset tasks back to 2 on every apply.

---

## Technology Decisions

### Why RDS (Not Self-Managed PostgreSQL in Docker)?

For a financial auth service, **data integrity is non-negotiable**.

| Feature | RDS PostgreSQL | Self-Managed Docker |
|---------|---------------|---------------------|
| Automated backups | Daily + point-in-time recovery | Manual or none |
| Multi-AZ failover | Automatic (1-minute RTO) | Manual, hours |
| Patching | AWS manages | You manage |
| Encryption at rest | Built-in | You configure |
| Performance insights | Built-in | Third-party tools |
| Storage autoscaling | Yes (20GB → 100GB) | Manual resize |
| Cost | ~$25-50/month | Lower raw cost, but high operational cost |

**Decision**: Use RDS. The operational risk of losing user credentials or audit logs far outweighs the cost savings of self-hosting.

### Why ElastiCache (Not Self-Managed Redis in ECS)?

| Feature | ElastiCache Redis | Self-Managed Redis |
|---------|------------------|-------------------|
| Persistence | Snapshot + optional AOF | Must configure EFS for persistence |
| Failover | Automatic | Manual recovery |
| Network latency | VPC-optimized | Same, but more complex |
| Celery queue survival | Snapshots restore queue | Container restart = queue lost |
| Cost | ~$13-25/month | Lower, but fragile |

**Decision**: Use ElastiCache. If the Redis container crashes, your Celery task queue disappears. For auth services, that means password reset emails never send, account lockouts never expire, audit jobs never run. Managed Redis is the safer choice.

### Why ALB (Not Nginx in ECS)?

The `docker-compose.yml` uses Nginx as a reverse proxy inn development. In AWS(production), we replaced it with the **Application Load Balancer**.

| Feature | ALB | Nginx Container |
|---------|-----|-----------------|
| Cross-AZ load balancing | Built-in | Must configure manually |
| Health checks | Built-in with auto-removal | Must configure + monitor |
| SSL termination | Built-in (ACM integration) | Cert management in container |
| AWS-managed | Yes | You manage the container |
| Cost | ~$20/month + usage | EC2/Fargate task cost |

**Decision**: Use ALB. It's a managed, highly available Layer 7 load balancer designed specifically for ECS Fargate services.

### Why S3 + Native Locking for Terraform State?

| Feature | S3 + Native Locking | Local Files |
|---------|--------------------|--------------|
| Collaboration | Team can share state | Single developer only |
| Durability | 99.999999999% (11 9s) | Depends on your laptop backups |
| Encryption | SSE-S3 or KMS | None by default |
| Locking | Built-in S3 lock file | None (race condition risk) |
| CI/CD friendly | Yes | Must upload/download manually |

**Decision**: Use S3 remote state with native locking. This prevents two people (or a pipeline and a human) from running `terraform apply` simultaneously and corrupting the state.

---

## Deployment Flow

### Full Deployment Sequence

```
Developer Laptop
       │
       ▼
┌────────────────────┐
│  1. Edit Terraform │
│  2. terraform plan │
│  3. terraform apply│
└────────────────────┘
       │
       │ Creates infrastructure (VPC, ALB, RDS, etc.)
       │
       ▼
┌────────────────────┐
│  4. Build Docker   │
│  5. docker push    │
│     → ECR          │
└────────────────────┘
       │
       │ Image scanned for vulnerabilities
       │
       ▼
┌────────────────────┐
│  6. ECS pulls image│
│  7. Run migrations │
│     (one-off task) │
│  8. Services start │
└────────────────────┘
       │
       ▼
    LIVE API
```

### Zero-Downtime Deployment Mechanics

When you push a new Docker image and update the task definition:

1. ECS registers the new task definition (revision N+1)
2. ECS starts **new** tasks using the new image
3. ALB health checks must pass **2 consecutive times** before receiving traffic
4. Once healthy, ALB routes traffic to new tasks
5. ECS stops **old** tasks (draining connections first)
6. **Deployment circuit breaker** watches for failures:
   - If too many new tasks fail health checks → **automatically rollback** to the previous working revision
   - This prevents a bad deployment from staying live and serving errors

**Minimum healthy percent: 100%** — you never drop below your desired count during deployment. If desired = 2, at least 2 tasks are always serving traffic.

**Maximum percent: 200%** — during deployment, up to 4 tasks can run temporarily (2 old + 2 new). This is the engine of zero-downtime updates.

---

## Cost Overview

### Estimated Monthly Costs (us-east-1, Free Tier eligible where noted)

| Resource | Size | Monthly Cost |
|----------|------|-------------|
| **NAT Gateway** | 1x | ~$32.40 + data processing |
| **ALB** | 1x | ~$16.43 + LCU usage |
| **RDS PostgreSQL** | db.t3.micro, 20GB, Single-AZ | ~$13-15 (Free Tier: 750 hrs included) |
| **ElastiCache Redis** | cache.t3.micro, 1 node | ~$12-13 (not Free Tier) |
| **Fargate Web (2 tasks)** | 512 CPU, 1GB RAM | ~$29 |
| **Fargate Worker (1 task)** | 256 CPU, 512MB RAM | ~$7 |
| **Fargate Beat (1 task)** | 256 CPU, 512MB RAM | ~$7 |
| **Fargate Flower (1 task)** | 256 CPU, 512MB RAM | ~$7 |
| **Secrets Manager** | 5 secrets | ~$2.00 |
| **CloudWatch Logs** | ~1GB/day, 30-day retention | ~$1-2 |
| **S3** | Terraform state (~1MB) | <$0.01 |
| **Data Transfer** | ECR pull, NAT Gateway, ALB | ~$5-10 |
| **TOTAL** | | **~$120-140/month** |

### Cost Optimization Notes

- **NAT Gateway is the biggest fixed cost.** If you switch to a VPC with public subnets only (not recommended for financial services), you eliminate the $32/month NAT cost.
- **Single-AZ RDS saves ~$25/month** over Multi-AZ. For a production financial service, Multi-AZ is strongly recommended once you have paying users.
- **Fargate Spot** can save up to 70% on compute costs for non-critical workloads (not suitable for beat scheduler, but viable for workers).
- **Right-size after measuring**: Start with these sizes, monitor CloudWatch CPU/memory metrics for 2 weeks, then adjust in `terraform.tfvars`.

---

## Operational Runbook

### Viewing Logs

```bash
# Web service logs
aws logs tail /ecs/financial-auth-production-web --follow

# Worker logs
aws logs tail /ecs/financial-auth-production-worker --follow

# Beat scheduler logs
aws logs tail /ecs/financial-auth-production-beat --follow

# Search logs for errors
aws logs filter-log-events \
  --log-group-name /ecs/financial-auth-production-web \
  --filter-pattern 'ERROR'
```

### Debugging a Running Container (ECS Exec)

```bash
# Get a shell inside a running web container
aws ecs execute-command \
  --cluster financial-auth-production \
  --task <TASK_ID> \
  --container web \
  --interactive \
  --command "/bin/sh"

# Inside the container:
python manage.py shell
python manage.py dbshell
env | grep DB
```

### Running One-Off Management Commands

```bash
# Database migrations (after schema changes)
aws ecs run-task \
  --cluster financial-auth-production \
  --task-definition <WEB_TASK_DEF_ARN> \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_1>,<SUBNET_2>],securityGroups=[<ECS_SG>],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides": [{"name": "web", "command": ["python", "manage.py", "migrate"]}]}'

# Create a superuser
aws ecs run-task \
  --cluster financial-auth-production \
  --task-definition <WEB_TASK_DEF_ARN> \
  --launch-type FARGATE \
  --network-configuration "..." \
  --overrides '{"containerOverrides": [{"name": "web", "command": ["python", "manage.py", "createsuperuser"]}]}'
```

### Checking Service Health

```bash
# Service status
aws ecs describe-services \
  --cluster financial-auth-production \
  --services financial-auth-production-web

# Running tasks
aws ecs list-tasks --cluster financial-auth-production --desired-status RUNNING

# ALB target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>
```

### Scaling Manually (Emergency)

```bash
# Force web service to 4 tasks (bypasses auto-scaling temporarily)
aws ecs update-service \
  --cluster financial-auth-production \
  --service financial-auth-production-web \
  --desired-count 4
```

### Destroying Everything (Cost Stop)

```bash
# In terraform/ directory
terraform destroy

# Delete remaining manual resources
aws s3 rm s3://financial-auth-terraform-state-209479305304 --recursive
aws s3api delete-bucket --bucket financial-auth-terraform-state-209479305304
aws dynamodb delete-table --table-name financial-auth-terraform-locks
```

---

## File Structure

```
terraform/
├── main.tf                    # Provider, backend (S3), AWS region, default tags
├── variables.tf               # All input variables (42+ variables, typed, validated)
├── terraform.tfvars           # The values (gitignored, contains secrets)
├── terraform.tfvars.example   # Template for new environments
├── .gitignore                 # Protects tfvars and state files
│
├── vpc.tf                     # VPC, subnets, IGW, NAT, Elastic IP, route tables
├── security_groups.tf         # 4 security groups + 12 ingress/egress rules
├── iam.tf                     # 4 IAM roles, 2 policy attachments, 3 inline policies
├── ecr.tf                     # Container registry + lifecycle policy
├── secrets.tf                 # 5 AWS Secrets Manager secrets + versions
├── rds.tf                     # Subnet group, parameter group, PostgreSQL instance, monitoring role
├── elasticache.tf             # Subnet group, Redis cluster, log group
├── alb.tf                     # ALB, target group, HTTP listener
├── ecs_cluster.tf             # ECS cluster + 4 CloudWatch log groups
├── ecs_web.tf                 # Django task definition + ECS service (ALB-attached)
├── ecs_worker.tf              # Celery worker task definition + service
├── ecs_beat.tf                # Celery beat task definition + service (singleton)
├── ecs_flower.tf              # Flower task definition + service (internal-only)
├── autoscaling.tf             # 2 auto-scaling targets, 4 CloudWatch alarms, 4 scaling policies
└── outputs.tf                 # ALB URL, endpoints, ARNs for operational use
```

---

## API Endpoint Reference

After deployment, your API is accessible at:

```
http://financial-auth-production-alb-717358561.us-east-1.elb.amazonaws.com
```

### Health Check
```bash
curl http://<ALB_URL>/api/auth/health/
# Response: {"status":"healthy","services":{"database":"connected","redis":"connected"}}
```

### Registration
```bash
curl -X POST http://<ALB_URL>/api/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "StrongPass123!",
    "password_confirm": "StrongPass123!",
    "first_name": "Jane",
    "last_name": "Doe"
  }'
```

### Login
```bash
curl -X POST http://<ALB_URL>/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "StrongPass123!"
  }'
# Response: {"access":"<JWT_TOKEN>","refresh":"<REFRESH_TOKEN>"}
```

---

## Future Enhancements

| Enhancement | Terraform File | Effort |
|-------------|--------------|--------|
 **HTTPS + Custom Domain** | Add ACM certificate + Route 53 record + ALB 443 listener | 30 min |
 **Database Multi-AZ** | Change `multi_az = true` in `rds.tf` | 1 min |
 **Blue/Green Deployments** | Add ECS deployment controller `CODE_DEPLOY` | 2-3 hours |
 **WAF (Web Application Firewall)** | Add `aws_wafv2_web_acl` associated with ALB | 1 hour |
 **CloudFront CDN** | Add CloudFront distribution in front of ALB | 1 hour |
 **Container Insights + X-Ray** | Enable AWS Distro for OpenTelemetry | 2 hours |
 **Secrets Rotation** | Enable AWS Secrets Manager rotation for DB password | 1 hour |
 **CI/CD Pipeline** | GitHub Actions → ECR push → ECS deployment | 2-3 hours |
 **VPC Flow Logs** | Enable `aws_flow_log` for network traffic auditing | 30 min |

---

## License

This infrastructure code is provided as-is for educational and production use. Review all security settings and costs before deploying to a production environment handling real financial data. Ensure compliance with PCI-DSS, SOC 2, or other applicable regulatory frameworks before processing live payment or identity data.
