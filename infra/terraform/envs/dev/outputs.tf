# ========================================
# DEV Environment - Outputs
# ========================================

# ----------------------------------------
# VPC Outputs (Phase 2)
# ----------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = var.vpc_cidr
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = module.vpc.private_subnet_id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (if enabled)"
  value       = module.vpc.nat_gateway_id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = module.vpc.public_route_table_id
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = module.vpc.private_route_table_id
}

# ----------------------------------------
# IAM Outputs (Phase 3)
# ----------------------------------------
output "backend_api_role_arn" {
  description = "Backend API IAM role ARN"
  value       = module.iam.backend_api_role_arn
}

output "backend_api_instance_profile_name" {
  description = "Backend API instance profile name"
  value       = module.iam.backend_api_instance_profile_name
}

output "driver_web_role_arn" {
  description = "Driver web IAM role ARN"
  value       = module.iam.driver_web_role_arn
}

output "driver_web_instance_profile_name" {
  description = "Driver web instance profile name"
  value       = module.iam.driver_web_instance_profile_name
}


# ----------------------------------------
# Cognito Outputs (Phase 3)
# ----------------------------------------
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID (for frontend)"
  value       = module.cognito.app_client_id
  sensitive   = true
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = module.cognito.user_pool_endpoint
}

output "cognito_jwks_uri" {
  description = "JWKS URI for JWT validation"
  value       = module.cognito.jwks_uri
}

output "cognito_issuer" {
  description = "JWT issuer for validation"
  value       = module.cognito.issuer
}

# ----------------------------------------
# Security Group Outputs (Phase 3)
# ----------------------------------------
output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.security_groups.alb_security_group_id
}

output "backend_api_security_group_id" {
  description = "Backend API security group ID"
  value       = module.security_groups.backend_api_security_group_id
}

output "driver_web_security_group_id" {
  description = "Driver web security group ID"
  value       = module.security_groups.driver_web_security_group_id
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.security_groups.rds_security_group_id
}

# ----------------------------------------
# Configuration Summary
# ----------------------------------------
output "environment_summary" {
  description = "Summary of DEV environment configuration"
  value = {
    environment  = var.environment
    project_name = var.project_name
    region       = var.aws_region
    domain       = var.domain_name
    phase        = "Phase 3: IAM, Cognito, Security Groups"

    # Authentication
    cognito = {
      user_pool_id  = module.cognito.user_pool_id
      app_client_id = "*** (sensitive - use: terraform output cognito_app_client_id)"
      roles         = ["ADMIN", "DRIVER", "PASSENGER"]
    }

    # Network
    vpc = {
      id          = module.vpc.vpc_id
      cidr        = var.vpc_cidr
      nat_enabled = var.enable_nat_gateway
    }
  }
}
