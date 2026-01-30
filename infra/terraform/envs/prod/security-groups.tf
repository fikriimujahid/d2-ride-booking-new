# ================================================================================
# SECURITY GROUPS (PROD) - NOT SHARED WITH DEV
# ================================================================================

module "security_groups" {
  source = "../../modules/security-groups-prod"

  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr

  backend_api_port = 3000
  driver_web_port  = 3001

  vpc_endpoints_security_group_id = try(module.ssm_vpc_endpoints[0].security_group_id, null)

  tags = var.tags
}
