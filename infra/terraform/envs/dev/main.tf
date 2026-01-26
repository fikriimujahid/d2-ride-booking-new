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

# CloudFront requires ACM certificates in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
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
# ACM CERTIFICATE (us-east-1) FOR CLOUDFRONT (DEV)
# ================================================================================
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-cloudfront-cert"
    Environment = var.environment
    Service     = "cloudfront"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_cert_validation : r.fqdn]
}

# ================================================================================
# DEPLOYMENT ARTIFACTS BUCKET (S3)
# ================================================================================
module "deployments_bucket" {
  source = "../../modules/deployments-bucket"

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  # Dev-friendly: allow destroy even if objects exist
  force_destroy = true

  tags = var.tags
}

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

  # Optional secondary public subnet to satisfy ALB multi-AZ requirement
  public_subnet_cidr_secondary = var.public_subnet_cidr_secondary

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
  source       = "../../modules/iam"
  environment  = var.environment
  project_name = var.project_name

  # AWS service for storing sensitive data (passwords, API keys, etc.)
  # Think of it as a secure vault that rotates passwords automatically
  secrets_manager_arns = var.secrets_manager_arns

  # A unique AWS identifier for your database instance
  rds_resource_id = try(module.rds[0].rds_resource_id, "")

  rds_db_user                     = var.rds_db_user
  aws_region                      = data.aws_region.current.name
  aws_account_id                  = data.aws_caller_identity.current.account_id
  deployment_artifacts_bucket_arn = module.deployments_bucket.bucket_arn
  tags                            = var.tags
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
  domain_name             = var.domain_name
  password_minimum_length = var.cognito_password_min_length

  tags = var.tags
}

# ================================================================================
# RUNTIME CONFIG (SSM PARAMETER STORE)
# ================================================================================
# These parameters are read at deploy time by SSM Run Command on the instance.
# This keeps configuration OUT of artifacts and avoids writing .env files.
#
# Path convention:
#   /<env>/<project>/<service>/<KEY>
# Examples:
#   /dev/d2-ride-booking/backend-api/DB_HOST
#   /dev/d2-ride-booking/web-driver/PORT

locals {
  runtime_param_prefix_backend = "/${var.environment}/${var.project_name}/backend-api"
  runtime_param_prefix_driver  = "/${var.environment}/${var.project_name}/web-driver"

  # SSM Run Command output log groups (used by infra/scripts/deploy-*.sh when enabled)
  ssm_deploy_backend_api_log_group = "/${var.environment}/ssm/deploy-backend-api"

  backend_api_runtime_params_base = {
    NODE_ENV             = "dev"
    PORT                 = "3000"
    AWS_REGION           = var.aws_region
    COGNITO_USER_POOL_ID = module.cognito.user_pool_id
    COGNITO_CLIENT_ID    = module.cognito.app_client_id
    CORS_ORIGINS         = "https://admin.${var.domain_name},https://driver.${var.domain_name},https://passenger.${var.domain_name}"
  }

  backend_api_runtime_params_db = var.enable_rds ? {
    DB_HOST                    = module.rds[0].rds_address
    DB_PORT                    = tostring(module.rds[0].rds_port)
    DB_NAME                    = var.db_name
    DB_USER                    = var.rds_db_user
    DB_IAM_AUTH                = "true"
    DB_SSL                     = "true"
    DB_SSL_REJECT_UNAUTHORIZED = "true"
    DB_SSL_CA_PATH             = "/opt/apps/backend-api/shared/aws-rds-global-bundle.pem"
  } : {}

  backend_api_runtime_params = merge(local.backend_api_runtime_params_base, local.backend_api_runtime_params_db)

  web_driver_runtime_params = {
    NODE_ENV = "production"
    PORT     = "3000"
  }
}

resource "aws_cloudwatch_log_group" "ssm_deploy_backend_api" {
  name              = local.ssm_deploy_backend_api_log_group
  retention_in_days = 14
  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-ssm-deploy-backend-api"
    Environment = var.environment
    Service     = "ssm-deploy-backend-api"
  })
}

