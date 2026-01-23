variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name (used in bucket naming/tagging)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used to make bucket name globally unique)"
  type        = string
}

variable "site_name" {
  description = "Logical site name (e.g., web-admin, web-passenger)"
  type        = string
}

variable "force_destroy" {
  description = "DEV-friendly: allow destroy even if objects exist"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
