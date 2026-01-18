# ==============================================================================
# TERRAFORM CONFIGURATION BLOCK
# ==============================================================================
#
# 🔍 WHAT IS THIS BLOCK?
# This is metadata about Terraform itself - NOT about AWS resources.
# It tells Terraform:
# - What version of Terraform is needed
# - What "providers" (plugins) to download
# - What versions of those providers to use
#
# 💡 WHAT IS A "PROVIDER"?
# A provider is like a driver or plugin that lets Terraform talk to a service.
# Examples:
# - AWS provider → Talk to Amazon Web Services
# - Azure provider → Talk to Microsoft Azure
# - GitHub provider → Talk to GitHub
#
# 🎯 WHY DO WE SPECIFY VERSIONS?
# To ensure consistency! If everyone uses different versions:
# - Your code might work on your machine but not on CI/CD
# - Updates could introduce breaking changes
# - Team members might get different results
#
# ⚠️ ONLY EDIT THIS IF:
# - You need to upgrade Terraform version
# - You need to upgrade provider versions
# - You're adding a new provider (like GitHub provider)
#
terraform {
  required_version = ">= 1.0"

  # REQUIRED PROVIDERS
  # List of providers (plugins) this configuration needs
  required_providers {
    # ☁️ AWS PROVIDER
    # This is THE most important provider for this project!
    # It lets Terraform create/manage AWS resources.
    aws = {
      # Where to download the provider from
      source  = "hashicorp/aws"
      
      # VERSION CONSTRAINT: Which version of the AWS provider?
      version = "~> 5.0"
    }
  }
}


# ==============================================================================
# AWS PROVIDER CONFIGURATION
# ==============================================================================
# WHAT IS A PROVIDER CONFIGURATION?
# After telling Terraform to download the AWS provider (above), we need to
# CONFIGURE it - tell it HOW to connect to AWS.
provider "aws" {
  region = var.aws_region
}


# ==============================================================================
# GITHUB OIDC PROVIDER - COMMENTED OUT (ALREADY EXISTS)
# ==============================================================================
# ⚠️ WARNING:
# If you uncomment and run this when the provider already exists,
# you'll get an error: "Resource already exists"
#
# resource "aws_iam_openid_connect_provider" "github" {
#   # URL: The OIDC provider's address
#   # This is GitHub's official OIDC endpoint (never changes)
#   url = "https://token.actions.githubusercontent.com"
#
#   # CLIENT_ID_LIST: Who can request authentication?
#   # "sts.amazonaws.com" = AWS Security Token Service
#   # This means "GitHub can request temporary AWS credentials from STS"
#   client_id_list = [
#     "sts.amazonaws.com"
#   ]
#
#   # THUMBPRINT_LIST: SSL certificate fingerprints
#   # 
#   # WHAT ARE THUMBPRINTS?
#   # Like fingerprints for websites - they verify the SSL certificate is real.
#   # AWS uses these to ensure it's really talking to GitHub, not a fake site.
#   #
#   # THESE ARE GITHUB'S OFFICIAL THUMBPRINTS:
#   # GitHub publishes these publicly. They change rarely (when GitHub
#   # renews their SSL certificates).
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1", # GitHub's primary thumbprint
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"  # GitHub's secondary thumbprint
#   ]
#
#   tags = {
#     project    = var.project  # Your project name
#     managed_by = "terraform"  # Indicates IaC management
#   }
# }
#

# ==============================================================================
# GITHUB OIDC PROVIDER - DATA SOURCE (REFERENCE EXISTING)
# ==============================================================================
#
# WHAT IS A "DATA SOURCE"?
# A data source is like asking AWS "tell me about something that already exists."
# We're NOT creating anything new here - just looking up existing information.
data "aws_iam_openid_connect_provider" "github" {
  # URL: The OIDC provider to look up
  # This is GitHub's official OIDC endpoint
  # AWS will search for an OIDC provider with this exact URL
  #
  # THIS MUST MATCH EXACTLY:
  # If the provider was created with a slightly different URL
  # (e.g., with a trailing slash), this lookup will fail!
  url = "https://token.actions.githubusercontent.com"
}


# ==============================================================================
# BOOTSTRAP MODULE - CALLING THE REUSABLE MODULE
# ==============================================================================
module "bootstrap" {
  source = "../../modules/bootstrap"

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # MODULE INPUTS: Values we're passing to the module
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  project = var.project

  # GITHUB_OIDC_PROVIDER_ARN: The OIDC provider's unique identifier
  # DEPENDENCY:
  # Terraform automatically understands that this module depends on the
  # data source. It will:
  # 1. First: Look up the OIDC provider (data source)
  # 2. Then: Pass the ARN to the module
  # 3. Finally: Create the IAM role with that ARN
  #
  # WHAT IF THE DATA SOURCE FAILS?
  # If the OIDC provider doesn't exist, the data source fails, and
  # Terraform stops before even trying to create the module resources.
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  github_repo = var.github_repo
}

output "github_actions_deploy_role_arn" {
  description = "ARN of the github_actions_deploy_role"
  value = module.bootstrap.github_actions_deploy_role_arn
}