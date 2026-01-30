# ================================================================================
# RUNTIME CONFIG (SSM PARAMETER STORE) - NOT SHARED WITH DEV
# ================================================================================

locals {
  runtime_param_prefix_backend = "/${var.environment}/${var.project_name}/backend-api"

  backend_api_runtime_params_base = {
    NODE_ENV             = "production"
    PORT                 = "3000"
    AWS_REGION           = var.aws_region
    COGNITO_USER_POOL_ID = module.cognito.user_pool_id
    COGNITO_CLIENT_ID    = module.cognito.app_client_id
    CORS_ORIGINS         = "https://${local.admin_domain},https://${local.driver_domain},https://passenger.${local.domain_base}"
  }

  backend_api_runtime_params_db = var.enable_rds ? {
    DB_HOST                    = module.rds[0].rds_address
    DB_PORT                    = tostring(module.rds[0].rds_port)
    DB_NAME                    = var.db_name
    DB_USER                    = var.rds_db_user
    DB_IAM_AUTH                = "true"
    DB_SSL                     = "true"
    DB_SSL_REJECT_UNAUTHORIZED = "true"
    DB_SSL_CA_PATH             = "/opt/apps/backend-api/shared/aws-rds-global-bundle.pem"
  } : {}

  backend_api_runtime_params = merge(local.backend_api_runtime_params_base, local.backend_api_runtime_params_db)
}

resource "aws_ssm_parameter" "backend_api_runtime" {
  for_each = local.backend_api_runtime_params

  name  = "${local.runtime_param_prefix_backend}/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-backend-api-${each.key}"
    Environment = var.environment
    Service     = "backend-api"
    ManagedBy   = "terraform"
  })
}
