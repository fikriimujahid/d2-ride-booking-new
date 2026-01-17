# ========================================
# DEV Environment - Terraform Variables
# ========================================
# Phase 3: IAM, Cognito, Security Groups

# ----------------------------------------
# General Configuration
# ----------------------------------------
environment  = "dev"
project_name = "d2-ride-booking"

# ----------------------------------------
# AWS Configuration
# ----------------------------------------
aws_region        = "ap-southeast-1"
availability_zone = "ap-southeast-1a"

# ----------------------------------------
# VPC Configuration (Phase 2)
# ----------------------------------------
vpc_cidr            = "10.20.0.0/16"
public_subnet_cidr  = "10.20.1.0/24"
private_subnet_cidr = "10.20.11.0/24"

# Cost toggle: keep NAT off by default
enable_nat_gateway = false

# ----------------------------------------
# Cognito Configuration (Phase 3)
# ----------------------------------------
domain_name                 = "d2.fikri.dev"
cognito_password_min_length = 8 # DEV: 8 chars (PROD should use 12+)

# ----------------------------------------
# IAM Configuration (Phase 3)
# ----------------------------------------
# NOTE: Secrets Manager ARNs will be added in Phase 4 when RDS is created
secrets_manager_arns = []

# ----------------------------------------
# Tags
# ----------------------------------------
tags = {
  Environment = "dev"
  Project     = "d2-ride-booking"
  ManagedBy   = "terraform"
  Domain      = "d2.fikri.dev"
}
