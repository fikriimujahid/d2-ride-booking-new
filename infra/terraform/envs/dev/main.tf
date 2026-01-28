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
# ACM CERTIFICATE FOR CLOUDFRONT (MUST BE IN us-east-1)
# ================================================================================
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = "*.d2.${var.domain_name}"
  subject_alternative_names = ["d2.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-cloudfront-cert"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "cloudfront"
    Domain      = "d2.${var.domain_name}"
  })
}

# DNS validation records for the CloudFront certificate
resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_cert_validation : record.fqdn]
}

# ================================================================================
# ACM CERTIFICATE FOR ALB (MUST BE IN SAME REGION AS ALB: ap-southeast-1)
# ================================================================================
# ALB will host:
# - api.d2.fikri.dev (backend API)
# - driver.d2.fikri.dev (driver web app)
resource "aws_acm_certificate" "alb" {
  # Note: No provider alias - uses default provider (ap-southeast-1)
  domain_name               = "*.d2.${var.domain_name}"
  subject_alternative_names = ["d2.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-alb-cert"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "alb"
    Domain      = "d2.${var.domain_name}"
  })
}

# DNS validation records for the ALB certificate
# Note: Can reuse same validation records as CloudFront cert since both cover *.d2.fikri.dev
resource "aws_route53_record" "alb_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for ALB certificate validation to complete
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_cert_validation : record.fqdn]
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
  domain_name    = "admin.d2.${var.domain_name}"
  hosted_zone_id = var.route53_zone_id

  acm_certificate_arn = aws_acm_certificate.cloudfront.arn
  force_destroy       = true
  tags                = var.tags

  depends_on = [aws_acm_certificate_validation.cloudfront]
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
  domain_name    = "passenger.d2.${var.domain_name}"
  hosted_zone_id = var.route53_zone_id

  acm_certificate_arn = aws_acm_certificate.cloudfront.arn
  force_destroy       = true
  tags                = var.tags

  depends_on = [aws_acm_certificate_validation.cloudfront]
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
  cognito_user_pool_arn           = module.cognito.user_pool_arn
  tags                            = var.tags
}

