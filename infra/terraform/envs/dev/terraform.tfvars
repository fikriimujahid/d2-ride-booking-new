# ================================================================================
# GENERAL CONFIGURATION
# ================================================================================
environment  = "dev"
project_name = "d2-ride-booking"
domain_name  = "fikri.dev"

# ================================================================================
# AWS CONFIGURATION
# ================================================================================
aws_region                  = "ap-southeast-1"
availability_zone           = "ap-southeast-1a"
availability_zone_secondary = "ap-southeast-1b"

# ================================================================================
# VPC CONFIGURATION
# ================================================================================
vpc_cidr = "10.20.0.0/16"

public_subnet_cidr           = "10.20.1.0/24"
public_subnet_cidr_secondary = "10.20.2.0/24"

private_subnet_cidr           = "10.20.11.0/24"
private_subnet_cidr_secondary = "10.20.12.0/24"

# --------------------------------------------------------------------------------
# ROUTE53 HOSTED ZONE ID (LEAVE BLANK TO SKIP ALIAS CREATION)
# --------------------------------------------------------------------------------
route53_zone_id = "Z019716819YT0PPFWXQPV"

# Optional: S3 website hosted zone id for your region.
# If unknown, leave blank and the Route53 module will fall back to CNAME records
# for admin/passenger subdomains (still valid DNS).
s3_website_zone_id = ""

# --------------------------------------------------------------------------------
# PASSWORD MINIMUM LENGTH
# --------------------------------------------------------------------------------
cognito_password_min_length = 8 # DEV: 8 chars (PROD should use 12+)

# ================================================================================
# IAM CONFIGURATION
# ================================================================================

# --------------------------------------------------------------------------------
# SECRETS MANAGER ARNs
# --------------------------------------------------------------------------------
secrets_manager_arns = []

# ================================================================================
# RDS CONFIGURATION
# ================================================================================
# MySQL database settings
db_name               = "ridebooking"
db_master_username    = "admin"
rds_db_user           = "app_user"
rds_instance_class    = "db.t3.micro" # DEV: smallest instance
rds_allocated_storage = 20            # GB - will autoscale if needed
rds_engine_version    = "8.0"

# ================================================================================
# BACKEND EC2 SETTINGS
# ================================================================================
backend_instance_type    = "t3.micro"
backend_root_volume_size = 16

# ================================================================================
# RESOURCE TAGS
# ================================================================================
tags = {
  Environment = "dev"             # dev/staging/prod
  Project     = "d2-ride-booking" # Project identifier
  ManagedBy   = "terraform"       # How this was created
  Domain      = "d2.fikri.dev"    # Associated domain
}

# ================================================================================
# COST
# ================================================================================
enable_ec2_backend       = false
enable_rds               = false
enable_nat_gateway       = false
enable_alb               = false
enable_ssm_vpc_endpoints = false

enable_web_admin     = false
enable_web_passenger = false
enable_web_driver    = false

driver_instance_type    = "t3.micro"
driver_root_volume_size = 16

# ================================================================================
# BASTION (OPTIONAL)
# ================================================================================
# Recommended: enable bastion and connect via SSM port forwarding.
enable_bastion = false

# Optional SSH (generally not needed if using SSM)
bastion_enable_ssh        = false
bastion_ssh_allowed_cidrs = ["125.163.30.66/32", "103.136.58.0/24"] # Replace with your IP address

# Only required if bastion_enable_ssh=true
bastion_key_name = "fikri-platform-key"