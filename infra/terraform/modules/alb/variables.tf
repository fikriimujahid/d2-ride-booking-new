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

variable "public_subnet_ids" {
  description = "Public subnet IDs spanning at least two AZs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the ALB"
  type        = string
}

variable "target_instance_id" {
  description = "Backend EC2 instance ID to register"
  type        = string
}

variable "target_port" {
  description = "Backend listener port"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path for backend"
  type        = string
  default     = "/health"
}

variable "domain_name" {
  description = "Base domain (e.g., d2.fikri.dev)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID (blank to skip record)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