resource "aws_ssm_parameter" "backend_api_runtime" {
  for_each = var.enable_ec2_backend ? local.backend_api_runtime_params : {}

  name  = "${local.runtime_param_prefix_backend}/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-backend-api-${each.key}"
    Environment = var.environment
    Service     = "backend-api"
    ManagedBy   = "terraform"
  })
}

resource "aws_ssm_parameter" "web_driver_runtime" {
  for_each = var.enable_web_driver ? local.web_driver_runtime_params : {}

  name  = "${local.runtime_param_prefix_driver}/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-web-driver-${each.key}"
    Environment = var.environment
    Service     = "web-driver"
    ManagedBy   = "terraform"
  })
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

  # Toggle: allow direct VPC access when ALB disabled (DEV convenience)
  enable_alb = var.enable_alb

  # When NAT is enabled, instances can reach the public internet (outbound only).
  # Security group egress rules still need to allow it.
  enable_nat_gateway = var.enable_nat_gateway

  tags = var.tags
}

# ================================================================================
# VPC ENDPOINTS (SSM) - REQUIRED FOR PRIVATE EC2 WITHOUT INTERNET/NAT
# ================================================================================
module "ssm_vpc_endpoints" {
  count  = var.enable_ssm_vpc_endpoints ? 1 : 0
  source = "../../modules/vpc-endpoints"

  environment  = var.environment
  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = var.vpc_cidr
  subnet_ids = module.vpc.private_subnet_ids

  tags = var.tags
}

# ==============================================================================
# BASTION HOST (OPTIONAL) - SAFE RDS ACCESS PATH
# ==============================================================================
# Default access method is SSM Session Manager (no inbound ports required).
# Optional SSH can be enabled via variables if you prefer.
module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../modules/bastion"

  environment  = var.environment
  project_name = var.project_name

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr

  # Place bastion in the public subnet and give it a public IP.
  subnet_id         = module.vpc.public_subnet_id
  instance_type     = var.bastion_instance_type
  enable_ssh        = var.bastion_enable_ssh
  ssh_allowed_cidrs = var.bastion_ssh_allowed_cidrs
  key_name          = var.bastion_key_name

  tags = var.tags

  depends_on = [module.vpc]
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
  vpc_id = module.vpc.vpc_id

  # VPC CIDR - Used for security group rules
  vpc_cidr = var.vpc_cidr

  # PRIVATE SUBNET IDs - Where to place the database
  private_subnet_ids = module.vpc.private_subnet_ids

  # -----------------------------------------------------------------------------
  # DATABASE CONFIGURATION
  # -----------------------------------------------------------------------------
  db_name                             = var.db_name
  db_username                         = var.db_master_username
  instance_class                      = var.rds_instance_class
  allocated_storage                   = var.rds_allocated_storage
  engine_version                      = var.rds_engine_version
  iam_database_authentication_enabled = true
  multi_az                            = false # Single-AZ for DEV
  deletion_protection                 = false # Allow easy cleanup in DEV
  skip_final_snapshot                 = true  # Skip snapshot on deletion in DEV

  # -----------------------------------------------------------------------------
  # SECURITY CONFIGURATION
  # -----------------------------------------------------------------------------
  allowed_security_group_ids = concat(
    [module.security_groups.backend_api_security_group_id],
    var.enable_bastion ? [module.bastion[0].security_group_id] : []
  )

  tags = var.tags
}

# ================================================================================
# EC2 MODULE - BACKEND API SERVER (DEV, SINGLE AZ)
# ================================================================================
module "ec2_backend" {
  count = var.enable_ec2_backend ? 1 : 0

  source = "../../modules/ec2"

  environment           = var.environment
  project_name          = var.project_name
  subnet_id             = module.vpc.private_subnet_id
  security_group_id     = module.security_groups.backend_api_security_group_id
  instance_profile_name = module.iam.backend_api_instance_profile_name
  instance_type         = var.backend_instance_type
  root_volume_size      = var.backend_root_volume_size
  tags                  = var.tags

