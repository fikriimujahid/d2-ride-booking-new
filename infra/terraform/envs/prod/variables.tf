variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name for naming"
}

variable "aws_region" {
  type        = string
  description = "AWS region for PROD"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------
variable "domain_name" {
  type        = string
  description = "Root domain (e.g., fikri.dev). ALB hosts api.d2.<domain> and driver.d2.<domain>."
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone id for domain_name"
}

# -----------------------------------------------------------------------------
# NETWORKING (PROD-GRADE)
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the PROD VPC (must not overlap DEV)"
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs for multi-AZ resilience (>=2)"

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "PROD requires at least 2 availability_zones."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs (one per AZ). Used for ALB + NAT."

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "PROD requires at least 2 public_subnet_cidrs (one per AZ)."
  }
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "Private app subnet CIDRs (one per AZ). Used for ASGs."

  validation {
    condition     = length(var.private_app_subnet_cidrs) >= 2
    error_message = "PROD requires at least 2 private_app_subnet_cidrs (one per AZ)."
  }
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "Private DB subnet CIDRs (one per AZ). Used for RDS."

  validation {
    condition     = length(var.private_db_subnet_cidrs) >= 2
    error_message = "PROD requires at least 2 private_db_subnet_cidrs (one per AZ)."
  }
}

variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Enable SSM interface endpoints (defense-in-depth; reduces dependency on NAT)."
}

# -----------------------------------------------------------------------------
# BASTION (PROD)
# -----------------------------------------------------------------------------
variable "enable_bastion" {
  type        = bool
  description = "Enable a bastion host (recommended access via SSM port forwarding)"
  default     = false
}

variable "bastion_instance_type" {
  type        = string
  description = "Bastion EC2 instance type"
  default     = "t3.micro"
}

variable "bastion_enable_ssh" {
  type        = bool
  description = "Enable inbound SSH (22) to bastion (prefer SSM if possible)"
  default     = false
}

variable "bastion_ssh_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH to the bastion when bastion_enable_ssh=true"
  default     = []
}

variable "bastion_key_name" {
  type        = string
  description = "Optional EC2 key pair name for bastion SSH"
  default     = null
}

# -----------------------------------------------------------------------------
# COMPUTE (ASG)
# -----------------------------------------------------------------------------
variable "asg_health_check_grace_period_seconds" {
  type        = number
  description = "ASG grace period before health checks apply. Increase for initial deployments where the app is deployed after boot (via SSM)."
  default     = 1800
}

variable "asg_health_check_type_override" {
  type        = string
  description = "Optional override for ASG health check type during initial deployment. Use 'EC2' to stop ELB-driven replacements until apps are deployed; then switch back to '' (or 'ELB')."
  default     = ""

  validation {
    condition     = var.asg_health_check_type_override == "" || var.asg_health_check_type_override == "EC2" || var.asg_health_check_type_override == "ELB"
    error_message = "asg_health_check_type_override must be one of: '', 'EC2', 'ELB'."
  }
}

variable "backend_instance_type" {
  type        = string
  description = "Backend API EC2 instance type"
}

variable "backend_root_volume_size" {
  type        = number
  description = "Backend API root volume size (GB)"
}

variable "backend_asg_min" {
  type        = number
  description = "Backend API ASG min"
}

variable "backend_asg_desired" {
  type        = number
  description = "Backend API ASG desired"
}

variable "backend_asg_max" {
  type        = number
  description = "Backend API ASG max"
}

variable "driver_instance_type" {
  type        = string
  description = "Web Driver EC2 instance type"
}

variable "driver_root_volume_size" {
  type        = number
  description = "Web Driver root volume size (GB)"
}

variable "driver_asg_min" {
  type        = number
  description = "Web Driver ASG min"
}

variable "driver_asg_desired" {
  type        = number
  description = "Web Driver ASG desired"
}

variable "driver_asg_max" {
  type        = number
  description = "Web Driver ASG max"
}

# -----------------------------------------------------------------------------
# DATABASE (RDS MySQL)
# -----------------------------------------------------------------------------
variable "enable_rds" {
  type        = bool
  description = "Enable RDS MySQL (PROD should keep true)"
}

variable "db_name" {
  type        = string
  description = "Database name"
}

variable "db_master_username" {
  type        = string
  description = "RDS master username (admin only; app uses IAM DB auth)"
}

variable "rds_db_user" {
  type        = string
  description = "Application DB user (IAM auth)"
}

variable "rds_instance_class" {
  type        = string
  description = "RDS instance class"
}

variable "rds_allocated_storage" {
  type        = number
  description = "Initial RDS storage (GB)"
}

variable "rds_engine_version" {
  type        = string
  description = "MySQL engine version"
}

variable "rds_backup_retention_days" {
  type        = number
  description = "Backup retention days (PROD should be > 1)"
}

# -----------------------------------------------------------------------------
# AUTH (Cognito)
# -----------------------------------------------------------------------------
variable "cognito_password_min_length" {
  type        = number
  description = "Minimum password length (PROD: 12+)"
}

# -----------------------------------------------------------------------------
# OBSERVABILITY (PROD stricter)
# -----------------------------------------------------------------------------
variable "enable_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms"
}

variable "alarm_email" {
  type        = string
  description = "Optional email for alarm notifications"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention (PROD should be longer than DEV)"
}

# -----------------------------------------------------------------------------
# CI/CD (GitHub Actions OIDC) - PROD only
# -----------------------------------------------------------------------------
variable "enable_github_actions_deploy_role" {
  type        = bool
  description = "If true, create a dedicated least-privilege GitHub Actions deploy role for PROD (recommended)."
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN of the GitHub OIDC provider in this AWS account (created by bootstrap). Required when enable_github_actions_deploy_role=true."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in format 'owner/repo'. Used to restrict the PROD deploy role trust policy. Required when enable_github_actions_deploy_role=true."
}
