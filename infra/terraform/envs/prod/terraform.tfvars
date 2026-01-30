environment  = "prod"
project_name = "d2-ride-booking"
aws_region   = "ap-southeast-1"

# ==============================================================================
# GITHUB INTEGRATION
# ==============================================================================
enable_github_actions_deploy_role = true
github_oidc_provider_arn          = "arn:aws:iam::731099197523:oidc-provider/token.actions.githubusercontent.com"
github_repo = "fikriimujahid/d2-ride-booking-new"

# Root domain. ALB will use: api.d2.<domain_name> and driver.d2.<domain_name>
domain_name     = "fikri.dev"
route53_zone_id = "Z019716819YT0PPFWXQPV"

# Networking (non-overlapping with DEV)
vpc_cidr = "10.30.0.0/16"

availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b"
]

public_subnet_cidrs = [
  "10.30.1.0/24",
  "10.30.2.0/24"
]

private_app_subnet_cidrs = [
  "10.30.11.0/24",
  "10.30.12.0/24"
]

private_db_subnet_cidrs = [
  "10.30.21.0/24",
  "10.30.22.0/24"
]

enable_ssm_vpc_endpoints = false

# Bastion (SSM-first; no inbound ports by default)
enable_bastion          = false
bastion_instance_type   = "t3.micro"
bastion_enable_ssh      = false
bastion_key_name        = null
bastion_ssh_allowed_cidrs = []

# RDS
enable_rds                = false
db_name                   = "ridebooking"
db_master_username        = "admin"
rds_db_user               = "app_user"
rds_instance_class        = "db.t3.micro"
rds_allocated_storage     = 30
rds_engine_version        = "8.0"
rds_backup_retention_days = 7
 
# ASGs
asg_health_check_type_override = "EC2"
backend_instance_type    = "t3.micro"
backend_root_volume_size = 10
backend_asg_min          = 1
backend_asg_desired      = 1
backend_asg_max          = 3

driver_instance_type    = "t3.micro"
driver_root_volume_size = 10
driver_asg_min          = 1
driver_asg_desired      = 1
driver_asg_max          = 3

# Cognito hardening
cognito_password_min_length = 12

# Observability
enable_alarms      = false
alarm_email        = ""
log_retention_days = 90

# Tags (make the env explicit for auditability)
tags = {
  Environment = "prod"
  Project     = "d2-ride-booking"
  ManagedBy   = "terraform"
  Domain      = "d2.fikri.dev"
  DataClass   = "production"
}
