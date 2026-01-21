# ========================================
# CORE VARIABLES (ALWAYS REQUIRED)
# ========================================
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ridebooking"
}
variable "secrets_manager_arns" {
  description = "ARNs of Secrets Manager secrets (DB credentials only)"
  type        = list(string)
  default     = []
}

# ========================================
# RDS IAM DATABASE AUTHENTICATION VARIABLES
# ========================================
variable "rds_resource_id" {
  description = "RDS resource ID for IAM database authentication (format: db-XXXXX)"
  type        = string
  default     = ""
}
variable "rds_db_user" {
  description = "Database username for application IAM authentication (e.g., app_user)"
  type        = string
  default     = "app_user"
}

variable "aws_region" {
  description = "AWS region for RDS IAM authentication policy"
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS account ID for RDS IAM authentication policy"
  type        = string
  default     = ""
}

# ========================================
# DEPLOYMENT ARTIFACTS (S3)
# ========================================
variable "deployment_artifacts_bucket_arn" {
  description = "Optional S3 bucket ARN that holds deployment artifacts (EC2 needs GetObject for SSM-driven deploys)"
  type        = string
  default     = ""
}

# ========================================
# TAGGING VARIABLES
# ========================================
variable "tags" {
  description = "Common tags for all IAM resources"
  type        = map(string)
  default     = {}
}

