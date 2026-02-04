# Terraform Infrastructure Documentation

> **Last Updated:** February 4, 2026  
> **AWS Account:** 731099197523  
> **Primary Region:** ap-southeast-1 (Singapore)

## Table of Contents

1. [Overview](#overview)
2. [Environments](#environments)
3. [Architecture Patterns](#architecture-patterns)
4. [AWS Services Used](#aws-services-used)
5. [Network Architecture](#network-architecture)
6. [Security & IAM](#security--iam)
7. [Cost Control](#cost-control)
8. [State Management](#state-management)
9. [Deployment Strategy](#deployment-strategy)
10. [Operational Procedures](#operational-procedures)
11. [Important Design Decisions](#important-design-decisions)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This project uses Terraform to manage infrastructure across three environments:
- **Bootstrap**: One-time setup for CI/CD
- **DEV**: Cost-optimized development environment
- **PROD**: Multi-AZ production environment

### Repository Structure

```
infra/terraform/
├── envs/
│   ├── bootstrap/    # GitHub OIDC + CI/CD IAM roles
│   ├── dev/         # Development environment
│   └── prod/        # Production environment
└── modules/         # Reusable infrastructure modules
    ├── alb/
    ├── asg/
    ├── bastion/
    ├── cloudfront-static-site/
    ├── cloudwatch/
    ├── cognito/
    ├── deployments-bucket/
    ├── ec2/
    ├── iam/
    ├── rds/
    ├── route53/
    ├── security-groups/
    ├── security-groups-prod/
    └── vpc/
```

---

## Environments

### Bootstrap Environment

**Location:** `infra/terraform/envs/bootstrap/`  
**Purpose:** One-time setup for CI/CD pipeline

**What it creates:**
- GitHub OIDC provider reference (already exists in AWS)
- IAM role: `github-actions-deploy-role`
- Permissions for GitHub Actions to deploy to both DEV and PROD

**State:** Local (`terraform.tfstate` in directory)

**Configuration:**
```hcl
project                = "d2-ride-booking-new"
aws_region             = "ap-southeast-1"
terraform_state_bucket = "terraform-731099197523"
github_repo            = "fikriimujahid/d2-ride-booking-new"
```

**Deploy Once:**
```bash
cd infra/terraform/envs/bootstrap
terraform init
terraform plan
terraform apply
```

---

### DEV Environment

**Location:** `infra/terraform/envs/dev/`  
**VPC CIDR:** 10.20.0.0/16  
**Availability Zones:** ap-southeast-1a (primary), ap-southeast-1b (secondary)  
**State:** Local

#### Philosophy
**Cost-Optimized Development**
- Most services are **toggleable** via feature flags
- Single EC2 instance runs multiple services (consolidated pattern)
- Minimal infrastructure by default
- **Target Monthly Cost:** $0-15 (most toggles disabled)

#### Current Configuration (terraform.tfvars)

```hcl
# Core Settings
environment  = "dev"
project_name = "d2-ride-booking"
domain_name  = "fikri.dev"

# Network
vpc_cidr                      = "10.20.0.0/16"
public_subnet_cidr            = "10.20.1.0/24"
public_subnet_cidr_secondary  = "10.20.2.0/24"
private_subnet_cidr           = "10.20.11.0/24"
private_subnet_cidr_secondary = "10.20.12.0/24"

# Cost Control (ALL DISABLED by default)
enable_rds               = false  # ~$15/month
enable_nat_gateway       = false  # ~$32/month
enable_alb               = false  # ~$16/month
enable_ssm_vpc_endpoints = false  # ~$7/month
enable_ec2_backend       = false  # ~$7/month
enable_web_driver        = false  # ~$7/month
enable_web_admin         = false  # ~$0.50/month
enable_web_passenger     = false  # ~$0.50/month
enable_bastion           = false

# Instance Sizing
backend_instance_type    = "t3.micro"
backend_root_volume_size = 16

# Database (when enabled)
rds_instance_class    = "db.t3.micro"
rds_allocated_storage = 20

# Monitoring
enable_alarms      = true
log_retention_days = 7
alarm_email        = ""
```

#### DEV Architecture

```
┌─────────────────────────────────────────────────┐
│ Internet                                         │
└─────────────┬───────────────────────────────────┘
              │
              ↓ (Optional)
    ┌─────────────────┐
    │  ALB (optional) │ ← Enable with enable_alb=true
    │  80 → 443       │
    │  443 (HTTPS)    │
    └────────┬────────┘
             │
             ↓
   ┌─────────────────────────┐
   │ VPC 10.20.0.0/16        │
   │                          │
   │ ┌──────────────────────┐│
   │ │ Public Subnet (1a)   ││
   │ │ 10.20.1.0/24         ││
   │ │ - Internet Gateway   ││
   │ │ - (Optional NAT)     ││
   │ └──────────────────────┘│
   │                          │
   │ ┌──────────────────────┐│
   │ │ Private Subnet (1a)  ││
   │ │ 10.20.11.0/24        ││
   │ │                      ││
   │ │ ┌──────────────────┐ ││
   │ │ │ EC2 (Consolidated│ ││ ← Single instance
   │ │ │ app-host)        │ ││   runs both services
   │ │ │                  │ ││
   │ │ │ :3000 backend-api│ ││
   │ │ │ :3001 web-driver │ ││
   │ │ └──────────────────┘ ││
   │ │         ↓            ││
   │ │ ┌──────────────────┐ ││
   │ │ │ RDS MySQL        │ ││ ← Optional
   │ │ │ (Single-AZ)      │ ││
   │ │ └──────────────────┘ ││
   │ └──────────────────────┘│
   └─────────────────────────┘

   Static Sites (separate):
   CloudFront → Private S3
   - admin.d2.fikri.dev
   - passenger.d2.fikri.dev
```

---

### PROD Environment

**Location:** `infra/terraform/envs/prod/`  
**VPC CIDR:** 10.30.0.0/16  
**Availability Zones:** ap-southeast-1a, ap-southeast-1b (Multi-AZ)  
**State:** Local

#### Philosophy
**Resilience-Optimized Production**
- Multi-AZ deployment across 2 availability zones
- Separate Auto Scaling Groups per service
- Always-on ALB for high availability
- Multi-AZ RDS with automatic failover
- **Target Monthly Cost:** $100-150

#### Current Configuration (terraform.tfvars)

```hcl
environment  = "prod"
project_name = "d2-ride-booking"
domain_name  = "fikri.dev"

# Network (Multi-AZ)
vpc_cidr = "10.30.0.0/16"
availability_zones = ["ap-southeast-1a", "ap-southeast-1b"]

public_subnet_cidrs      = ["10.30.1.0/24", "10.30.2.0/24"]
private_app_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]
private_db_subnet_cidrs  = ["10.30.21.0/24", "10.30.22.0/24"]

# Core Services (ENABLED)
enable_rds = true
enable_ssm_vpc_endpoints = false  # Using NAT Gateway instead
enable_bastion = true

# Auto Scaling Groups
backend_asg_min     = 1
backend_asg_desired = 1
backend_asg_max     = 3

driver_asg_min      = 1
driver_asg_desired  = 1
driver_asg_max      = 3

# Database
rds_instance_class        = "db.t3.micro"
rds_allocated_storage     = 30
rds_backup_retention_days = 7

# Monitoring
enable_alarms      = false  # TODO: Enable before go-live
alarm_email        = ""
log_retention_days = 90

# Security Hardening
cognito_password_min_length = 12

# CI/CD
enable_github_actions_deploy_role = true
github_oidc_provider_arn = "arn:aws:iam::731099197523:oidc-provider/token.actions.githubusercontent.com"
```

#### PROD Architecture

```
┌──────────────────────────────────────────────────────┐
│ Internet                                              │
└───────────────────┬──────────────────────────────────┘
                    │
                    ↓
          ┌─────────────────┐
          │  ALB (Multi-AZ) │
          │  80 → 443       │
          │  443 (HTTPS)    │
          └────────┬────────┘
                   │
    ┌──────────────┴──────────────┐
    │                              │
    ↓                              ↓
┌─────────────────┐    ┌─────────────────┐
│ Backend-API TG  │    │ Web-Driver TG   │
│ :3000           │    │ :3001           │
└────────┬────────┘    └────────┬────────┘
         │                      │
         ↓                      ↓
   ┌───────────────────────────────────────┐
   │ VPC 10.30.0.0/16 (2 AZs)              │
   │                                        │
   │ ┌────────────────────────────────────┐│
   │ │ Public Subnets                     ││
   │ │ - AZ1: 10.30.1.0/24                ││
   │ │ - AZ2: 10.30.2.0/24                ││
   │ │ - NAT Gateways (both AZs)          ││
   │ │ - Bastion Host (AZ1, SSH 0.0.0.0/0)││
   │ └────────────────────────────────────┘│
   │                                        │
   │ ┌────────────────────────────────────┐│
   │ │ Private App Subnets                ││
   │ │ - AZ1: 10.30.11.0/24               ││
   │ │ - AZ2: 10.30.12.0/24               ││
   │ │                                    ││
   │ │ ┌──────────┐      ┌──────────┐    ││
   │ │ │ ASG      │      │ ASG      │    ││
   │ │ │ backend  │      │ driver   │    ││
   │ │ │ (1-3)    │      │ (1-3)    │    ││
   │ │ └────┬─────┘      └────┬─────┘    ││
   │ └──────┼──────────────────┼──────────┘│
   │        └──────────┬───────┘            │
   │                   ↓                    │
   │ ┌────────────────────────────────────┐│
   │ │ Private DB Subnets                 ││
   │ │ - AZ1: 10.30.21.0/24               ││
   │ │ - AZ2: 10.30.22.0/24               ││
   │ │                                    ││
   │ │ ┌──────────────────────┐          ││
   │ │ │ RDS MySQL (Multi-AZ) │          ││
   │ │ │ Primary + Standby    │          ││
   │ │ └──────────────────────┘          ││
   │ └────────────────────────────────────┘│
   └───────────────────────────────────────┘
```

---

## Architecture Patterns

### DEV: Consolidated Instance Pattern

**Design Choice:** Single EC2 instance runs multiple applications

**Implementation:**
- One EC2 instance with unified IAM role `app_host`
- Process isolation via PM2 (not infrastructure)
- backend-api: port 3000, directory `/opt/apps/backend-api`
- web-driver: port 3001, directory `/opt/apps/web-driver`
- Single security group accepts traffic on both ports
- Merged IAM permissions (RDS + Cognito + CloudWatch + S3)

**Trade-offs:**
- ✅ **Cost:** ~50% reduction vs separate instances
- ✅ **Simplicity:** Single instance to manage
- ❌ **Blast Radius:** One instance failure affects all services
- ❌ **Resource Contention:** Services share CPU/memory
- ❌ **Security:** Merged permissions (broader access than needed)

**When to Use:**
- Development and testing only
- Low-traffic environments
- Cost is primary concern

---

### PROD: Separate ASG Pattern

**Design Choice:** Dedicated Auto Scaling Groups per service

**Implementation:**
- Separate ASG for backend-api (1-3 instances)
- Separate ASG for web-driver (1-3 instances)
- Separate IAM roles with least-privilege permissions
- Separate security groups with service-specific rules
- Independent scaling policies per service
- Multi-AZ deployment (instances span 2 AZs)

**Trade-offs:**
- ✅ **Isolation:** Service failures don't cascade
- ✅ **Security:** Least-privilege per service
- ✅ **Scaling:** Independent scaling per workload
- ✅ **Resilience:** Multi-AZ automatic failover
- ❌ **Cost:** 2x compute resources minimum
- ❌ **Complexity:** More moving parts to manage

**When to Use:**
- Production environments
- High availability requirements
- Services with different scaling characteristics

---

### Static Site Pattern (Both Environments)

**Architecture:**
CloudFront (Global) → Origin Access Control → Private S3 Bucket → KMS Encryption

**Key Features:**
- S3 buckets are **completely private** (no public access)
- CloudFront uses Origin Access Control (OAC) for secure access
- KMS customer-managed keys for encryption
- S3 Bucket Keys enabled (reduces KMS costs by 99%)
- WAF enabled in PROD (AWS Managed Rules in "count" mode)
- Security headers via CloudFront Response Headers Policy
- Route53 alias records point to CloudFront distributions

**Sites Deployed:**
- `admin.d2.fikri.dev` (web-admin)
- `passenger.d2.fikri.dev` (web-passenger)
- `driver.d2.fikri.dev` (web-driver via ALB, not CloudFront)

---

## AWS Services Used

### Compute
- **EC2:** Virtual servers for applications
  - DEV: t3.micro (1 vCPU, 1GB RAM)
  - PROD: t3.micro (1 vCPU, 1GB RAM) in ASGs
- **Auto Scaling Groups:** Self-healing EC2 clusters (PROD only)
- **Launch Templates:** Instance configuration blueprints

### Networking
- **VPC:** Isolated network per environment
- **Subnets:** Public (internet-facing), Private App, Private DB tiers
- **Internet Gateway:** VPC-to-internet connection
- **NAT Gateway:** Private instance outbound internet (PROD only)
- **Application Load Balancer:** HTTP/HTTPS load balancing
- **Route53:** DNS management
- **VPC Endpoints:** Private AWS API access (optional)

### Storage
- **S3:** Deployment artifacts + static site hosting
- **EBS:** EC2 root volumes (gp3, encrypted)
- **KMS:** Customer-managed encryption keys

### Database
- **RDS MySQL 8.0:** Relational database
  - DEV: Single-AZ, db.t3.micro, 20GB
  - PROD: Multi-AZ, db.t3.micro, 30GB
- **Secrets Manager:** RDS master password storage

### Security & Identity
- **IAM:** Roles, policies, instance profiles
- **Cognito:** User authentication (JWT tokens)
- **Security Groups:** VPC firewall rules
- **ACM:** SSL/TLS certificates (us-east-1 + ap-southeast-1)
- **SSM Parameter Store:** Runtime configuration

### Content Delivery
- **CloudFront:** Global CDN for static sites
- **WAF:** Web Application Firewall (PROD)

### Monitoring & Operations
- **CloudWatch Logs:** Application logging (7 days DEV, 90 days PROD)
- **CloudWatch Alarms:** Resource monitoring
- **SNS:** Alarm notifications
- **SSM Session Manager:** Bastion-less EC2 access

### CI/CD
- **GitHub OIDC Provider:** Passwordless authentication
- **IAM Roles:** GitHub Actions deployment permissions

---

## Network Architecture

### Subnets & CIDR Allocation

#### DEV (10.20.0.0/16)

| Subnet Type | CIDR | AZ | Usage |
|-------------|------|-----|-------|
| Public Primary | 10.20.1.0/24 | ap-southeast-1a | ALB, NAT Gateway (if enabled) |
| Public Secondary | 10.20.2.0/24 | ap-southeast-1b | ALB (multi-AZ requirement) |
| Private Primary | 10.20.11.0/24 | ap-southeast-1a | EC2 instances, RDS |
| Private Secondary | 10.20.12.0/24 | ap-southeast-1b | RDS subnet group (multi-AZ) |

#### PROD (10.30.0.0/16)

| Subnet Type | CIDR | AZ | Usage |
|-------------|------|-----|-------|
| Public 1 | 10.30.1.0/24 | ap-southeast-1a | ALB, NAT Gateway, Bastion |
| Public 2 | 10.30.2.0/24 | ap-southeast-1b | ALB, NAT Gateway |
| Private App 1 | 10.30.11.0/24 | ap-southeast-1a | ASG instances |
| Private App 2 | 10.30.12.0/24 | ap-southeast-1b | ASG instances |
| Private DB 1 | 10.30.21.0/24 | ap-southeast-1a | RDS Primary |
| Private DB 2 | 10.30.22.0/24 | ap-southeast-1b | RDS Standby |

### Internet Connectivity

#### DEV

```
Internet
  ↓
Internet Gateway (always-on)
  ↓
Public Subnets → ALB (optional)
  ↓
Private Subnets → EC2
  ↓
(No NAT by default → No outbound internet)
  ↓
VPC Endpoints (optional) → SSM/CloudWatch
```

#### PROD

```
Internet
  ↓
Internet Gateway (always-on)
  ↓
Public Subnets → ALB + NAT Gateways (2 AZs)
  ↓
Private App Subnets → ASG Instances
  ↓ (outbound via NAT)
NAT Gateways → Internet (for patches, npm packages)
```

### DNS Configuration

**Route53 Hosted Zone:** `fikri.dev` (Z019716819YT0PPFWXQPV)

**Domain Structure:**
- `d2.fikri.dev` → Base domain for this project
- `admin.d2.fikri.dev` → CloudFront (web-admin static site)
- `passenger.d2.fikri.dev` → CloudFront (web-passenger static site)
- `api.d2.fikri.dev` → ALB (backend-api)
- `driver.d2.fikri.dev` → ALB (web-driver SSR app)

**Certificate Strategy:**
- **CloudFront Certificate:** ACM in us-east-1 (CloudFront requirement)
  - Domain: `*.d2.fikri.dev` + `d2.fikri.dev`
  - Validation: DNS (Route53)
- **ALB Certificate:** ACM in ap-southeast-1 (regional requirement)
  - Domain: `*.d2.fikri.dev` + `d2.fikri.dev`
  - Validation: DNS (Route53)
  - Same DNS validation records can be reused

---

## Security & IAM

### Security Groups (DEV)

**Unified Security Group Model:**

```
┌─────────────────────────┐
│ alb                     │
│ In: 0.0.0.0/0:80,443    │
│ Out: app_host:3000,3001 │
└─────────────────────────┘
           ↓
┌─────────────────────────┐
│ app_host                │ ← Unified for both services
│ In: alb:3000,3001       │
│     (or VPC CIDR if     │
│      ALB disabled)      │
│ Out: RDS:3306           │
│      VPC:443,53         │
└─────────────────────────┘
           ↓
┌─────────────────────────┐
│ rds                     │
│ In: app_host:3306       │
│     bastion:3306        │
│ Out: VPC CIDR:443       │
└─────────────────────────┘
```

### Security Groups (PROD)

**Separated Security Group Model:**

```
┌─────────────────────────┐
│ alb                     │
│ In: 0.0.0.0/0:80,443    │
│ Out: backend_api:3000   │
│      driver_web:3001    │
└───────┬─────────┬───────┘
        │         │
        ↓         ↓
┌──────────┐ ┌──────────┐
│ backend  │ │ driver   │ ← Separate SGs
│ In: ALB  │ │ In: ALB  │
│ Out: RDS │ │ Out: N/A │
└────┬─────┘ └──────────┘
     ↓
┌─────────────────────────┐
│ rds                     │
│ In: backend_api:3306    │
│     bastion:3306        │
│ Out: VPC CIDR:443       │
└─────────────────────────┘
```

### IAM Roles & Permissions

#### Bootstrap Role: `github-actions-deploy-role`

**Purpose:** CI/CD deployment to both DEV and PROD

**Trust Policy:**
- GitHub OIDC provider
- Repository: `fikriimujahid/d2-ride-booking-new`
- Branches: `dev`, `main`
- Environments: `dev`, `main`, `prod`
- Pull requests: ✅ (for testing)

**Permissions:**
- EC2: Describe instances, create tags
- S3: Upload/download deployment artifacts
- S3: Deploy static sites (admin, passenger)
- SSM: Send commands to tagged instances
- CloudWatch: Read logs (for debugging deployments)
- CloudFront: Invalidate caches

**Security Note:** PR-based deployments are allowed but have limited permissions

#### DEV Role: `app_host`

**Attached to:** Consolidated EC2 instance  
**Merged Permissions:**
- CloudWatch Logs: Write to `/dev/backend-api/*` and `/dev/web-driver/*`
- SSM Parameter Store: Read `/dev/d2-ride-booking/backend-api/*` and `/web-driver/*`
- RDS IAM Auth: Connect as `app_user` to DEV RDS
- S3: Read deployment artifacts from deployment bucket
- Cognito: Validate JWT tokens
- Secrets Manager: Read RDS master password (if needed)

**Trade-off:** Broader permissions than necessary (least privilege violated for cost savings)

#### PROD Roles: `backend_api`, `driver_web`

**Separate Instance Profiles:**
- `prod-d2-ride-booking-backend-api-instance-profile`
- `prod-d2-ride-booking-driver-web-instance-profile`

**Backend API Permissions (Least Privilege):**
- CloudWatch Logs: Write to `/prod/backend-api/*` only
- SSM Parameter Store: Read `/prod/d2-ride-booking/backend-api/*` only
- RDS IAM Auth: Connect as `app_user` to PROD RDS
- S3: Read deployment artifacts (apps/backend-api/*) only
- Cognito: Validate JWT tokens

**Driver Web Permissions (Minimal):**
- CloudWatch Logs: Write to `/prod/web-driver/*` only
- SSM Parameter Store: Read `/prod/d2-ride-booking/web-driver/*` only
- S3: Read deployment artifacts (apps/web-driver/*) only
- **No RDS access** (frontend doesn't need database)

#### PROD CI/CD Role: `github-actions-prod-deploy-role`

**Purpose:** PROD-specific deployment (more restrictive than bootstrap role)

**Trust Policy:**
- GitHub OIDC provider
- Repository: `fikriimujahid/d2-ride-booking-new`
- Branch: `main` only
- Environment: `prod` only
- **No pull requests** (PROD deploys only from main branch)

**Permissions:**
- EC2: Describe instances (PROD tagged only)
- S3: Upload artifacts to PROD bucket
- S3: Deploy static sites (PROD buckets only)
- KMS: Encrypt/decrypt with static site keys
- CloudFront: Invalidate PROD distributions
- SSM: Send commands to PROD instances only (tag-based filtering)
- **Deny:** Interactive Session Manager (CI should not have shell access)

### Database Authentication

**Method:** IAM Database Authentication (Passwordless)

**How it works:**
1. Application EC2 instance has IAM role
2. AWS SDK generates short-lived authentication token (15 minutes)
3. Token is used instead of password to connect to RDS
4. RDS verifies token with AWS IAM service
5. Connection established without storing passwords

**Master Password:**
- Stored in AWS Secrets Manager
- Only for human admin access (DBA tasks, migrations)
- Application never uses master password
- Terraform generates random 32-character password

**Database User:**
- Master user: `admin` (humans only)
- Application user: `app_user` (IAM authentication)

---

## Cost Control

### Monthly Cost Breakdown

#### DEV (Minimal Configuration)

| Service | Cost | Toggle |
|---------|------|--------|
| VPC (networking) | $0 | Always-on |
| Internet Gateway | $0 | Always-on |
| S3 (deployment artifacts) | ~$0.50 | Always-on |
| Cognito | $0 | Always-on (free tier) |
| Route53 | $0.50 | Always-on |
| CloudWatch Logs | $0.20 | Always-on |
| **Optional Services:** | | |
| EC2 t3.micro | ~$7 | `enable_ec2_backend` |
| RDS db.t3.micro | ~$15 | `enable_rds` |
| NAT Gateway | ~$32 | `enable_nat_gateway` |
| ALB | ~$16 | `enable_alb` |
| VPC Endpoints (3x) | ~$7 | `enable_ssm_vpc_endpoints` |
| CloudFront | ~$0.50 | `enable_web_admin/passenger` |
| **Total (minimal):** | **~$1/month** | |
| **Total (all enabled):** | **~$78/month** | |

#### PROD (Full Configuration)

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| VPC (networking) | $0 | Free |
| Internet Gateway | $0 | Free |
| NAT Gateway (2 AZs) | ~$64 | Always-on |
| ALB | ~$16 | Always-on |
| ASG Backend (1 t3.micro) | ~$7 | Minimum, scales to 3 |
| ASG Driver (1 t3.micro) | ~$7 | Minimum, scales to 3 |
| RDS db.t3.micro (Multi-AZ) | ~$30 | Automatic failover |
| EBS Storage (40GB total) | ~$4 | gp3 volumes |
| S3 (artifacts + static) | ~$2 | With KMS encryption |
| CloudFront (2 distributions) | ~$1 | With WAF |
| Route53 | $0.50 | Hosted zone + queries |
| CloudWatch Logs | ~$3 | 90-day retention |
| Cognito | $0 | Free tier |
| Bastion t3.micro | ~$7 | Optional |
| **Total (minimum):** | **~$135/month** | |
| **Total (scaled to 3 instances):** | **~$170/month** | |

### Cost Optimization Strategies

#### DEV Cost Reduction

1. **Disable Unused Services**
   ```hcl
   enable_rds               = false  # Use Docker for local DB
   enable_nat_gateway       = false  # Use VPC endpoints instead
   enable_alb               = false  # Access via SSM port forwarding
   enable_ssm_vpc_endpoints = false  # No outbound needed
   ```

2. **Use On-Demand Scaling**
   - Start/stop RDS when not in use (requires manual intervention)
   - Terminate EC2 instances overnight (requires manual intervention)
   - Use AWS Instance Scheduler for automation

3. **Optimize Log Retention**
   ```hcl
   log_retention_days = 7  # vs 90 in PROD
   ```

4. **Leverage Free Tier**
   - First 12 months: 750 hours/month of t2.micro (not t3.micro)
   - Consider switching to t2.micro in DEV

#### PROD Cost Reduction

1. **Reserved Instances** (1-year commitment)
   - RDS Reserved Instance: ~30% savings (~$21/month vs $30)
   - EC2 Reserved Instances: ~30% savings (~$5/month vs $7)
   - **Potential Savings:** ~$18/month

2. **Savings Plans** (1-year commitment)
   - Compute Savings Plan: 15-20% discount on EC2 + RDS
   - More flexible than Reserved Instances

3. **Right-Size Resources**
   - Monitor CloudWatch metrics
   - If CPU < 20%, consider t3.nano (half the cost)
   - If DB connections < 50, consider db.t3.micro → db.t2.micro

4. **NAT Gateway Optimization**
   - Use VPC Endpoints for AWS services (SSM, S3, CloudWatch)
   - Reduces NAT Gateway data transfer charges
   - **Potential Savings:** ~$10-20/month in data transfer

5. **S3 Lifecycle Policies**
   - Move old deployment artifacts to Glacier after 30 days
   - Delete artifacts older than 90 days

### Infracost Integration

This project uses [Infracost](https://www.infracost.io/) for cost estimation.

**Generate cost report:**
```bash
cd infra/terraform/envs/dev
infracost breakdown --path . --format html > infracost-report.html
```

**Files:**
- `infracost-breakdown.json`: Machine-readable cost data
- `infracost-report.html`: Human-readable HTML report

**See:** [docs/infracost.md](./infracost.md) for details

---

## State Management

### Current Configuration

**⚠️ CRITICAL: All environments use LOCAL state**

```
infra/terraform/envs/
├── bootstrap/terraform.tfstate       ← Local state
├── dev/terraform.tfstate              ← Local state
└── prod/terraform.tfstate             ← Local state
```

**Risks:**
- 🔴 No team collaboration (concurrent runs will corrupt state)
- 🔴 No state locking (multiple users can run terraform simultaneously)
- 🔴 State stored in workspace (loss = infrastructure drift)
- 🔴 No encryption at rest
- 🔴 State contains sensitive data (RDS passwords, certificates)
- 🔴 No audit trail (who changed what, when?)

### Migration to Remote State (TODO)

**Recommended Configuration:**

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-731099197523"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Migration Steps:**

1. **Create DynamoDB Table (one-time)**
   ```bash
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region ap-southeast-1
   ```

2. **Verify S3 Bucket Exists**
   ```bash
   aws s3 ls s3://terraform-731099197523
   ```

3. **Enable Versioning on S3 Bucket**
   ```bash
   aws s3api put-bucket-versioning \
     --bucket terraform-731099197523 \
     --versioning-configuration Status=Enabled
   ```

4. **Add Backend Configuration to Each Environment**
   
   Create `backend.tf` in each env:
   ```hcl
   # infra/terraform/envs/dev/backend.tf
   terraform {
     backend "s3" {
       bucket         = "terraform-731099197523"
       key            = "envs/dev/terraform.tfstate"
       region         = "ap-southeast-1"
       encrypt        = true
       dynamodb_table = "terraform-state-lock"
     }
   }
   ```

5. **Migrate State**
   ```bash
   cd infra/terraform/envs/dev
   terraform init -migrate-state
   # Terraform will prompt: "Do you want to copy existing state?"
   # Answer: yes
   ```

6. **Verify Migration**
   ```bash
   # State should now be in S3
   aws s3 ls s3://terraform-731099197523/envs/dev/
   
   # Local state can be removed (backup first!)
   mv terraform.tfstate terraform.tfstate.backup
   ```

7. **Repeat for Other Environments**
   - Bootstrap: `key = "envs/bootstrap/terraform.tfstate"`
   - PROD: `key = "envs/prod/terraform.tfstate"`

---

## Deployment Strategy

### Application Deployment Flow

#### DEV (Consolidated Instance)

```
1. GitHub Actions triggered (push to dev branch)
   ↓
2. Build artifacts (npm run build)
   ↓
3. Upload to S3: s3://[project]-dev-deployments/apps/[service]/
   ↓
4. SSM Run Command to EC2 instance:
   - Download artifact from S3
   - Extract to /opt/apps/[service]
   - Restart PM2 process
   ↓
5. Health check via ALB (if enabled) or manual verification
```

**PM2 Process Management:**
```bash
# On the EC2 instance
pm2 list

# Should show:
# ┌─────┬──────────────┬─────────┬─────────┬─────────┬──────────┐
# │ id  │ name         │ mode    │ ↺       │ status  │ cpu      │
# ├─────┼──────────────┼─────────┼─────────┼─────────┼──────────┤
# │ 0   │ backend-api  │ fork    │ 0       │ online  │ 0%       │
# │ 1   │ web-driver   │ fork    │ 0       │ online  │ 0%       │
# └─────┴──────────────┴─────────┴─────────┴─────────┴──────────┘

# Restart individual service
pm2 restart backend-api

# View logs
pm2 logs backend-api
pm2 logs web-driver
```

#### PROD (Auto Scaling Groups)

```
1. GitHub Actions triggered (push to main branch)
   ↓
2. Build artifacts (npm run build)
   ↓
3. Upload to S3: s3://[project]-prod-deployments/apps/[service]/
   ↓
4. Update Launch Template user_data (if needed)
   ↓
5. Trigger ASG Instance Refresh:
   - Launch new instances with updated user_data
   - New instances download latest artifact on boot
   - Wait for health checks to pass
   - Terminate old instances (connection draining)
   ↓
6. Rolling update completes (zero downtime)
```

**Why 30-Minute Grace Period?**
- Instances boot → user_data runs → downloads app → starts PM2
- Total time: 5-10 minutes typically
- Grace period: 30 minutes (generous buffer)
- During grace period: ASG won't terminate instances for failing health checks

**ASG Instance Refresh Configuration:**
```hcl
instance_refresh {
  strategy = "Rolling"
  preferences {
    min_healthy_percentage = 50  # Keep at least 50% healthy during update
    instance_warmup        = 300 # Wait 5 minutes before checking health
  }
}
```

### Infrastructure Deployment

**DEV Workflow:**
```bash
cd infra/terraform/envs/dev

# 1. Review changes
terraform plan -out=tfplan

# 2. Apply (with approval)
terraform apply tfplan

# 3. Verify outputs
terraform output
```

**PROD Workflow:**
```bash
cd infra/terraform/envs/prod

# 1. Always plan first (review changes carefully)
terraform plan -out=prod.tfplan

# 2. Peer review (required for PROD)
# - Share tfplan with team
# - Review security group changes
# - Review IAM policy changes

# 3. Apply during maintenance window
terraform apply prod.tfplan

# 4. Monitor CloudWatch alarms
# 5. Verify application health
curl https://api.d2.fikri.dev/health
curl https://driver.d2.fikri.dev/health
```

---

## Operational Procedures

### Accessing EC2 Instances

#### Method 1: SSM Session Manager (Recommended)

**Why:** No SSH keys, no open ports, audited access

```bash
# List instances
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table

# Start session
aws ssm start-session --target i-0123456789abcdef0

# You're now in a bash shell on the instance
sh-5.2$ whoami
ssm-user

sh-5.2$ sudo su - ec2-user
[ec2-user@ip-10-20-11-123 ~]$
```

#### Method 2: SSH (Bastion Host - PROD only)

**⚠️ WARNING:** Bastion currently has SSH open to `0.0.0.0/0` (world-accessible)

```bash
# Get bastion public IP
cd infra/terraform/envs/prod
terraform output bastion_public_ip

# SSH to bastion (requires key pair)
ssh -i ~/.ssh/fikri-platform-key.pem ec2-user@<bastion-ip>

# From bastion, SSH to private instances
ssh ec2-user@10.30.11.10
```

**TODO: Restrict SSH access to specific IPs**

#### Method 3: SSM Port Forwarding (DEV - ALB disabled)

**Use case:** Access backend API directly when ALB is disabled

```bash
# Forward local port 3000 to EC2 instance port 3000
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# Access API locally
curl http://localhost:3000/health
```

### Viewing Logs

#### CloudWatch Logs

```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/dev/d2-ride-booking"

# Tail logs (requires CloudWatch Logs Insights or aws-logs-cli)
aws logs tail /dev/d2-ride-booking/backend-api --follow
```

#### On-Instance Logs (via SSM)

```bash
# Start session
aws ssm start-session --target i-0123456789abcdef0

# PM2 logs
pm2 logs backend-api
pm2 logs web-driver

# System logs
sudo journalctl -u amazon-ssm-agent -f
```

### Database Access

#### Method 1: Bastion + MySQL Client (PROD)

```bash
# SSH to bastion
ssh -i ~/.ssh/fikri-platform-key.pem ec2-user@<bastion-ip>

# Connect to RDS (master password from Secrets Manager)
mysql -h prod-d2-ride-booking-rds-mysql.xxxxx.ap-southeast-1.rds.amazonaws.com \
  -u admin \
  -p

# Or use IAM authentication token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname prod-d2-ride-booking-rds-mysql.xxxxx.ap-southeast-1.rds.amazonaws.com \
  --port 3306 \
  --username app_user)

mysql -h prod-d2-ride-booking-rds-mysql.xxxxx.ap-southeast-1.rds.amazonaws.com \
  --port=3306 \
  --user=app_user \
  --password="$TOKEN" \
  --ssl-ca=/path/to/aws-rds-global-bundle.pem \
  --ssl-mode=VERIFY_IDENTITY
```

#### Method 2: SSM Port Forwarding + Local MySQL Client

```bash
# Forward local port 3306 to RDS via bastion
aws ssm start-session \
  --target i-<bastion-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["prod-rds-endpoint"],"portNumber":["3306"],"localPortNumber":["3306"]}'

# Connect from local machine
mysql -h 127.0.0.1 -P 3306 -u app_user -p
```

### Running Migrations

**Application-driven migrations (NestJS/TypeORM):**

```bash
# SSH to instance or use SSM
aws ssm start-session --target i-0123456789abcdef0

# Navigate to app directory
cd /opt/apps/backend-api

# Run migrations
npm run migration:run

# Or manually via SSM Run Command
aws ssm send-command \
  --instance-ids i-0123456789abcdef0 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /opt/apps/backend-api && npm run migration:run"]'
```

### Scaling Operations (PROD)

#### Manual Scaling

```bash
cd infra/terraform/envs/prod

# Edit terraform.tfvars
# backend_asg_desired = 3  # Scale to 3 instances

terraform plan -out=scale.tfplan
terraform apply scale.tfplan

# Monitor scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name prod-d2-ride-booking-backend-api-asg \
  --max-records 10
```

#### Temporary Scaling (without Terraform)

```bash
# Quick scale-up (doesn't persist in Terraform state)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name prod-d2-ride-booking-backend-api-asg \
  --desired-capacity 5

# Quick scale-down
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name prod-d2-ride-booking-backend-api-asg \
  --desired-capacity 1

# ⚠️ WARNING: Next terraform apply will reset to terraform.tfvars value
```

### Disaster Recovery

#### RDS Snapshots

**Automated Backups:**
- DEV: 1 day retention
- PROD: 7 days retention
- Backup window: 03:00-04:00 UTC

**Manual Snapshot:**
```bash
aws rds create-db-snapshot \
  --db-instance-identifier prod-d2-ride-booking-rds-mysql \
  --db-snapshot-identifier manual-snapshot-$(date +%Y%m%d-%H%M%S)
```

**Restore from Snapshot:**
```bash
# 1. List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier prod-d2-ride-booking-rds-mysql

# 2. Restore (creates new RDS instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier prod-d2-ride-booking-rds-mysql-restored \
  --db-snapshot-identifier manual-snapshot-20260204-120000

# 3. Update Terraform or DNS to point to new instance
```

#### Terraform State Recovery

**If state is lost (local state file deleted):**

```bash
# 1. Import existing resources back into state
cd infra/terraform/envs/dev

# Example: Import VPC
terraform import module.vpc.aws_vpc.this vpc-0123456789abcdef

# Example: Import EC2 instance
terraform import 'module.ec2_app_host[0].aws_instance.this' i-0123456789abcdef0

# 2. This is tedious - better to restore from backup
# 3. TODO: Migrate to S3 backend with versioning
```

---

## Important Design Decisions

### 1. Local State (Not Recommended for Production)

**Current State:** All environments use local `terraform.tfstate` files  
**Risk Level:** 🔴 HIGH (especially for PROD)

**Decision Rationale:**
- Likely early-stage project prioritizing speed over governance
- Small team (1-2 people) where conflicts are rare
- State bucket exists but migration not completed

**Migration Path:** See [State Management](#state-management) section

---

### 2. Consolidated Instance in DEV

**Current State:** Single EC2 runs both backend-api and web-driver  
**Risk Level:** 🟡 MEDIUM

**Decision Rationale:**
- Cost optimization (~50% savings vs separate instances)
- Development workloads are low-traffic
- Acceptable blast radius for non-production

**When to Reconsider:**
- DEV traffic exceeds 100 req/min
- Services require independent scaling
- Testing ASG behavior before PROD deployment

---

### 3. Health Check Grace Period: 30 Minutes (PROD)

**Current State:** `asg_health_check_grace_period_seconds = 1800`  
**Risk Level:** 🟡 MEDIUM

**Decision Rationale:**
- Application deployment happens AFTER instance launch
- SSM Run Command downloads artifacts from S3
- User data installs dependencies, starts PM2
- Total bootstrap time: 5-10 minutes typically
- 30 minutes provides generous buffer

**Trade-offs:**
- ✅ Prevents premature instance termination during deployment
- ❌ Unhealthy instances stay in service for up to 30 minutes
- ❌ Slower incident response

**Recommended Change:**
- Reduce to 10 minutes once deployment process is stable
- Implement pre-baked AMIs (application pre-installed)

---

### 4. ASG Health Check Override: "EC2" (PROD)

**Current State:** `asg_health_check_type_override = "EC2"`  
**Risk Level:** 🔴 HIGH

**Decision Rationale:**
- Comment states: "Use 'EC2' to stop ELB-driven replacements until apps are deployed"
- Intended as temporary workaround during initial deployment
- Prevents ALB from replacing instances before application starts

**Trade-offs:**
- ✅ Allows instances to stabilize during initial deployment
- ❌ Unhealthy applications won't be replaced automatically
- ❌ Defeats purpose of ALB health checks

**Recommended Fix:**
```hcl
# After initial deployment, switch to ELB health checks
asg_health_check_type_override = ""  # Uses "ELB" (default for ALB)

# Or explicitly:
asg_health_check_type_override = "ELB"
```

**How to Deploy Fix:**
1. Verify all instances are healthy in ALB target group
2. Update terraform.tfvars
3. Apply change (no downtime - only changes ASG health check source)
4. Monitor for 24 hours to ensure instances aren't prematurely terminated

---

### 5. CloudWatch Alarms Disabled (PROD)

**Current State:** `enable_alarms = false` in PROD  
**Risk Level:** 🔴 HIGH

**Decision Rationale:**
- Likely disabled during testing to avoid alarm noise
- Incomplete monitoring strategy
- Email notification not configured

**TODO Before Go-Live:**
```hcl
# terraform.tfvars
enable_alarms = true
alarm_email   = "devops-team@example.com"  # Use team DL, not personal
```

**Alarms to Configure:**
- RDS CPU > 80% for 5 minutes
- RDS Storage < 10% free
- RDS Connection count > 80% of max
- ALB 5xx errors > 50 in 5 minutes
- ALB Unhealthy host count > 0
- Target group no healthy hosts

---

### 6. Bastion SSH Open to World (PROD)

**Current State:** `bastion_ssh_allowed_cidrs = ["0.0.0.0/0"]`  
**Risk Level:** 🔴 HIGH

**Decision Rationale:**
- Convenience during development
- Comment suggests "SSM-first" but SSH still enabled
- No specific IP restrictions

**Recommended Fix:**
```hcl
# Option 1: Use SSM only (best practice)
bastion_enable_ssh = false

# Option 2: Restrict SSH to office/VPN IPs
bastion_enable_ssh = true
bastion_ssh_allowed_cidrs = [
  "203.0.113.0/24",  # Office IP range
  "198.51.100.0/24"  # VPN IP range
]
```

---

### 7. VPC Endpoints Disabled (PROD)

**Current State:** `enable_ssm_vpc_endpoints = false`  
**Risk Level:** 🟡 MEDIUM

**Decision Rationale:**
- Cost optimization (~$7/month per endpoint × 3 = $21/month)
- NAT Gateway already enabled for outbound internet

**Trade-offs:**
- ❌ All AWS API calls route through NAT Gateway (data transfer charges)
- ❌ NAT Gateway is single point of failure for AWS API access
- ✅ Simpler architecture (fewer resources)

**When to Enable:**
- NAT Gateway data transfer costs > $21/month
- Compliance requires private AWS API access
- Defense-in-depth strategy (reduce NAT Gateway dependency)

**Monthly Cost Analysis:**
```
Without VPC Endpoints:
- NAT Gateway: $32/month (base)
- Data transfer: ~$0.045/GB
- Typical usage: 100GB/month = $4.50
- Total: $36.50/month

With VPC Endpoints:
- NAT Gateway: $32/month (base)
- VPC Endpoints: $7/month × 3 = $21/month
- Data transfer to VPC endpoints: $0.01/GB
- Typical usage: 100GB/month = $1.00
- Total: $54/month

Conclusion: VPC endpoints MORE expensive for <500GB/month
```

---

### 8. Certificate Duplication (Both Environments)

**Current State:** Two ACM certificates for same domain `*.d2.fikri.dev`  
**Risk Level:** 🟢 LOW (intentional design)

**Decision Rationale:**
- CloudFront requires certificate in us-east-1 (global requirement)
- ALB requires certificate in ap-southeast-1 (regional requirement)
- DNS validation records can be shared (no duplication)

**This is Correct:** Not a problem, just AWS architectural constraint

---

### 9. S3 Bucket Keys Enabled

**Current State:** `bucket_key_enabled = true` in static site modules  
**Risk Level:** 🟢 LOW

**Decision Rationale:**
- Reduces KMS API calls by ~99%
- Significant cost savings for high-throughput buckets
- No security trade-off (still encrypted at rest)

**Impact:**
- Without bucket keys: 100,000 objects × $0.03/10,000 requests = $0.30/month
- With bucket keys: 1 request × $0.03/10,000 requests = $0.000003/month

**This is Best Practice:** Keep enabled

---

### 10. RDS Master Password in Terraform State

**Current State:** `random_password` resource in Terraform, stored in state  
**Risk Level:** 🟡 MEDIUM

**Decision Rationale:**
- Terraform generates password (better than hardcoding)
- Password stored in Secrets Manager
- Application uses IAM authentication (doesn't need password)

**Trade-offs:**
- ❌ Password visible in Terraform state file
- ❌ State file not encrypted (local state)
- ✅ Password not hardcoded in source control
- ✅ Application doesn't use password anyway

**Mitigation:**
1. Migrate to S3 backend with encryption (priority)
2. Consider using pre-created secret: `data.aws_secretsmanager_secret_version`
3. Rotate master password regularly (manual process)

---

## Troubleshooting

### Common Issues

#### Issue: Terraform plan shows changes every run

**Symptom:** `terraform plan` shows changes even when nothing changed

**Common Causes:**
1. **Dynamic values in configs:** `timestamp()`, `uuid()` functions
2. **Resource drift:** Manual changes in AWS console
3. **Provider version changes:** `.terraform.lock.hcl` not tracked

**Solutions:**
```bash
# 1. Check for drift
terraform plan -refresh-only

# 2. Import manually changed resources
terraform import <resource_type>.<name> <aws_id>

# 3. Pin provider versions
# Commit .terraform.lock.hcl to git
```

#### Issue: ASG instances fail health checks immediately

**Symptom:** Instances launch, then terminate after 5 minutes

**Root Cause:** Health check grace period too short

**Solution:**
```hcl
# Increase grace period
asg_health_check_grace_period_seconds = 1800  # 30 minutes

# Or switch to EC2 health checks temporarily
asg_health_check_type_override = "EC2"
```

#### Issue: ALB returns 503 Service Unavailable

**Symptom:** `curl https://api.d2.fikri.dev` returns 503

**Debugging Steps:**
1. Check target group health
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <target-group-arn>
   ```

2. Check security groups
   ```bash
   # ALB should allow outbound to backend SG on port 3000
   # Backend SG should allow inbound from ALB SG on port 3000
   ```

3. Check application logs
   ```bash
   aws ssm start-session --target i-<instance-id>
   pm2 logs backend-api
   ```

#### Issue: Cannot access RDS from application

**Symptom:** Connection timeout or "Access denied"

**Debugging Steps:**
1. Check security groups
   ```bash
   # Backend SG should have outbound rule to RDS on 3306
   # RDS SG should allow inbound from Backend SG on 3306
   ```

2. Verify IAM authentication
   ```bash
   # On EC2 instance
   aws rds generate-db-auth-token \
     --hostname <rds-endpoint> \
     --port 3306 \
     --username app_user
   
   # Should return a token (not error)
   ```

3. Check RDS parameter group
   ```sql
   -- IAM authentication must be enabled
   SHOW VARIABLES LIKE 'rds.iam_authentication';
   ```

#### Issue: Static site (CloudFront) shows 403 Forbidden

**Symptom:** `curl https://admin.d2.fikri.dev` returns 403

**Root Causes:**
1. S3 bucket is empty (no index.html)
2. OAC permissions not configured
3. CloudFront cache contains old error

**Solutions:**
1. Deploy static site
   ```bash
   aws s3 sync ./dist s3://<bucket-name>/
   ```

2. Verify S3 bucket policy allows CloudFront OAC
   ```bash
   aws s3api get-bucket-policy --bucket <bucket-name>
   # Should reference CloudFront distribution
   ```

3. Invalidate CloudFront cache
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id <dist-id> \
     --paths "/*"
   ```

#### Issue: Terraform state lock error

**Symptom:** `Error acquiring the state lock`

**Root Cause:** Previous terraform run was interrupted

**Solution:**
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Better: Wait for lock timeout (15 minutes by default)
```

**Prevention:** Migrate to S3 backend with DynamoDB locking

---

## Next Steps & Recommendations

### Critical (Do Before Production Launch)

1. **Migrate to Remote State**
   - Priority: 🔴 CRITICAL
   - Effort: 2 hours
   - Risk: State corruption, loss
   - See: [State Management](#state-management)

2. **Enable CloudWatch Alarms (PROD)**
   - Priority: 🔴 CRITICAL
   - Effort: 1 hour
   - Risk: No visibility into incidents
   - Change: `enable_alarms = true`, configure `alarm_email`

3. **Fix ASG Health Check Type (PROD)**
   - Priority: 🔴 CRITICAL
   - Effort: 15 minutes
   - Risk: Unhealthy instances stay in service
   - Change: `asg_health_check_type_override = ""` (use ELB)

4. **Restrict Bastion SSH Access (PROD)**
   - Priority: 🔴 CRITICAL
   - Effort: 15 minutes
   - Risk: Unauthorized access
   - Change: Limit `bastion_ssh_allowed_cidrs` to office/VPN IPs

### High Priority

5. **Reduce ASG Grace Period (PROD)**
   - Priority: 🟡 HIGH
   - Effort: 15 minutes
   - Risk: Slow incident response
   - Change: Reduce to 600 seconds (10 minutes) after deployment stabilizes

6. **Implement Pre-Baked AMIs**
   - Priority: 🟡 HIGH
   - Effort: 8 hours
   - Benefit: Faster deployments, shorter grace period
   - Approach: Use Packer to build AMIs with application pre-installed

7. **Set Up Cross-Region RDS Snapshots**
   - Priority: 🟡 HIGH
   - Effort: 4 hours
   - Benefit: Disaster recovery
   - Approach: AWS Backup or Lambda-triggered snapshot copies

### Medium Priority

8. **Evaluate VPC Endpoints (PROD)**
   - Priority: 🟠 MEDIUM
   - Effort: 2 hours
   - Benefit: Reduce NAT costs if data transfer > 500GB/month
   - Approach: Monitor NAT Gateway metrics for 30 days

9. **Implement Reserved Instances**
   - Priority: 🟠 MEDIUM
   - Effort: 1 hour
   - Benefit: ~30% cost savings (~$18/month)
   - Timing: After 3 months of stable production usage

10. **Add WAF Rules (PROD)**
    - Priority: 🟠 MEDIUM
    - Effort: 4 hours
    - Current: WAF in "count" mode (logs only)
    - Change: Enable blocking rules after baseline established

### Nice to Have

11. **Implement Auto Scaling Policies**
    - Priority: 🟢 LOW
    - Effort: 8 hours
    - Current: Manual scaling only
    - Approach: CPU-based scaling (target 60% CPU utilization)

12. **Centralized Logging**
    - Priority: 🟢 LOW
    - Effort: 16 hours
    - Current: CloudWatch Logs per service
    - Approach: Aggregate to OpenSearch or third-party (Datadog, New Relic)

13. **Distributed Tracing**
    - Priority: 🟢 LOW
    - Effort: 24 hours
    - Current: No tracing
    - Approach: AWS X-Ray or OpenTelemetry

---

## Glossary

**ALB:** Application Load Balancer - AWS Layer 7 load balancer  
**ASG:** Auto Scaling Group - Self-healing EC2 cluster  
**AZ:** Availability Zone - AWS data center  
**CIDR:** Classless Inter-Domain Routing - IP address range notation  
**IAM:** Identity and Access Management - AWS permission system  
**NAT:** Network Address Translation - Allows private instances to reach internet  
**OAC:** Origin Access Control - CloudFront-to-S3 authentication (replaces OAI)  
**OIDC:** OpenID Connect - Passwordless authentication protocol  
**RDS:** Relational Database Service - Managed MySQL/PostgreSQL  
**SG:** Security Group - VPC firewall rules  
**SSM:** AWS Systems Manager - Remote instance management  
**TLS:** Transport Layer Security - Encryption protocol (replaces SSL)  
**VPC:** Virtual Private Cloud - Isolated AWS network  

---

## References

- [AWS Architecture Best Practices](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS RDS IAM Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

---

**Document Maintained By:** Infrastructure Team  
**Last Review Date:** February 4, 2026  
**Next Review Date:** May 4, 2026 (quarterly)
