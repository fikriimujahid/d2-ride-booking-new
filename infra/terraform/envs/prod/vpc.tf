# ================================================================================
# NETWORKING (PROD) - VPC via shared module
# ================================================================================

locals {
  # PROD is multi-AZ (2 AZs in this module version).
  prod_primary_az   = var.availability_zones[0]
  prod_secondary_az = var.availability_zones[1]
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr = var.vpc_cidr

  # Public tier
  public_subnet_cidr           = var.public_subnet_cidrs[0]
  public_subnet_cidr_secondary = var.public_subnet_cidrs[1]

  # Private app tier
  private_subnet_cidr           = var.private_app_subnet_cidrs[0]
  private_subnet_cidr_secondary = var.private_app_subnet_cidrs[1]

  # Private DB tier (separate from app)
  private_db_subnet_cidrs = var.private_db_subnet_cidrs

  # Availability zones
  availability_zone           = local.prod_primary_az
  availability_zone_secondary = local.prod_secondary_az

  # New, backward-compatible controls
  enable_multi_az = false
  az_count        = 2

  # NAT enabled only in PROD
  enable_nat_gateway = false

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
