# ========================================
# IAM Module - Input Variables
# ========================================
# Purpose: Define variables for IAM roles and policies
# Environment: DEV-scoped (will scale to PROD)

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

variable "tags" {
  description = "Common tags for all IAM resources"
  type        = map(string)
  default     = {}
}
