# ========================================
# DEV Environment - Phase 3
# ========================================
# Phase 1: Monorepo CI/CD ✓
# Phase 2: VPC, Subnets, IGW, NAT ✓
# Phase 3: IAM, Cognito, Security Groups ← YOU ARE HERE
# Phase 4: ALB, EC2, RDS (upcoming)

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------------------
# VPC Module (Phase 2)
# ----------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone

  enable_nat_gateway = var.enable_nat_gateway
  tags               = var.tags
}

# ----------------------------------------
# IAM Module (Phase 3)
# ----------------------------------------
# WHY: Create least-privilege IAM roles for EC2 instances
module "iam" {
  source = "../../modules/iam"

  environment  = var.environment
  project_name = var.project_name

  # WHY: Backend needs access to DB credentials in Secrets Manager
  # NOTE: Secrets Manager ARNs will be populated in Phase 4 when RDS is created
  secrets_manager_arns = var.secrets_manager_arns

  tags = var.tags
}

# ----------------------------------------
# Cognito Module (Phase 3)
# ----------------------------------------
# WHY: JWT-based authentication for ADMIN, DRIVER, PASSENGER roles
module "cognito" {
  source = "../../modules/cognito"

  environment  = var.environment
  project_name = var.project_name
  domain_name  = var.domain_name

  password_minimum_length = var.cognito_password_min_length

  tags = var.tags
}

# ----------------------------------------
# Security Groups Module (Phase 3)
# ----------------------------------------
# WHY: Network isolation with least-privilege rules
module "security_groups" {
  source = "../../modules/security-groups"

  environment  = var.environment
  project_name = var.project_name

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr

  tags = var.tags
}
