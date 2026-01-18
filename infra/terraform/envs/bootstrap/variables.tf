variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,31}$", var.project))
    error_message = "Project name must start with lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 2-32 characters."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created (e.g., us-east-1, ap-southeast-1)"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "Must be a valid AWS region format (e.g., us-east-1, ap-southeast-1)."
  }
}

variable "terraform_state_bucket" {
  description = "Name of the S3 bucket for storing Terraform state (must exist before running terraform init)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.terraform_state_bucket))
    error_message = "Bucket name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' (e.g., 'fikriimujahid/d2-ride-booking-new') - used for OIDC authentication"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]+/[a-zA-Z0-9-_.]+$", var.github_repo))
    error_message = "GitHub repo must be in format 'owner/repo' with valid GitHub username and repository name."
  }
}