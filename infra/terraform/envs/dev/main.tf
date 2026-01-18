# ================================================================================
# DEVELOPMENT ENVIRONMENT - MAIN CONFIGURATION
# ================================================================================
#
# PURPOSE:
# This file defines the ENTIRE infrastructure for the DEV environment of our
# ride-booking application. Think of this as the "master blueprint" that tells
# Terraform exactly what AWS resources to create and how they should connect.
#
# WHAT GETS CREATED:
# - VPC (Virtual Private Cloud): Your own isolated network in AWS
# - Subnets: Subdivisions of the VPC (public for internet-facing, private for databases)
# - Security Groups: Firewall rules controlling who can talk to what
# - IAM Roles: Permission sets for your applications to access AWS services
# - Cognito: User authentication system (login/signup for admin, drivers, passengers)
# - RDS Database: MySQL database with secure IAM-based authentication
# ================================================================================

# ================================================================================
# TERRAFORM CONFIGURATION BLOCK
# ================================================================================
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    # -------------------------------------------------------------------------
    # AWS PROVIDER
    # -------------------------------------------------------------------------
    aws = {
      # WHERE TO DOWNLOAD: HashiCorp's official registry
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # -------------------------------------------------------------------------
    # RANDOM PROVIDER
    # -------------------------------------------------------------------------
    # This plugin generates random values (passwords, IDs, pet names)
    # WHY NEEDED: RDS module might use it for unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ================================================================================
# AWS PROVIDER CONFIGURATION
# ================================================================================
provider "aws" {
  region = var.aws_region
}

# ================================================================================
# DATA SOURCES - FETCHING INFORMATION FROM AWS
# ================================================================================
data "aws_caller_identity" "current" {}

# --------------------------------------------------------------------------------
# CURRENT AWS REGION
# --------------------------------------------------------------------------------
data "aws_region" "current" {}

# ================================================================================
# VPC MODULE - YOUR PRIVATE NETWORK IN AWS
# ================================================================================
# WHAT GETS CREATED BY THIS MODULE:
# - VPC: The overall network (like the entire apartment)
# - Public Subnet: For resources that need internet access (like a balcony)
# - Private Subnet: For resources hidden from internet (like a bedroom)
# - Internet Gateway: Door to the internet (for public subnet)
# - NAT Gateway: Allows private subnet to access internet outbound (optional, costs money)
# - Route Tables: Rules for how traffic flows between subnets and internet
module "vpc" {
  source = "../../modules/vpc"

  # CIDR = Classless Inter-Domain Routing. It's a way to define IP address ranges.
  vpc_cidr = var.vpc_cidr

  # A section of your VPC where resources CAN have public IP addresses and
  # can be accessed from the internet (with proper security group rules)
  public_subnet_cidr = var.public_subnet_cidr

  # A section of your VPC where resources CANNOT be accessed from internet.
  # Resources here can only talk to other resources in the VPC (or through NAT)
  private_subnet_cidr = var.private_subnet_cidr

  # Optional secondary private subnet for RDS subnet group AZ coverage
  private_subnet_cidr_secondary = var.private_subnet_cidr_secondary

  # AWS regions are divided into multiple isolated data centers called AZs
  # Each AZ has independent power, cooling, networking
  availability_zone = var.availability_zone

  # Optional secondary AZ for the secondary private subnet
  availability_zone_secondary = var.availability_zone_secondary

  # Allows resources in PRIVATE subnet to initiate outbound internet connections
  # (e.g., download packages, call external APIs) while staying private
  enable_nat_gateway = var.enable_nat_gateway

  tags = var.tags
}

# ================================================================================
# IAM MODULE - PERMISSIONS AND ROLES
# ================================================================================
module "iam" {
  source = "../../modules/iam"
  environment  = var.environment
  project_name = var.project_name

  # AWS service for storing sensitive data (passwords, API keys, etc.)
  # Think of it as a secure vault that rotates passwords automatically
  secrets_manager_arns = var.secrets_manager_arns

  # A unique AWS identifier for your database instance
  rds_resource_id = try(module.rds[0].rds_resource_id, "")

  rds_db_user     = var.rds_db_user
  aws_region      = data.aws_region.current.name
  aws_account_id  = data.aws_caller_identity.current.account_id
  tags = var.tags
}

# ================================================================================
# COGNITO MODULE - USER AUTHENTICATION SYSTEM
# ================================================================================
module "cognito" {
  source = "../../modules/cognito"

  environment  = var.environment
  project_name = var.project_name
  
  # -----------------------------------------------------------------------------
  # DOMAIN NAME (FOR COGNITO HOSTED UI)
  # -----------------------------------------------------------------------------
  domain_name  = var.domain_name
  password_minimum_length = var.cognito_password_min_length

  tags = var.tags
}

# ================================================================================
# SECURITY GROUPS MODULE - FIREWALL RULES
# ================================================================================
module "security_groups" {
  source = "../../modules/security-groups"

  environment  = var.environment
  project_name = var.project_name

  # Security groups must be created inside a VPC
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr

  tags = var.tags
}

# ================================================================================
# RDS MODULE - MYSQL DATABASE WITH IAM AUTHENTICATION
# ================================================================================
module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"

  # -----------------------------------------------------------------------------
  # ENVIRONMENT AND PROJECT NAMING
  # -----------------------------------------------------------------------------
  environment  = var.environment
  project_name = var.project_name

  # -----------------------------------------------------------------------------
  # NETWORK CONFIGURATION
  # -----------------------------------------------------------------------------
  
  # VPC ID - Which VPC the database lives in
  vpc_id             = module.vpc.vpc_id
  
  # VPC CIDR - Used for security group rules
  vpc_cidr = var.vpc_cidr
  
  # PRIVATE SUBNET IDs - Where to place the database
  private_subnet_ids = module.vpc.private_subnet_ids

  # -----------------------------------------------------------------------------
  # DATABASE CONFIGURATION
  # -----------------------------------------------------------------------------
  db_name           = var.db_name
  db_username       = var.db_master_username
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  engine_version    = var.rds_engine_version
  iam_database_authentication_enabled = true
  multi_az            = false # Single-AZ for DEV
  deletion_protection = false # Allow easy cleanup in DEV
  skip_final_snapshot = true  # Skip snapshot on deletion in DEV

  # -----------------------------------------------------------------------------
  # SECURITY CONFIGURATION
  # -----------------------------------------------------------------------------
  allowed_security_group_ids = [module.security_groups.backend_api_security_group_id]

  tags = var.tags
}
