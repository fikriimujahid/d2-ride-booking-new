variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (used for limited egress)"
  type        = string
}

variable "backend_api_port" {
  description = "Backend API port"
  type        = number
  default     = 3000
}

variable "driver_web_port" {
  description = "Driver web port"
  type        = number
  default     = 3001
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group ID attached to interface VPC endpoints (e.g., SSM endpoints). When set, outbound HTTPS can be restricted to this SG instead of 0.0.0.0/0."
  type        = string
  default     = null
}