  depends_on = [module.vpc]
}

# ================================================================================
# STATIC WEB SITES (CLOUDFRONT + PRIVATE S3, DEV)
# ================================================================================
module "web_admin_static" {
  count  = var.enable_web_admin ? 1 : 0
  source = "../../modules/cloudfront-static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  site_name      = "web-admin"
  domain_name    = "admin.${var.domain_name}"
  hosted_zone_id = var.route53_zone_id

  acm_certificate_arn = aws_acm_certificate_validation.cloudfront.certificate_arn
  force_destroy       = true
  tags                = var.tags
}

module "web_passenger_static" {
  count  = var.enable_web_passenger ? 1 : 0
  source = "../../modules/cloudfront-static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  site_name      = "web-passenger"
  domain_name    = "passenger.${var.domain_name}"
  hosted_zone_id = var.route53_zone_id

  acm_certificate_arn = aws_acm_certificate_validation.cloudfront.certificate_arn
  force_destroy       = true
  tags                = var.tags
}

# ================================================================================
# DRIVER WEB (Next.js on EC2, SSR/realtime ready)
# ================================================================================
# SECURITY / COST NOTES:
# - Single small instance (t3.micro) with PM2.
# - No SSH: access is via SSM Session Manager.
# - Instance is in the PRIVATE subnet; it is exposed publicly only through the ALB.
module "ec2_driver" {
  count = var.enable_web_driver ? 1 : 0

  source = "../../modules/ec2"

  environment           = var.environment
  project_name          = var.project_name
  subnet_id             = module.vpc.private_subnet_id
  security_group_id     = module.security_groups.driver_web_security_group_id
  instance_profile_name = module.iam.driver_web_instance_profile_name

  instance_type    = var.driver_instance_type
  root_volume_size = var.driver_root_volume_size

  # Keep naming consistent with the application and required log groups.
  # Required CloudWatch log group: /dev/web-driver
  service_name = "web-driver"
  app_root     = "/opt/apps/web-driver"
  pm2_app_name = "web-driver"

  tags = var.tags

  depends_on = [module.vpc]
}

# ================================================================================
# OPTIONAL ALB MODULE - ENABLED VIA TOGGLE (DEFAULT OFF TO SAVE COST)
# ================================================================================
module "alb" {
  count = var.enable_alb && var.enable_ec2_backend ? 1 : 0

  source = "../../modules/alb"

  environment           = var.environment
  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  target_instance_id    = module.ec2_backend[0].instance_id
  target_port           = 3000
  health_check_path     = "/health"
  domain_name           = var.domain_name
  hosted_zone_id        = var.route53_zone_id

  enable_driver_web = var.enable_web_driver

  # When driver web is enabled, route driver.<domain> to the driver EC2 instance.
  driver_target_instance_id = var.enable_web_driver ? module.ec2_driver[0].instance_id : ""
  driver_target_port        = 3000
  driver_health_check_path  = "/health"
  tags                      = var.tags
}

# ================================================================================
# ROUTE53 RECORDS (DEV)
# ================================================================================
module "route53_frontends" {
  count  = var.route53_zone_id != "" ? 1 : 0
  source = "../../modules/route53"

  hosted_zone_id = var.route53_zone_id
  domain_name    = var.domain_name
  aws_region     = var.aws_region

  # Admin/passenger are managed by the CloudFront static-site modules.
  enable_admin_record     = false
  enable_passenger_record = false

  # Keep these empty to avoid accidental usage.
  s3_website_zone_id       = ""
  admin_website_domain     = ""
  passenger_website_domain = ""

  # Driver domain points to the ALB (host-based routing forwards to driver EC2)
  enable_driver_record = var.enable_web_driver && var.enable_alb && var.enable_ec2_backend
  alb_dns_name         = try(module.alb[0].alb_dns_name, "")
  alb_zone_id          = try(module.alb[0].alb_zone_id, "")

  tags = var.tags
}
