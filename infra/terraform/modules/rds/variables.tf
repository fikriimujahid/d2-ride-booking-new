# ================================================================================
# SECTION 1: BASIC IDENTIFICATION VARIABLES
# ================================================================================

variable "environment" {
  description = "Environment name (e.g., dev, prod, staging)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming (used in all resource names)"
  type        = string
}

# ================================================================================
# SECTION 2: NETWORK CONFIGURATION VARIABLES
# ================================================================================
variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS subnet group (must be in different AZs)"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for internal traffic rules)"
  type        = string
}

# ================================================================================
# SECTION 3: RDS DATABASE CONFIGURATION VARIABLES
# ================================================================================
variable "db_name" {
  description = "Database name (created automatically on RDS startup)"
  type        = string
  default     = "ridebooking"
}

variable "db_username" {
  description = "Master username for RDS (admin only - NOT for app use)"
  type        = string
  default     = "admin"
}

variable "instance_class" {
  description = "RDS instance class (db.t3.micro for DEV, db.m5.large for PROD)"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB (will autoscale)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB (RDS grows automatically)"
  type        = number
  default     = 100
}

variable "engine_version" {
  description = "MySQL engine version (8.0 recommended, only change if needed)"
  type        = string
  default     = "8.0"
}

variable "backup_retention_period" {
  description = "Backup retention period in days (1 for DEV, 7+ for PROD)"
  type        = number
  default     = 1
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment (false for DEV, true for PROD)"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection (false for DEV, true for PROD)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion (true for DEV, false for PROD)"
  type        = bool
  default     = true
}

variable "iam_database_authentication_enabled" {
  description = "Enable IAM database authentication (MUST be true - required for security)"
  type        = bool
  default     = true
}

# ================================================================================
# SECTION 4: SECURITY CONFIGURATION
# ================================================================================
variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to RDS (backend API)"
  type        = list(string)
}

# ================================================================================
# SECTION 5: TAGS FOR ORGANIZATION
# ================================================================================
variable "tags" {
  description = "Additional tags for RDS resources (for organization and cost tracking)"
  type        = map(string)
  default     = {}
}
