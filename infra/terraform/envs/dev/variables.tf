# ========================================
# DEV Environment - Variables
# ========================================

# ----------------------------------------
# General Configuration
# ----------------------------------------
variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
  default     = "ridebooking"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the DEV environment"
  default     = "ap-southeast-1"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
}

# ----------------------------------------
# VPC Configuration (Phase 2)
# ----------------------------------------
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the DEV VPC"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV public subnet"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV private subnet"
}

variable "availability_zone" {
  type        = string
  description = "Single AZ for DEV (fixed)"
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway (cost toggle)"
  default     = false
}

# ----------------------------------------
# Cognito Configuration (Phase 3)
# ----------------------------------------
variable "domain_name" {
  type        = string
  description = "Domain name for project (e.g., d2.fikri.dev)"
}

variable "cognito_password_min_length" {
  type        = number
  description = "Minimum password length for Cognito (DEV: 8, PROD: 12+)"
  default     = 8
}

# ----------------------------------------
# IAM Configuration (Phase 3)
# ----------------------------------------
variable "secrets_manager_arns" {
  type        = list(string)
  description = "ARNs of Secrets Manager secrets (DB credentials)"
  default     = []
}

