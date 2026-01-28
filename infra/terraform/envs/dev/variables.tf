# ================================================================================
# GENERAL CONFIGURATION VARIABLES
# ================================================================================

# --------------------------------------------------------------------------------
# ENVIRONMENT NAME
# --------------------------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

# --------------------------------------------------------------------------------
# PROJECT NAME
# --------------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Project name for resource naming"
  default     = "ridebooking"
}

# --------------------------------------------------------------------------------
# AWS REGION
# --------------------------------------------------------------------------------
variable "aws_region" {
  type        = string
  description = "AWS region for the DEV environment"
  default     = "ap-southeast-1"
}

# --------------------------------------------------------------------------------
# RESOURCE TAGS
# --------------------------------------------------------------------------------
variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
}

# ================================================================================
# VPC CONFIGURATION VARIABLES (PHASE 2)
# ================================================================================
# These variables define the network layout for your infrastructure

# --------------------------------------------------------------------------------
# VPC CIDR BLOCK
# --------------------------------------------------------------------------------
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the DEV VPC"
}

# --------------------------------------------------------------------------------
# PUBLIC SUBNET CIDR
# --------------------------------------------------------------------------------
variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV public subnet"
}

variable "public_subnet_cidr_secondary" {
  type        = string
  description = "CIDR block for the DEV secondary public subnet (for ALB multi-AZ)"
}

# --------------------------------------------------------------------------------
# PRIVATE SUBNET CIDR
# --------------------------------------------------------------------------------
variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV private subnet"
}

# --------------------------------------------------------------------------------
# SECONDARY PRIVATE SUBNET CIDR
# --------------------------------------------------------------------------------
variable "private_subnet_cidr_secondary" {
  type        = string
  description = "CIDR block for the DEV secondary private subnet"
}

# --------------------------------------------------------------------------------
# AVAILABILITY ZONE
# --------------------------------------------------------------------------------
variable "availability_zone" {
  type        = string
  description = "Single AZ for DEV (fixed)"
}

# --------------------------------------------------------------------------------
# SECONDARY AVAILABILITY ZONE
# --------------------------------------------------------------------------------
variable "availability_zone_secondary" {
  type        = string
  description = "Secondary AZ for DEV private subnet"
}

# --------------------------------------------------------------------------------
# NAT GATEWAY TOGGLE
# --------------------------------------------------------------------------------
variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway (cost toggle)"
  default     = false
}

# Optional ALB toggle (default off to avoid hourly charges in DEV)
variable "enable_alb" {
  type        = bool
  description = "Enable internet-facing ALB for backend"
  default     = false
}

variable "enable_ec2_backend" {
  type        = bool
  description = "Enable internet-facing EC2 backend"
  default     = false
}

# ================================================================================
# FRONTENDS (PHASE 6) - COST-AWARE TOGGLES
# ================================================================================
variable "enable_web_admin" {
  type        = bool
  description = "Enable web-admin static site bucket (S3 website hosting)"
  default     = true
}

variable "enable_web_passenger" {
  type        = bool
  description = "Enable web-passenger static site bucket (S3 website hosting)"
  default     = true
}

variable "enable_web_driver" {
  type        = bool
  description = "Enable web-driver Next.js app on EC2 (SSR/realtime ready)"
  default     = true
}

variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Enable Interface VPC endpoints for SSM (ssm/ec2messages/ssmmessages) so private instances can use Session Manager without NAT"
  default     = true
}

# ================================================================================
# BASTION SETTINGS (OPTIONAL)
# ================================================================================
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

# ================================================================================
# COGNITO CONFIGURATION VARIABLES
# ================================================================================
# Authentication and user management settings

# --------------------------------------------------------------------------------
# DOMAIN NAME
# --------------------------------------------------------------------------------
variable "domain_name" {
  type        = string
  description = "Domain name for project (e.g., d2.fikri.dev)"
}

variable "route53_zone_id" {
  type        = string
  description = "Hosted zone ID for Route53 (blank to skip alias creation)"
  default     = ""
}

variable "s3_website_zone_id" {
  type        = string
  description = "Optional: S3 website hosted zone id for this region (enables Route53 A-alias to S3 website endpoints). If blank, we fall back to CNAME for admin/passenger (valid for subdomains)."
  default     = ""
}

