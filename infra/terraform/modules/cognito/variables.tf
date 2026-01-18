variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  # No default = REQUIRED (you must provide this value)
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ridebooking" # Default value if not provided
}

variable "domain_name" {
  description = "Domain name for email sender (e.g., d2.fikri.dev)"
  type        = string
  # No default = REQUIRED (you must provide this value)
}

variable "password_minimum_length" {
  description = "Minimum password length (DEV: 8, PROD: 12+)"
  type        = number
  default     = 8 # Default for development (override for prod!)
}

variable "tags" {
  description = "Common tags for all Cognito resources"
  type        = map(string)
  default     = {} # Empty map = no common tags unless provided
}
