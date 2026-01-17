# ==============================================================================
# BOOTSTRAP ENVIRONMENT - Infrastructure Foundation Setup
# ==============================================================================

# ------------------------------------------------------------------------------
# Terraform Configuration Block
# ------------------------------------------------------------------------------
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Official AWS provider from HashiCorp
      version = "~> 5.0"        # Pin to major version 5
    }
  }
}

# ------------------------------------------------------------------------------
# AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region # From terraform.tfvars
}

# ------------------------------------------------------------------------------
# GitHub OIDC Provider for Secure CI/CD Authentication
# ------------------------------------------------------------------------------
# resource "aws_iam_openid_connect_provider" "github" {
#   # The URL where AWS will verify GitHub's identity
#   url = "https://token.actions.githubusercontent.com"

#   # client_id_list: Who can request tokens from this provider
#   # "sts.amazonaws.com" means AWS Security Token Service (temporary credentials)
#   client_id_list = [
#     "sts.amazonaws.com"
#   ]

#   # thumbprint_list: SSL certificate fingerprints to verify GitHub's identity
#   # These are GitHub's official thumbprints (updated by GitHub if certificates change)
#   # SECURITY: These prevent man-in-the-middle attacks
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1", # GitHub's primary thumbprint // pragma: allowlist secret 
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"  # GitHub's secondary thumbprint // pragma: allowlist secret 
#   ]

#   # Tags help identify and organize resources in AWS console
#   tags = {
#     project    = var.project # e.g., "personal-note"
#     managed_by = "terraform" # Shows this was created by infrastructure-as-code
#   }
# }

# ------------------------------------------------------------------------------
# GitHub OIDC Provider (Data Source for Existing Provider)
# ------------------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ------------------------------------------------------------------------------
# IAM Roles Module - Creates Roles for Different Environments
# ------------------------------------------------------------------------------
module "bootstrap" {
  # Path to the module directory (relative to this file)
  source = "../../modules/bootstrap"

  # Pass variables to the module
  # The module uses these to customize the roles it creates
  project = var.project

  # ARN of the GitHub OIDC provider we created above
  # Allows the roles to trust GitHub Actions
  # DEPENDENCY: This creates an implicit dependency on the OIDC provider
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  # GitHub repository in format "owner/repo"
  # Used to restrict which repo can assume these roles
  # SECURITY: Only this specific repo can use these roles
  github_repo = var.github_repo
}

# ==============================================================================
# OUTPUTS - Values to Display After Apply
# ==============================================================================
output "github_actions_deploy_role_arn" {
  description = "ARN of the github_actions_deploy_role"
  value       = module.bootstrap.github_actions_deploy_role_arn
}