# --------------------------------------------------------------------------------
# COGNITO PASSWORD MINIMUM LENGTH
# --------------------------------------------------------------------------------
variable "cognito_password_min_length" {
  type        = number
  description = "Minimum password length for Cognito (DEV: 8, PROD: 12+)"
  default     = 8
}

# ================================================================================
# IAM CONFIGURATION VARIABLES (PHASE 3)
# ================================================================================
# Variables for IAM roles and permissions

# --------------------------------------------------------------------------------
# SECRETS MANAGER ARNs
# --------------------------------------------------------------------------------
variable "secrets_manager_arns" {
  type        = list(string)
  description = "ARNs of Secrets Manager secrets (DB credentials)"
  default     = []
}

# --------------------------------------------------------------------------------
# RDS DATABASE USER (FOR APPLICATION IAM AUTHENTICATION)
# --------------------------------------------------------------------------------
variable "rds_db_user" {
  type        = string
  description = "Database username for application IAM authentication"
  default     = "app_user"
}

# ================================================================================
# RDS CONFIGURATION VARIABLES (PHASE 4)
# ================================================================================
# MySQL database instance settings

# --------------------------------------------------------------------------------
# ENABLE RDS TOGGLE
# --------------------------------------------------------------------------------
variable "enable_rds" {
  type        = bool
  description = "Enable RDS MySQL instance (cost toggle)"
  default     = true
}

# --------------------------------------------------------------------------------
# DATABASE NAME
# --------------------------------------------------------------------------------
variable "db_name" {
  type        = string
  description = "Database name"
  default     = "ridebooking"
}

# --------------------------------------------------------------------------------
# DATABASE MASTER USERNAME
# --------------------------------------------------------------------------------
variable "db_master_username" {
  type        = string
  description = "Master username for RDS (admin only - NOT for application use)"
  default     = "admin"
}

# --------------------------------------------------------------------------------
# RDS INSTANCE CLASS
# --------------------------------------------------------------------------------
variable "rds_instance_class" {
  type        = string
  description = "RDS instance class (db.t3.micro for DEV cost optimization)"
  default     = "db.t3.micro"
}

# --------------------------------------------------------------------------------
# RDS ALLOCATED STORAGE
# --------------------------------------------------------------------------------
variable "rds_allocated_storage" {
  type        = number
  description = "Initial allocated storage in GB (keep low for DEV, autoscaling enabled)"
  default     = 20
}

# --------------------------------------------------------------------------------
# RDS ENGINE VERSION
# --------------------------------------------------------------------------------
variable "rds_engine_version" {
  type        = string
  description = "MySQL engine version"
  default     = "8.0"
}

# ================================================================================
# BACKEND EC2 SETTINGS (PHASE 5)
# ================================================================================
variable "backend_instance_type" {
  type        = string
  description = "Backend EC2 instance type (keep micro for DEV cost)"
  default     = "t3.micro"
}

variable "backend_root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 16
}

# ================================================================================
# DRIVER WEB EC2 SETTINGS (PHASE 6)
# ================================================================================
variable "driver_instance_type" {
  type        = string
  description = "Driver web EC2 instance type (keep micro for DEV cost)"
  default     = "t3.micro"
}

variable "driver_root_volume_size" {
  type        = number
  description = "Driver web root EBS volume size in GB"
  default     = 16
}

# ================================================================================
# CLOUDWATCH OBSERVABILITY SETTINGS (PHASE 7)
# ================================================================================

# --------------------------------------------------------------------------------
# ENABLE CLOUDWATCH ALARMS TOGGLE
# --------------------------------------------------------------------------------
variable "enable_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms. Set to false during demos, load tests, or when you need silence."
  default     = false
}

# --------------------------------------------------------------------------------
# LOG RETENTION PERIOD
# --------------------------------------------------------------------------------
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days. DEV default: 7 days (cost control). PROD would use 30-90 days."
  default     = 7
}

# --------------------------------------------------------------------------------
# ALARM NOTIFICATION EMAIL
# --------------------------------------------------------------------------------
variable "alarm_email" {
  type        = string
  description = "Email address for CloudWatch alarm notifications. Leave empty to skip email subscription. Use team distribution list instead of personal email to avoid spam."
  default     = ""
}
