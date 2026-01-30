# ==============================================================================
# BASTION HOST (PROD) - SAFE RDS ACCESS PATH
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
  subnet_id         = module.vpc.public_subnet_ids[0]
  instance_type     = var.bastion_instance_type
  enable_ssh        = var.bastion_enable_ssh
  ssh_allowed_cidrs = var.bastion_ssh_allowed_cidrs
  key_name          = var.bastion_key_name

  tags = var.tags

  depends_on = [module.vpc]
}

# ==============================================================================
# BASTION -> RDS ACCESS (PROD)
# ==============================================================================
# Keep this rule outside the RDS module so the module's internal `count` doesn't
# depend on unknown values during plan.
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_bastion" {
  count = (var.enable_rds && var.enable_bastion) ? 1 : 0

  security_group_id            = module.rds[0].rds_security_group_id
  referenced_security_group_id = module.bastion[0].security_group_id

  description = "Allow MySQL from bastion"
  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"
}
