variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name for naming/tagging"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used to make bucket name globally unique)"
  type        = string
}

variable "force_destroy" {
  description = "Whether to force-destroy the bucket even if it contains objects (recommended true for dev)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
