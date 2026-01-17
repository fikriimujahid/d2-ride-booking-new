# ========================================
# Cognito Module - Input Variables
# ========================================
# Purpose: Define variables for Cognito User Pool and App Client

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ridebooking"
}

variable "domain_name" {
  description = "Domain name for email sender (e.g., d2.fikri.dev)"
  type        = string
}

variable "password_minimum_length" {
  description = "Minimum password length (DEV: 8, PROD: 12+)"
  type        = number
  default     = 8
}

variable "tags" {
  description = "Common tags for all Cognito resources"
  type        = map(string)
  default     = {}
}
