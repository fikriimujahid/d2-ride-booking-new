# ================================================================================
# DEPLOYMENT ARTIFACTS BUCKET (S3) - NOT SHARED WITH DEV
# ================================================================================

module "deployments_bucket" {
  source = "../../modules/deployments-bucket"

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  # NOTE: force_destroy=true means terraform destroy CAN delete objects.
  # If you want stronger PROD safety, set this to false in a follow-up change.
  force_destroy = true

  tags = var.tags
}
