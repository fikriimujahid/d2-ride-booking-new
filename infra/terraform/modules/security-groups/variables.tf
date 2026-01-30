# ========================================
# REQUIRED VARIABLES (must be provided)
# ========================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for internal traffic rules)"
  type        = string
}

variable "tags" {
  description = "Common tags for all security group resources"
  type        = map(string)
  default     = {}
}

variable "rds_security_group_id" {
  description = "Security group ID of the RDS instance (from RDS module)"
  type        = string
  default     = "" # Empty string when RDS not yet created
}

variable "enable_alb" {
  description = "Whether ALB is enabled; when false, allow direct DEV HTTP"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Whether NAT gateway is enabled; when true, allow outbound HTTPS to the internet (via NAT)"
  type        = bool
  default     = false
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group ID attached to interface VPC endpoints (e.g., SSM endpoints). When set, outbound HTTPS can be restricted to this SG instead of 0.0.0.0/0."
  type        = string
  default     = null
}