# ==============================================================================
# IAM ROLES MODULE - INPUT VARIABLES
# ==============================================================================

# ------------------------------------------------------------------------------
# PROJECT IDENTIFICATION
# ------------------------------------------------------------------------------
variable "project" {
  description = "Project name used to prefix all resource names for easy identification"
  type        = string
}

# ------------------------------------------------------------------------------
# GITHUB ACTIONS INTEGRATION (OIDC)
# ------------------------------------------------------------------------------
variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider. Enables GitHub Actions to authenticate with AWS without storing credentials."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo'. Used to restrict IAM role access to specific repository."
  type        = string
}
