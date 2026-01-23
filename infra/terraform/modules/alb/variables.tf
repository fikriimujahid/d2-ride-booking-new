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

# ------------------------------------------------------------------------------
# CERTIFICATE ARN - Existing SSL certificate (optional)
# ------------------------------------------------------------------------------
# TWO SCENARIOS:
#
# Scenario 1: You have existing certificate (provide this variable)
# - Maybe you created it manually
# - Maybe shared across multiple ALBs
# - Module uses your certificate
# - Faster deployment (no waiting for validation)
#
# Scenario 2: Let module create certificate (leave empty, provide hosted_zone_id)
# - Module creates new certificate
# - Automatically validates via DNS
# - Takes 5-10 minutes for validation
# - Certificate managed by this module
#
# WHY HAVE THIS OPTION?
# - Flexibility: Works with existing certificates
# - Reusability: Can share one cert across multiple ALBs
# - Cost: Certificates are free, but why create duplicates?
# - Control: Some teams prefer centralized cert management
variable "certificate_arn" {
  description = "Optional ACM certificate ARN to use for the ALB HTTPS listener. If empty and hosted_zone_id is provided, the module will request and DNS-validate a certificate for api.<domain_name>."
  type        = string
  default     = ""
}

variable "alb_security_group_id" {
  description = "Security group for the ALB"
  type        = string
}

variable "target_instance_id" {
  description = "Backend EC2 instance ID to register"
  type        = string
}

variable "driver_target_instance_id" {
  description = "Optional: driver-web EC2 instance ID to register (enables host-based routing for driver.<domain_name>)"
  type        = string
  default     = ""
}

variable "enable_driver_web" {
  description = "Whether to enable driver-web resources on the ALB (target group, listener rule, and attachment). Must be a plan-time boolean (do not derive from resource attributes)."
  type        = bool
  default     = false
}

variable "driver_target_port" {
  description = "Driver-web listener port"
  type        = number
  default     = 3000
}

variable "driver_health_check_path" {
  description = "Health check path for driver web"
  type        = string
  default     = "/"
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
