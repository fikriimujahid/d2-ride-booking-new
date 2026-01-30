variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "service_name" {
  type        = string
  description = "Service name for tagging (e.g., backend-api, web-driver)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets where instances should run (should span >=2 AZs in PROD)"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups for instances"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name to attach"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root volume size in GB"
  default     = 30
}

variable "app_port" {
  type        = number
  description = "App port exposed behind ALB"
}

variable "ami_id" {
  type        = string
  description = "Optional AMI ID override. Leave empty to use latest Amazon Linux 2023."
  default     = ""
}

variable "min_size" {
  type        = number
  description = "ASG minimum capacity"
}

variable "max_size" {
  type        = number
  description = "ASG maximum capacity"
}

variable "desired_capacity" {
  type        = number
  description = "ASG desired capacity"
}

variable "target_group_arns" {
  type        = list(string)
  description = "Target group ARNs to register instances into (ALB)"
  default     = []
}

variable "health_check_grace_period_seconds" {
  type        = number
  description = "How long ASG waits after instance launch before considering health checks (use longer when app deployment happens after boot)."
  default     = 120
}

variable "health_check_type_override" {
  type        = string
  description = "Optional override for ASG health_check_type. Set to \"EC2\" to avoid ELB-driven replacements during initial deploy; set to \"ELB\" for app-aware healing; empty string uses default behavior (ELB when target groups are attached)."
  default     = ""

  validation {
    condition     = var.health_check_type_override == "" || var.health_check_type_override == "EC2" || var.health_check_type_override == "ELB"
    error_message = "health_check_type_override must be one of: '', 'EC2', 'ELB'."
  }
}

variable "enable_instance_refresh" {
  type        = bool
  description = "Enable rolling instance refresh on launch template change (safe + reversible)"
  default     = true
}

variable "instance_refresh_min_healthy_percentage" {
  type        = number
  description = "Minimum healthy percentage during instance refresh"
  default     = 90
}

variable "instance_warmup_seconds" {
  type        = number
  description = "Warmup time for new instances during rolling refresh"
  default     = 180
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
