# Terraform Infrastructure Guide (DEV & PROD)

**Target Audience:** Junior DevOps Engineers, Platform Engineers, Cloud Engineers  
**Last Updated:** February 4, 2026  
**Project:** D2 Ride Booking Platform  

---

## Table of Contents

1. [What is Terraform?](#1-what-is-terraform)
2. [Repository Structure](#2-repository-structure)
3. [Environment Separation Strategy](#3-environment-separation-strategy)
4. [Module Usage and Responsibilities](#4-module-usage-and-responsibilities)
5. [Variables and tfvars Explained](#5-variables-and-tfvars-explained)
6. [Backend State and Locking](#6-backend-state-and-locking)
7. [Naming, Tagging, and Conventions](#7-naming-tagging-and-conventions)
8. [Cost-Control Flags](#8-cost-control-flags)
9. [Safe vs Dangerous Terraform Commands](#9-safe-vs-dangerous-terraform-commands)
10. [DEV vs PROD Differences](#10-dev-vs-prod-differences)
11. [Common Operations](#11-common-operations)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. What is Terraform?

**Terraform** is an Infrastructure as Code (IaC) tool that lets you define cloud resources using code instead of clicking through AWS console.

### Why Use Terraform?

- **Repeatability:** Create identical infrastructure every time
- **Version Control:** Track infrastructure changes in Git
- **Automation:** Infrastructure can be created/destroyed with simple commands
- **Documentation:** The code itself documents what exists
- **Safety:** Review changes before applying them

### Key Concepts

| Concept | Explanation |
|---------|-------------|
| **Provider** | A plugin that talks to a cloud service (AWS, Azure, etc.) |
| **Resource** | A piece of infrastructure (EC2 instance, S3 bucket, VPC) |
| **Module** | Reusable Terraform code (like a function in programming) |
| **State** | Terraform's memory of what infrastructure exists |
| **Plan** | Preview of changes Terraform will make |
| **Apply** | Execute the changes to create/modify/destroy resources |

---

## 2. Repository Structure

```
infra/terraform/
├── envs/                          # Environment-specific configurations
│   ├── bootstrap/                 # One-time setup (OIDC provider, etc.)
│   │   ├── main.tf               # Bootstrap resources
│   │   ├── variables.tf          # Bootstrap variables
│   │   └── terraform.tfvars      # Bootstrap values
│   ├── dev/                       # DEV environment (cost-optimized)
│   │   ├── main.tf               # DEV root module (unified file)
│   │   ├── variables.tf          # DEV variable definitions
│   │   ├── terraform.tfvars      # DEV variable values
│   │   ├── outputs.tf            # DEV outputs
│   │   └── README.md             # DEV-specific operations guide
│   └── prod/                      # PROD environment (multi-AZ, hardened)
│       ├── main.tf               # PROD entry point (minimal)
│       ├── providers.tf          # Terraform & provider versions
│       ├── locals.tf             # PROD local values
│       ├── data.tf               # PROD data sources
│       ├── vpc.tf                # VPC configuration
│       ├── vpc-endpoints.tf      # VPC endpoints for SSM
│       ├── security-groups.tf    # Security groups
│       ├── acm-cloudfront.tf     # CloudFront SSL certificates
│       ├── acm-alb.tf            # ALB SSL certificates
│       ├── static-sites.tf       # S3 + CloudFront for web-admin/passenger
│       ├── deployments-bucket.tf # S3 bucket for deployment artifacts
│       ├── cognito.tf            # User authentication
│       ├── cicd-iam.tf           # GitHub Actions IAM role
│       ├── iam.tf                # EC2 instance profiles
│       ├── rds.tf                # Database
│       ├── ssm-params.tf         # Parameter Store secrets
│       ├── alb.tf                # Application Load Balancer
│       ├── asg-backend-api.tf    # Backend API Auto Scaling Group
│       ├── asg-web-driver.tf     # Web Driver Auto Scaling Group
│       ├── bastion.tf            # Bastion host for database access
│       ├── route53.tf            # DNS records
│       ├── cloudwatch.tf         # Monitoring and alarms
│       ├── variables.tf          # PROD variable definitions
│       ├── terraform.tfvars      # PROD variable values
│       └── outputs.tf            # PROD outputs
│
└── modules/                       # Reusable infrastructure components
    ├── alb/                       # Application Load Balancer
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── asg/                       # Auto Scaling Group for EC2 instances
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── user_data.sh          # Bootstrap script for EC2
    ├── bastion/                   # Bastion host
    ├── bootstrap/                 # Bootstrap utilities
    ├── cloudfront-static-site/    # S3 + CloudFront for static websites
    ├── cloudwatch/                # Alarms and monitoring
    ├── cognito/                   # User authentication
    ├── deployments-bucket/        # S3 for CI/CD artifacts
    ├── ec2/                       # Single EC2 instances
    ├── iam/                       # IAM roles and policies
    ├── rds/                       # RDS MySQL database
    ├── route53/                   # DNS management
    ├── s3/                        # S3 buckets
    ├── security-groups/           # DEV security groups
    ├── security-groups-prod/      # PROD security groups
    ├── vpc/                       # Virtual Private Cloud
    └── vpc-endpoints/             # VPC endpoints for AWS services
```

### Purpose of Each Directory

| Directory | Purpose | When to Edit |
|-----------|---------|--------------|
| `envs/bootstrap/` | One-time AWS account setup (OIDC provider) | Rarely - only during initial account setup |
| `envs/dev/` | Development environment configuration | Frequently - when testing infrastructure changes |
| `envs/prod/` | Production environment configuration | Carefully - requires approval and testing |
| `modules/` | Reusable infrastructure components | When adding new features or fixing bugs |

---

## 3. Environment Separation Strategy

### Critical Principle: DEV and PROD Are Completely Isolated

**Nothing is shared between DEV and PROD:**

| Resource Type | DEV | PROD | Shared? |
|--------------|-----|------|---------|
| VPC | `10.20.0.0/16` | `10.30.0.0/16` | ❌ NO |
| Subnets | `10.20.x.x` | `10.30.x.x` | ❌ NO |
| Security Groups | `dev-*` | `prod-*` | ❌ NO |
| RDS Database | Separate | Separate | ❌ NO |
| Cognito User Pool | Separate | Separate | ❌ NO |
| IAM Roles | `dev-*-role` | `prod-*-role` | ❌ NO |
| S3 Buckets | `dev-*` | `prod-*` | ❌ NO |
| Domain | `*.d2.fikri.dev` | `*.d2.fikri.dev` | ⚠️ DNS Zone Only |

### Why Complete Isolation?

1. **Blast Radius:** A mistake in DEV cannot affect PROD
2. **Audit Trail:** Clear which environment a change impacts
3. **Security:** Different permission levels for each environment
4. **Cost Tracking:** Easy to see costs per environment

### Network Architecture

#### DEV Network Layout
```
VPC: 10.20.0.0/16 (65,536 IPs)
├── Public Subnet (AZ1):    10.20.1.0/24  (256 IPs)
├── Public Subnet (AZ2):    10.20.2.0/24  (256 IPs)
├── Private Subnet (AZ1):   10.20.11.0/24 (256 IPs)
└── Private Subnet (AZ2):   10.20.12.0/24 (256 IPs)

Note: DEV does NOT have separate DB subnets (cost optimization)
```

#### PROD Network Layout
```
VPC: 10.30.0.0/16 (65,536 IPs)
├── Public Subnet (AZ1):    10.30.1.0/24  (256 IPs) - ALB, NAT Gateway
├── Public Subnet (AZ2):    10.30.2.0/24  (256 IPs) - ALB, NAT Gateway
├── Private App (AZ1):      10.30.11.0/24 (256 IPs) - EC2 instances
├── Private App (AZ2):      10.30.12.0/24 (256 IPs) - EC2 instances
├── Private DB (AZ1):       10.30.21.0/24 (256 IPs) - RDS primary
└── Private DB (AZ2):       10.30.22.0/24 (256 IPs) - RDS standby

Note: PROD has dedicated DB tier for better security
```

---

## 4. Module Usage and Responsibilities

Modules are like functions in programming - they encapsulate reusable infrastructure logic.

### Module Overview

| Module | What It Creates | Used In | Cost Impact |
|--------|----------------|---------|-------------|
| **vpc** | VPC, subnets, Internet Gateway, NAT Gateway, route tables | DEV, PROD | 💰💰 (NAT Gateway ~$32/month) |
| **rds** | RDS MySQL database, subnet group, security group rules | DEV (optional), PROD | 💰💰💰 (db.t3.micro ~$25/month) |
| **cognito** | User Pool, App Client, custom attributes | DEV, PROD | FREE (up to 50k MAU) |
| **alb** | Application Load Balancer, Target Groups, Listeners | DEV (optional), PROD | 💰💰 (~$22/month + data transfer) |
| **asg** | Launch Template, Auto Scaling Group, IAM instance profile | DEV (optional), PROD | 💰 (t3.micro ~$7.50/month per instance) |
| **bastion** | Bastion EC2, security group, optional SSH access | DEV (optional), PROD | 💰 (~$7.50/month) |
| **cloudfront-static-site** | S3 bucket, CloudFront distribution, ACM cert | DEV, PROD | 💰 (~$1-5/month depending on traffic) |
| **vpc-endpoints** | Interface endpoints for SSM, SSM Messages, EC2 Messages | DEV (optional), PROD | 💰 (~$7-10/month per endpoint) |
| **security-groups** | Security groups with allow/deny rules | DEV | FREE |
| **security-groups-prod** | Security groups with stricter rules | PROD | FREE |
| **iam** | IAM roles, policies, instance profiles | DEV, PROD | FREE |
| **route53** | DNS A/CNAME records | DEV, PROD | FREE (if using existing zone) |
| **cloudwatch** | Alarms, SNS topics for alerts | PROD | FREE (within limits) |

### How Modules Are Called

Modules are invoked from environment-specific `.tf` files:

#### Example: DEV Calling VPC Module

```terraform
# Location: infra/terraform/envs/dev/main.tf

module "vpc" {
  source = "../../modules/vpc"  # Relative path to module

  # Required inputs
  vpc_cidr                      = var.vpc_cidr
  public_subnet_cidr            = var.public_subnet_cidr
  public_subnet_cidr_secondary  = var.public_subnet_cidr_secondary
  private_subnet_cidr           = var.private_subnet_cidr
  private_subnet_cidr_secondary = var.private_subnet_cidr_secondary
  availability_zone             = var.availability_zone
  availability_zone_secondary   = var.availability_zone_secondary

  # Optional inputs
  enable_nat_gateway            = var.enable_nat_gateway  # Usually false in DEV
  enable_multi_az               = false
  az_count                      = 2

  tags = var.tags
}
```

#### Module Outputs Usage

Modules expose outputs that other modules can use:

```terraform
# VPC module outputs
output "vpc_id" {
  value = aws_vpc.this.id
}

# RDS module uses VPC output
module "rds" {
  source = "../../modules/rds"
  
  vpc_id             = module.vpc.vpc_id         # ← Uses VPC module output
  private_subnet_ids = module.vpc.private_subnet_ids
  ...
}
```

---

## 5. Variables and tfvars Explained

### Variable Types

Terraform has **two files** for variables:

| File | Purpose | Example |
|------|---------|---------|
| `variables.tf` | **Declares** variables (defines what variables exist, their types, and defaults) | `variable "environment" { type = string }` |
| `terraform.tfvars` | **Assigns** values to variables (the actual values to use) | `environment = "dev"` |

### Example: How Variables Work

#### Step 1: Declare Variable (`variables.tf`)
```terraform
variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"  # Used if no value provided in tfvars
}

variable "enable_rds" {
  type        = bool
  description = "Enable RDS database (cost toggle)"
  default     = false
}
```

#### Step 2: Assign Value (`terraform.tfvars`)
```terraform
environment = "dev"
enable_rds  = false  # Don't create RDS to save money
```

#### Step 3: Use Variable (`main.tf`)
```terraform
module "rds" {
  count  = var.enable_rds ? 1 : 0  # Create RDS only if enabled
  source = "../../modules/rds"
  
  environment = var.environment  # Use the variable value
  ...
}
```

### DEV terraform.tfvars Explained

**File:** `infra/terraform/envs/dev/terraform.tfvars`

```terraform
# ========================================
# GENERAL SETTINGS
# ========================================
environment  = "dev"                  # Environment identifier
project_name = "d2-ride-booking"      # Project name (used in resource names)
domain_name  = "fikri.dev"            # Root domain
aws_region   = "ap-southeast-1"       # Singapore region

# ========================================
# NETWORK CONFIGURATION
# ========================================
vpc_cidr = "10.20.0.0/16"             # 65,536 IP addresses

# Public subnets (have internet access via Internet Gateway)
public_subnet_cidr           = "10.20.1.0/24"   # 256 IPs, AZ1
public_subnet_cidr_secondary = "10.20.2.0/24"   # 256 IPs, AZ2

# Private subnets (internet access via NAT Gateway if enabled)
private_subnet_cidr           = "10.20.11.0/24"  # 256 IPs, AZ1
private_subnet_cidr_secondary = "10.20.12.0/24"  # 256 IPs, AZ2

# Availability Zones
availability_zone           = "ap-southeast-1a"  # Primary AZ
availability_zone_secondary = "ap-southeast-1b"  # Secondary AZ

# ========================================
# DNS CONFIGURATION
# ========================================
route53_zone_id = "Z019716819YT0PPFWXQPV"  # Hosted Zone ID for fikri.dev

# ========================================
# DATABASE CONFIGURATION
# ========================================
db_name            = "ridebooking"
db_master_username = "admin"
rds_db_user        = "app_user"
rds_instance_class = "db.t3.micro"         # Smallest RDS instance (~$25/month)
rds_engine_version = "8.0"                 # MySQL 8.0

# ========================================
# EC2 CONFIGURATION
# ========================================
backend_instance_type    = "t3.micro"      # ~$7.50/month
backend_root_volume_size = 16              # GB

# ========================================
# COST CONTROL FLAGS 💰
# ========================================
enable_ec2_backend       = false           # ❌ No backend EC2 (save $7.50/month)
enable_rds               = false           # ❌ No RDS (save $25/month)
enable_nat_gateway       = false           # ❌ No NAT (save $32/month)
enable_alb               = false           # ❌ No ALB (save $22/month)
enable_ssm_vpc_endpoints = false           # ❌ No VPC endpoints (save $21/month)
enable_bastion           = false           # ❌ No bastion (save $7.50/month)

enable_web_admin     = false               # ❌ No web-admin CloudFront
enable_web_passenger = false               # ❌ No web-passenger CloudFront
enable_web_driver    = false               # ❌ No web-driver EC2

# ========================================
# RESOURCE TAGS
# ========================================
tags = {
  Environment = "dev"
  Project     = "d2-ride-booking"
  ManagedBy   = "terraform"
  Domain      = "d2.fikri.dev"
}
```

### PROD terraform.tfvars Differences

**File:** `infra/terraform/envs/prod/terraform.tfvars`

```terraform
environment = "prod"
vpc_cidr    = "10.30.0.0/16"  # Non-overlapping with DEV

# Multi-AZ Configuration
availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b"
]

# ========================================
# PROD-SPECIFIC SETTINGS
# ========================================
enable_rds         = true                  # ✅ RDS enabled
enable_nat_gateway = true                  # ✅ NAT Gateway enabled (required for updates)
enable_bastion     = true                  # ✅ Bastion for DB access

# RDS Hardening
rds_backup_retention_days = 7              # 7-day backups (DEV = 1 day)
rds_multi_az              = true           # Multi-AZ for high availability
deletion_protection       = true           # Prevent accidental deletion

# Cognito Hardening
cognito_password_min_length = 12           # 12 chars (DEV = 8 chars)

# Monitoring
enable_alarms = true                       # CloudWatch alarms
alarm_email   = "alerts@example.com"       # Alert destination
log_retention_days = 90                    # 90 days (DEV = 7 days)

# GitHub Actions Integration
enable_github_actions_deploy_role = true
github_repo = "fikriimujahid/d2-ride-booking-new"
```

---

## 6. Backend State and Locking

### What is Terraform State?

**Terraform State** is a JSON file that stores:
- What resources Terraform has created
- Current configuration of those resources
- Metadata about resource dependencies

**Location:** `terraform.tfstate` in the environment directory

### ⚠️ CRITICAL: State File Safety Rules

| Rule | Explanation |
|------|-------------|
| ✅ **DO** commit `terraform.tfvars` to Git | It's just configuration, not secrets |
| ❌ **DO NOT** commit `terraform.tfstate` to Git | Contains sensitive data (passwords, ARNs) |
| ❌ **DO NOT** edit state files manually | Use `terraform state` commands |
| ✅ **DO** back up state files before major changes | Copy to safe location |
| ❌ **DO NOT** delete state files | You'll lose track of all resources |

### Current State Backend: Local

**Your repository uses LOCAL state storage:**

```terraform
# File: infra/terraform/envs/dev/main.tf
terraform {
  required_version = ">= 1.6.0"
  # No backend block = local state storage
}
```

**What this means:**
- State file is stored on your local machine: `infra/terraform/envs/dev/terraform.tfstate`
- ⚠️ **Risk:** If you delete the file, Terraform loses track of resources
- ⚠️ **Team Problem:** Two people can't work simultaneously (state conflicts)

### Recommended: Migrate to S3 Backend

For team environments, use **S3 + DynamoDB** for state locking:

```terraform
terraform {
  backend "s3" {
    bucket         = "d2-ride-booking-terraform-state"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "d2-ride-booking-terraform-locks"
    encrypt        = true
  }
}
```

**Benefits:**
- ✅ State stored in S3 (team can access)
- ✅ DynamoDB prevents concurrent modifications
- ✅ Encryption at rest
- ✅ Version history in S3

**To migrate:**
```powershell
cd infra\terraform\envs\dev

# Add backend block to main.tf (shown above)

# Migrate state
terraform init -migrate-state
```

---

## 7. Naming, Tagging, and Conventions

### Resource Naming Pattern

**Format:** `{environment}-{project_name}-{service}-{resource_type}`

#### Examples

| Resource Type | Name | Breakdown |
|--------------|------|-----------|
| VPC | `dev-d2-ride-booking-vpc` | `dev` + `d2-ride-booking` + `vpc` |
| RDS Instance | `dev-d2-ride-booking` | `dev` + `d2-ride-booking` |
| Security Group | `dev-d2-ride-booking-backend-api` | `dev` + `d2-ride-booking` + `backend-api` |
| S3 Bucket | `dev-d2-ride-booking-deployments` | `dev` + `d2-ride-booking` + `deployments` |
| IAM Role | `dev-d2-ride-booking-ec2-backend-role` | `dev` + `d2-ride-booking` + `ec2-backend-role` |

### Why This Pattern?

1. **Environment clarity:** Immediately know if resource is DEV or PROD
2. **Project grouping:** All resources for this project have consistent prefix
3. **AWS Console filtering:** Easy to filter by name prefix
4. **Cost allocation:** Tag-based cost tracking

### Tag Strategy

**All resources get these tags:**

```terraform
tags = {
  Environment = "dev"              # dev / staging / prod
  Project     = "d2-ride-booking"  # Project identifier
  ManagedBy   = "terraform"        # How it was created
  Domain      = "d2.fikri.dev"     # Associated domain (optional)
}
```

**Additional tags for specific resources:**

```terraform
# VPC tags
tags = merge(var.tags, {
  Name = "dev-d2-ride-booking-vpc"
  Type = "networking"
})

# RDS tags
tags = merge(var.tags, {
  Name    = "dev-d2-ride-booking-mysql"
  Service = "database"
  Engine  = "mysql-8.0"
})
```

### CIDR Allocation Strategy

| Environment | VPC CIDR | Public Subnets | Private App Subnets | Private DB Subnets |
|-------------|----------|----------------|---------------------|-------------------|
| DEV | `10.20.0.0/16` | `10.20.1-2.0/24` | `10.20.11-12.0/24` | N/A (cost savings) |
| PROD | `10.30.0.0/16` | `10.30.1-2.0/24` | `10.30.11-12.0/24` | `10.30.21-22.0/24` |
| Future Staging | `10.40.0.0/16` | Reserved | Reserved | Reserved |

**Why this matters:**
- No IP overlap = environments can be VPC-peered if needed
- `/16` = 65,536 IPs per environment (plenty of room to grow)
- `/24` = 256 IPs per subnet (sufficient for most use cases)

---

## 8. Cost-Control Flags

DEV environment uses **feature flags** to minimize costs. Each flag enables/disables expensive resources.

### Cost Flag Reference

| Flag | What It Controls | Monthly Cost | DEV Default | PROD Default |
|------|------------------|--------------|-------------|--------------|
| `enable_nat_gateway` | NAT Gateway for private subnet internet access | ~$32 | ❌ false | ✅ true |
| `enable_alb` | Application Load Balancer | ~$22 + data | ❌ false | ✅ true |
| `enable_rds` | RDS MySQL database | ~$25 (t3.micro) | ❌ false | ✅ true |
| `enable_ec2_backend` | Backend API EC2 instance | ~$7.50 (t3.micro) | ❌ false | ✅ true |
| `enable_bastion` | Bastion host for DB access | ~$7.50 | ❌ false | ✅ true |
| `enable_ssm_vpc_endpoints` | VPC endpoints for SSM (3 endpoints) | ~$21 | ❌ false | ❌ false |
| `enable_web_admin` | Web Admin CloudFront + S3 | ~$1-5 | ❌ false | ✅ true |
| `enable_web_passenger` | Web Passenger CloudFront + S3 | ~$1-5 | ❌ false | ✅ true |
| `enable_web_driver` | Web Driver EC2 (Next.js SSR) | ~$7.50 | ❌ false | ✅ true |

### How Flags Work

Flags use Terraform's **count** meta-argument:

```terraform
# If enable_rds is true, count = 1 (create 1 module)
# If enable_rds is false, count = 0 (create 0 modules = skip)
module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"
  ...
}
```

### DEV Cost Scenarios

| Scenario | Enabled Resources | Estimated Monthly Cost |
|----------|------------------|------------------------|
| **Minimal** (all flags OFF) | VPC, Cognito, Route53 | ~$5 (just data transfer) |
| **Backend Testing** | + RDS + Backend EC2 | ~$37.50 |
| **Full Stack** | + ALB + NAT + Bastion + Web Driver | ~$100 |

### Toggling Resources

#### Enable RDS in DEV

```powershell
cd infra\terraform\envs\dev

# Edit terraform.tfvars
# Change: enable_rds = false
# To:     enable_rds = true

# Preview changes
terraform plan

# Apply changes
terraform apply
```

#### Disable RDS to Save Money

```powershell
# Edit terraform.tfvars
# Change: enable_rds = true
# To:     enable_rds = false

# Preview (will show RDS being destroyed)
terraform plan

# Apply (destroys RDS - ⚠️ data loss!)
terraform apply
```

⚠️ **WARNING:** Disabling `enable_rds` will **DELETE the database and all data**!

---

## 9. Safe vs Dangerous Terraform Commands

### ✅ SAFE Commands (Read-Only)

These commands **never modify** AWS resources:

```powershell
# Initialize Terraform (download providers)
terraform init

# Validate syntax (check for errors)
terraform validate

# Format code (fix indentation)
terraform fmt

# Preview changes WITHOUT applying
terraform plan

# Show current state
terraform show

# List resources in state
terraform state list

# Show specific resource details
terraform state show aws_vpc.this

# Show outputs
terraform output

# Show outputs in JSON
terraform output -json
```

### ⚠️ DANGEROUS Commands (Modify AWS)

These commands **create, modify, or destroy** AWS resources:

```powershell
# Apply changes (creates/modifies/destroys resources)
terraform apply

# Apply without asking for confirmation (VERY DANGEROUS)
terraform apply -auto-approve

# Destroy ALL resources (EXTREMELY DANGEROUS)
terraform destroy

# Destroy specific resource
terraform destroy -target=module.rds

# Import existing AWS resource into state
terraform import aws_instance.example i-1234567890abcdef0

# Remove resource from state (doesn't delete in AWS)
terraform state rm aws_instance.example

# Move resource in state
terraform state mv aws_instance.old aws_instance.new
```

### DO / DO NOT Rules

| ✅ DO | ❌ DO NOT |
|-------|-----------|
| ✅ Always run `terraform plan` before `apply` | ❌ Never run `terraform destroy` in PROD without approval |
| ✅ Review the plan output carefully | ❌ Never use `-auto-approve` in PROD |
| ✅ Back up state before major changes | ❌ Never edit `terraform.tfstate` manually |
| ✅ Test changes in DEV first | ❌ Never delete state files |
| ✅ Use version control (Git) | ❌ Never commit state files to Git |
| ✅ Use meaningful commit messages | ❌ Never apply changes you don't understand |

### Safe Workflow

```powershell
# 1. Check current directory
pwd
# Should be: infra\terraform\envs\dev or infra\terraform\envs\prod

# 2. Pull latest code
git pull

# 3. Initialize (safe, downloads providers)
terraform init

# 4. Validate syntax (safe, checks for errors)
terraform validate

# 5. Plan (safe, preview only)
terraform plan
# READ THE OUTPUT! Look for:
# - Resources being created (+)
# - Resources being modified (~)
# - Resources being destroyed (-)

# 6. If plan looks good, apply
terraform apply
# Type "yes" when prompted

# 7. Verify outputs
terraform output
```

---

## 10. DEV vs PROD Differences

### Comprehensive Comparison Table

| Aspect | DEV | PROD |
|--------|-----|------|
| **VPC CIDR** | `10.20.0.0/16` | `10.30.0.0/16` |
| **Availability Zones** | 2 (minimal HA) | 2 (true HA) |
| **NAT Gateway** | ❌ Disabled (save $32/month) | ✅ Enabled (required for updates) |
| **RDS Multi-AZ** | ❌ Single-AZ (save $25/month) | ✅ Multi-AZ (high availability) |
| **RDS Backups** | 1 day retention | 7 day retention |
| **RDS Deletion Protection** | ❌ Disabled (easy to delete) | ✅ Enabled (prevent accidents) |
| **RDS Instance Class** | `db.t3.micro` | `db.t3.micro` (upgradeable) |
| **ALB** | Optional (disabled by default) | ✅ Enabled |
| **Bastion Host** | Optional (disabled by default) | ✅ Enabled |
| **Auto Scaling** | Min: 0, Desired: 0, Max: 1 | Min: 1, Desired: 1, Max: 3 |
| **Cognito Password Length** | 8 characters (lenient) | 12 characters (strict) |
| **CloudWatch Alarms** | ❌ Disabled | ✅ Enabled |
| **Log Retention** | 7 days | 90 days |
| **VPC Endpoints** | Optional (disabled by default) | Optional (cost consideration) |
| **IMDSv2** | ✅ Required | ✅ Required |
| **EBS Encryption** | ✅ Enabled | ✅ Enabled |
| **S3 Versioning** | ❌ Disabled | ✅ Enabled |
| **GitHub Actions Role** | ❌ N/A | ✅ Enabled |
| **Domain** | `*.d2.fikri.dev` (shared DNS zone) | `*.d2.fikri.dev` (shared DNS zone) |
| **DNS Records** | `admin.d2.fikri.dev`, etc. | `api.d2.fikri.dev`, `driver.d2.fikri.dev` |

### Network Architecture Differences

#### DEV: Simplified 2-Tier
```
┌─────────────────────────────────────────┐
│ VPC: 10.20.0.0/16                       │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │ Public   │  │ Public   │            │
│  │ Subnet   │  │ Subnet   │            │
│  │ AZ1      │  │ AZ2      │            │
│  └──────────┘  └──────────┘            │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │ Private  │  │ Private  │            │
│  │ Subnet   │  │ Subnet   │            │
│  │ AZ1      │  │ AZ2      │            │
│  │ (EC2+RDS)│  │ (EC2+RDS)│            │
│  └──────────┘  └──────────┘            │
│                                         │
│  No NAT Gateway (cost savings)          │
│  Single-AZ RDS (cost savings)           │
└─────────────────────────────────────────┘
```

#### PROD: Hardened 3-Tier
```
┌─────────────────────────────────────────┐
│ VPC: 10.30.0.0/16                       │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │ Public   │  │ Public   │            │
│  │ Subnet   │  │ Subnet   │            │
│  │ AZ1      │  │ AZ2      │            │
│  │ (ALB+NAT)│  │ (ALB+NAT)│            │
│  └──────────┘  └──────────┘            │
│       │             │                   │
│  ┌──────────┐  ┌──────────┐            │
│  │ Private  │  │ Private  │            │
│  │ App      │  │ App      │            │
│  │ AZ1      │  │ AZ2      │            │
│  │ (EC2 ASG)│  │ (EC2 ASG)│            │
│  └──────────┘  └──────────┘            │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │ Private  │  │ Private  │            │
│  │ DB       │  │ DB       │            │
│  │ AZ1      │  │ AZ2      │            │
│  │ (RDS Pri)│  │(RDS Stby)│            │
│  └──────────┘  └──────────┘            │
│                                         │
│  Multi-AZ RDS (auto-failover)           │
│  NAT Gateway (secure internet access)   │
└─────────────────────────────────────────┘
```

### File Structure Differences

#### DEV: Monolithic
```
envs/dev/
├── main.tf         # All resources in ONE file (665 lines)
├── variables.tf    # Variable declarations
├── terraform.tfvars# Variable values
└── outputs.tf      # Outputs
```

**Why monolithic?**
- DEV changes frequently
- Easier to see everything in one place
- Faster iteration

#### PROD: Split by Service
```
envs/prod/
├── main.tf               # Minimal entry point
├── providers.tf          # Provider configuration
├── locals.tf             # Local values
├── data.tf               # Data sources
├── vpc.tf                # VPC configuration
├── vpc-endpoints.tf      # VPC endpoints
├── security-groups.tf    # Security groups
├── cognito.tf            # Cognito
├── rds.tf                # Database
├── alb.tf                # Load balancer
├── asg-backend-api.tf    # Backend Auto Scaling
├── asg-web-driver.tf     # Web Driver Auto Scaling
├── bastion.tf            # Bastion
├── route53.tf            # DNS
├── cloudwatch.tf         # Monitoring
├── ...                   # (other services)
├── variables.tf          # Variables
├── terraform.tfvars      # Values
└── outputs.tf            # Outputs
```

**Why split?**
- Easier code review (smaller files)
- Clearer ownership per service
- Safer to modify (less chance of breaking unrelated things)

---

## 11. Common Operations

### Initial Setup (First Time)

```powershell
# 1. Clone repository
git clone https://github.com/fikriimujahid/d2-ride-booking-new.git
cd d2-ride-booking-new

# 2. Navigate to DEV environment
cd infra\terraform\envs\dev

# 3. Review configuration
cat terraform.tfvars

# 4. Initialize Terraform (download providers)
terraform init

# 5. Validate syntax
terraform validate

# 6. Preview what will be created
terraform plan

# 7. Create infrastructure
terraform apply
# Review plan, type "yes" to proceed
```

### Enable RDS in DEV

```powershell
cd infra\terraform\envs\dev

# 1. Edit terraform.tfvars
# Change: enable_rds = false
# To:     enable_rds = true

# 2. Preview changes
terraform plan
# Look for: module.rds[0] will be created

# 3. Apply
terraform apply
# Type "yes"

# 4. Get RDS endpoint
terraform output rds_endpoint
```

### Deploy to PROD

```powershell
cd infra\terraform\envs\prod

# 1. Review changes
git diff

# 2. Initialize
terraform init

# 3. Plan
terraform plan -out=plan.tfplan
# Save plan to file for review

# 4. Review saved plan
terraform show plan.tfplan

# 5. Apply saved plan (no approval needed if plan is saved)
terraform apply plan.tfplan
```

### Destroy DEV Environment (Save Money)

```powershell
cd infra\terraform\envs\dev

# 1. Preview what will be destroyed
terraform plan -destroy

# 2. Destroy all resources
terraform destroy
# Type "yes"

# ⚠️ WARNING: This deletes EVERYTHING!
# - VPC, subnets, routing tables
# - RDS database (ALL DATA LOST!)
# - EC2 instances
# - S3 buckets (if empty)
# - Security groups
# - IAM roles
```

### Update Terraform Providers

```powershell
cd infra\terraform\envs\dev

# 1. Check current versions
terraform version

# 2. Update providers (respects version constraints)
terraform init -upgrade

# 3. Verify no changes needed
terraform plan
# Should show "No changes"
```

### Import Existing Resource

If you created a resource manually in AWS console and want Terraform to manage it:

```powershell
# Example: Import VPC with ID vpc-12345678
terraform import module.vpc.aws_vpc.this vpc-12345678

# Verify it's in state
terraform state show module.vpc.aws_vpc.this

# Update your .tf file to match the imported resource
# Then run:
terraform plan
# Should show "No changes"
```

---

## 12. Troubleshooting

### Problem: "Error: Backend initialization required"

**Error Message:**
```
Error: Backend initialization required, please run "terraform init"
```

**Solution:**
```powershell
terraform init
```

**Explanation:** Terraform needs to download provider plugins first.

---

### Problem: "Error: Insufficient IAM permissions"

**Error Message:**
```
Error: Error creating VPC: UnauthorizedOperation: You are not authorized to perform this operation
```

**Solution:**
1. Check AWS credentials:
   ```powershell
   aws sts get-caller-identity
   ```

2. Verify IAM permissions - you need:
   - `ec2:CreateVpc`
   - `ec2:CreateSubnet`
   - `rds:CreateDBInstance`
   - etc.

3. If using a specific IAM role:
   ```powershell
   aws configure set aws_access_key_id YOUR_KEY
   aws configure set aws_secret_access_key YOUR_SECRET
   aws configure set region ap-southeast-1
   ```

---

### Problem: "Resource already exists"

**Error Message:**
```
Error: Error creating VPC: VpcLimitExceeded: The maximum number of VPCs has been reached
```

**Solution:**
1. Check existing VPCs:
   ```powershell
   aws ec2 describe-vpcs --region ap-southeast-1
   ```

2. Delete unused VPCs in AWS console, OR

3. Import existing VPC into Terraform state:
   ```powershell
   terraform import module.vpc.aws_vpc.this vpc-12345678
   ```

---

### Problem: "State lock" errors

**Error Message:**
```
Error: Error acquiring the state lock
Lock Info:
  ID:        abc123...
  Operation: OperationTypeApply
  Who:       john@laptop
```

**Cause:** Someone else is running Terraform, or previous run crashed.

**Solution (Local State):**
```powershell
# If you're SURE no one else is running Terraform:
# Delete lock file (local state only)
rm .terraform.tfstate.lock.info
```

**Solution (S3 Backend with DynamoDB):**
```powershell
# Force unlock (use LOCK_ID from error message)
terraform force-unlock abc123...
```

---

### Problem: "Inconsistent state" after crash

**Error Message:**
```
Error: Provider produced inconsistent result after apply
```

**Solution:**
```powershell
# Refresh state from AWS
terraform refresh

# If that fails, manually reconcile:
terraform state list
terraform state show aws_instance.example
# Compare with AWS console, remove if needed:
terraform state rm aws_instance.example
```

---

### Problem: RDS won't delete (deletion protection)

**Error Message:**
```
Error: Error deleting DB Instance: InvalidParameterCombination: Cannot delete protected DB Instance
```

**Solution:**
```powershell
# 1. Edit terraform.tfvars or module call:
deletion_protection = false

# 2. Apply to update RDS
terraform apply

# 3. Now destroy will work
terraform destroy
```

---

### Problem: "No changes" but resources are missing

**Symptom:** `terraform plan` says "No changes", but you can't see resources in AWS console.

**Cause:** State file is out of sync with reality.

**Solution:**
```powershell
# 1. Refresh state from AWS
terraform refresh

# 2. Check what Terraform thinks exists
terraform state list

# 3. If resource is in state but not in AWS:
terraform state rm module.rds[0].aws_db_instance.main

# 4. Re-create from scratch:
terraform apply
```

---

### Helpful Debug Commands

```powershell
# Show detailed logs
$env:TF_LOG="DEBUG"
terraform apply

# Disable logs
Remove-Item Env:\TF_LOG

# Show provider versions
terraform version

# Show all providers used
terraform providers

# Show state as JSON (useful for scripting)
terraform show -json | ConvertFrom-Json

# Graph dependencies (requires Graphviz)
terraform graph | dot -Tpng > graph.png
```

---

## 13. Additional Resources

### Official Documentation
- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

### Project-Specific Docs
- [DEV Environment Operations](../infra/terraform/envs/dev/README.md)
- [PROD Environment Guide](../infra/terraform/envs/prod/README.md)
- [Deployment Scripts Guide](../infra/scripts/README.md)
- [Architecture Overview](./architecture.md)
- [Cost Strategy](./cost-strategy.md)

### AWS CLI References
```powershell
# List EC2 instances
aws ec2 describe-instances --region ap-southeast-1

# List RDS instances
aws rds describe-db-instances --region ap-southeast-1

# List VPCs
aws ec2 describe-vpcs --region ap-southeast-1

# List S3 buckets
aws s3 ls

# Get Cognito User Pools
aws cognito-idp list-user-pools --max-results 10 --region ap-southeast-1
```

---

## Quick Reference Card

### Most Common Commands

```powershell
# 🔍 CHECK (Safe, no changes)
terraform init        # Download providers
terraform validate    # Check syntax
terraform plan        # Preview changes
terraform show        # Show current state

# ✏️ MODIFY (Changes AWS resources)
terraform apply       # Apply changes
terraform destroy     # Delete everything

# 📊 INSPECT (Safe, read-only)
terraform output      # Show outputs
terraform state list  # List resources
terraform state show aws_vpc.this  # Show specific resource

# 🔧 MAINTENANCE
terraform fmt         # Format code
terraform refresh     # Sync state with AWS
```

### Cost Optimization Checklist for DEV

- [ ] Set `enable_rds = false` when not testing database features
- [ ] Set `enable_nat_gateway = false` (use SSM port forwarding instead)
- [ ] Set `enable_alb = false` when not testing load balancing
- [ ] Set `enable_bastion = false` when not accessing RDS
- [ ] Set `enable_ssm_vpc_endpoints = false` (use NAT Gateway if needed)
- [ ] Run `terraform destroy` on weekends/holidays
- [ ] Use `t3.micro` instances (smallest viable size)
- [ ] Set short RDS backup retention (1 day in DEV)

### Pre-PROD Deployment Checklist

- [ ] Test changes in DEV environment first
- [ ] Run `terraform plan` and review ALL changes
- [ ] Check for resource deletions (red `-` in plan)
- [ ] Verify no secrets in Git commits
- [ ] Back up PROD state file
- [ ] Get approval from team lead
- [ ] Have rollback plan ready
- [ ] Monitor CloudWatch logs after deployment
- [ ] Test application functionality
- [ ] Document changes in CHANGELOG

---

**Document Version:** 1.0  
**Last Updated:** February 4, 2026  
**Maintainer:** Platform Engineering Team  
**Questions?** Open an issue in the repository or contact the DevOps team.
