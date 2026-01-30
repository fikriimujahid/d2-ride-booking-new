# ================================================================================
# IAM (PROD) - NOT SHARED WITH DEV
# ================================================================================

module "iam" {
  source       = "../../modules/iam"
  environment  = var.environment
  project_name = var.project_name

  secrets_manager_arns            = []
  rds_resource_id                 = try(module.rds[0].rds_resource_id, "")
  rds_db_user                     = var.rds_db_user
  aws_region                      = data.aws_region.current.name
  aws_account_id                  = data.aws_caller_identity.current.account_id
  deployment_artifacts_bucket_arn = module.deployments_bucket.bucket_arn
  cognito_user_pool_arn           = module.cognito.user_pool_arn
  tags                            = var.tags
}