# ================================================================================
# RUNTIME CONFIG (SSM PARAMETER STORE)
# ================================================================================
locals {
  runtime_param_prefix_backend = "/${var.environment}/${var.project_name}/backend-api"
  runtime_param_prefix_driver  = "/${var.environment}/${var.project_name}/web-driver"

  backend_api_runtime_params_base = {
    NODE_ENV             = "dev"
    PORT                 = "3000" # backend-api runs on port 3000
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
    PORT     = "3001" # web-driver runs on port 3001 (consolidated instance)
  }
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
# CONSOLIDATED EC2 INSTANCE (DEV ONLY)
# ================================================================================
# DEV-ONLY CONSOLIDATION:
# - Both backend-api and web-driver run on ONE EC2 instance
# - Isolation via: separate directories, PM2 processes, ports, log streams
# - backend-api: port 3000, /opt/apps/backend-api
# - web-driver:  port 3001, /opt/apps/web-driver
# ================================================================================
module "ec2_app_host" {
  count = var.enable_ec2_backend || var.enable_web_driver ? 1 : 0

  source = "../../modules/ec2"

  environment           = var.environment
  project_name          = var.project_name
  subnet_id             = module.vpc.private_subnet_id
  security_group_id     = module.security_groups.app_host_security_group_id
  instance_profile_name = module.iam.app_host_instance_profile_name
  instance_type         = var.backend_instance_type
  root_volume_size      = var.backend_root_volume_size

  # Unified host configuration
  service_name = "app-host"

  # Pass both service names for multi-app setup
  enable_backend_api = var.enable_ec2_backend
  enable_web_driver  = var.enable_web_driver

  tags = merge(var.tags, {
    # Tag with both services for SSM targeting
    # SSM can target by either Service=backend-api or Service=web-driver
    Service         = "app-host"
    ServiceBackend  = "backend-api"
    ServiceDriver   = "web-driver"
    DeploymentModel = "consolidated"
  })

  depends_on = [module.vpc]
}

# ================================================================================
# ALB MODULE - Application Load Balancer for API and Driver Web
# ================================================================================
module "alb" {
  count = var.enable_alb && var.enable_ec2_backend ? 1 : 0

  source = "../../modules/alb"

  environment           = var.environment
  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  target_instance_id    = module.ec2_app_host[0].instance_id
  target_port           = 3000 # backend-api port
  health_check_path     = "/health"

  # Domain configuration for api.d2.fikri.dev and driver.d2.fikri.dev
  domain_name    = "d2.${var.domain_name}" # Changed to d2.fikri.dev
  hosted_zone_id = var.route53_zone_id

  # Use the regional certificate (ap-southeast-1) for ALB
  certificate_arn = aws_acm_certificate.alb.arn
  enable_https    = true

  enable_driver_web = var.enable_web_driver

  # When driver web is enabled, route driver.<domain> to the consolidated EC2 instance.
  driver_target_instance_id = var.enable_web_driver ? module.ec2_app_host[0].instance_id : ""
  driver_target_port        = 3001 # web-driver port on consolidated instance
  driver_health_check_path  = "/health"

  tags = var.tags

  depends_on = [aws_acm_certificate_validation.alb]
}

# ================================================================================
# ROUTE53 RECORDS (DEV)
# ================================================================================
module "route53_api_driver" {
  count  = var.route53_zone_id != "" ? 1 : 0
  source = "../../modules/route53"

  hosted_zone_id = var.route53_zone_id
  domain_name    = "d2.${var.domain_name}" # Changed to d2.fikri.dev
  aws_region     = var.aws_region

  # Admin/passenger are managed by the CloudFront static-site modules.
  enable_admin_record     = false
  enable_passenger_record = false

  # Keep these empty to avoid accidental usage.
  s3_website_zone_id       = ""
  admin_website_domain     = ""
  passenger_website_domain = ""

  # API and Driver domains point to the ALB
  enable_api_record    = var.enable_alb && var.enable_ec2_backend
  enable_driver_record = var.enable_web_driver && var.enable_alb && var.enable_ec2_backend
  alb_dns_name         = try(module.alb[0].alb_dns_name, "")
  alb_zone_id          = try(module.alb[0].alb_zone_id, "")

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
# CLOUDWATCH MODULE - OBSERVABILITY (PHASE 7)
# ================================================================================
# Centralized logging and cost-effective alarms for DEV environment
#
# WHAT THIS PROVIDES:
# - CloudWatch log groups for backend-api and web-driver
# - EC2 instance alarms (CPU, status checks)
# - RDS database alarms (CPU, storage, connections)
# - SNS topic for email notifications
#
# DEV PHILOSOPHY:
# - Logs > Dashboards (engineers debug with logs, not graphs)
# - Alarms answer "is it broken?" not "why is it broken?"
# - Keep it simple and cheap
#
# COST IMPACT:
# - Log storage (7 days): ~$0.20-0.50/month
# - Alarms (5 total): FREE (first 10 alarms included)
# - SNS notifications: FREE (within free tier)
# - Total: < $1/month
#
# WHEN TO DISABLE ALARMS:
# - During load testing (set enable_alarms = false)
# - During demos where failures are expected
# - When iterating rapidly on infrastructure
#
# HOW TO USE:
# -----------
# 1. Deploy with terraform apply
# 2. Check email for SNS subscription confirmation (if alarm_email is set)
# 3. View logs in CloudWatch console:
#    - /dev/ridebooking/backend-api
#    - /dev/ridebooking/web-driver
# 4. View alarms in CloudWatch Alarms console
# 5. Test alarms by triggering conditions (high CPU, etc.)
#
module "cloudwatch" {
  # Only create if we have EC2 or RDS enabled
  count = (var.enable_ec2_backend || var.enable_web_driver || var.enable_rds) ? 1 : 0

  source = "../../modules/cloudwatch"

  # General configuration
  environment  = var.environment
  project_name = var.project_name
  tags         = var.tags

  # Alarm toggle (disable during demos/testing)
  enable_alarms = var.enable_alarms

  # Log retention (7 days = cost-effective for DEV)
  log_retention_days = var.log_retention_days

  # EC2 monitoring (consolidated app-host instance)
  enable_ec2_monitoring = var.enable_ec2_backend
  ec2_instance_id       = var.enable_ec2_backend ? module.ec2_app_host[0].instance_id : ""
  ec2_instance_name     = "app-host"

  # RDS monitoring
  enable_rds_monitoring = var.enable_rds
  rds_instance_id       = var.enable_rds ? module.rds[0].rds_instance_id : ""
  rds_instance_name     = "${var.environment}-${var.project_name}-rds"

  # SNS notification email (optional)
  alarm_email = var.alarm_email

  depends_on = [
    module.ec2_app_host,
    module.rds
  ]
}
