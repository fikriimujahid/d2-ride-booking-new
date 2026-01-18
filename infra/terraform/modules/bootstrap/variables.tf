variable "project" {
  description = "Project name used to prefix all resource names for easy identification"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider. Enables GitHub Actions to authenticate with AWS without storing credentials."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo'. Used to restrict IAM role access to specific repository."
  type        = string

  # validation {
  #   condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
  #   error_message = "github_repo must be in format 'owner/repository'"
  # }
}