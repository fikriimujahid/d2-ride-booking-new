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
