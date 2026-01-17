# ========================================
# Security Groups Module - Input Variables
# ========================================
# Purpose: Define variables for network security groups

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ridebooking"
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
