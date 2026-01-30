# Optional but recommended: SSM endpoints for defense-in-depth.
module "ssm_vpc_endpoints" {
  count  = var.enable_ssm_vpc_endpoints ? 1 : 0
  source = "../../modules/vpc-endpoints"

  environment  = var.environment
  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = var.vpc_cidr
  subnet_ids = module.vpc.private_app_subnet_ids

  tags = var.tags
}
