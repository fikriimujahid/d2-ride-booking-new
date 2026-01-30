# ================================================================================
# DATABASE (PROD HARDENING) - NOT SHARED WITH DEV
# ================================================================================

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"

  environment  = var.environment
  project_name = var.project_name

  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_db_subnet_ids

  db_name                             = var.db_name
  db_username                         = var.db_master_username
  instance_class                      = var.rds_instance_class
  allocated_storage                   = var.rds_allocated_storage
  engine_version                      = var.rds_engine_version
  iam_database_authentication_enabled = true
  multi_az                            = true
  backup_retention_period             = var.rds_backup_retention_days

  # PROD safety:
  deletion_protection = true
  skip_final_snapshot = false

  allowed_security_group_ids = [module.security_groups.backend_api_security_group_id]

  tags = var.tags
}
