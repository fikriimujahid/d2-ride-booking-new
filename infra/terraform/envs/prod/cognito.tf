# ================================================================================
# COGNITO (PROD) - NOT SHARED WITH DEV
# ================================================================================

module "cognito" {
  source = "../../modules/cognito"

  environment  = var.environment
  project_name = var.project_name

  domain_name             = local.domain_base
  password_minimum_length = var.cognito_password_min_length

  tags = var.tags
}
