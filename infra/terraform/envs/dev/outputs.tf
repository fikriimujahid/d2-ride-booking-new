# ================================================================================
# VPC OUTPUTS
# # ================================================================================
# output "vpc_id" {
#   description = "VPC ID"
#   value       = module.vpc.vpc_id
# }

# output "vpc_cidr" {
#   description = "VPC CIDR block"
#   value       = var.vpc_cidr
# }

# output "public_subnet_id" {
#   description = "Public subnet ID"
#   value       = module.vpc.public_subnet_id
# }

# output "private_subnet_id" {
#   description = "Private subnet ID"
#   value       = module.vpc.private_subnet_id
# }

# output "internet_gateway_id" {
#   description = "Internet Gateway ID"
#   value       = module.vpc.internet_gateway_id
# }

# output "nat_gateway_id" {
#   description = "NAT Gateway ID (if enabled)"
#   value       = module.vpc.nat_gateway_id
# }

# output "public_route_table_id" {
#   description = "Public route table ID"
#   value       = module.vpc.public_route_table_id
# }

# output "private_route_table_id" {
#   description = "Private route table ID"
#   value       = module.vpc.private_route_table_id
# }

# # ================================================================================
# # IAM OUTPUTS
# # ================================================================================
# # IAM roles and instance profiles for EC2 instances
# output "backend_api_role_arn" {
#   description = "Backend API IAM role ARN"
#   value       = module.iam.backend_api_role_arn
# }

# output "backend_api_instance_profile_name" {
#   description = "Backend API instance profile name"
#   value       = module.iam.backend_api_instance_profile_name
# }

# output "driver_web_role_arn" {
#   description = "Driver web IAM role ARN"
#   value       = module.iam.driver_web_role_arn
# }

# output "driver_web_instance_profile_name" {
#   description = "Driver web instance profile name"
#   value       = module.iam.driver_web_instance_profile_name
# }

# # ----------------------------------------
# # Cognito Outputs
# # ----------------------------------------
# output "cognito_user_pool_id" {
#   description = "Cognito User Pool ID"
#   value       = module.cognito.user_pool_id
# }

# output "cognito_app_client_id" {
#   description = "Cognito App Client ID (for frontend)"
#   value       = module.cognito.app_client_id
#   sensitive   = true
# }

# output "cognito_user_pool_endpoint" {
#   description = "Cognito User Pool endpoint"
#   value       = module.cognito.user_pool_endpoint
# }

# output "cognito_jwks_uri" {
#   description = "JWKS URI for JWT validation"
#   value       = module.cognito.jwks_uri
# }

# output "cognito_issuer" {
#   description = "JWT issuer for validation"
#   value       = module.cognito.issuer
# }

# # ----------------------------------------
# # Security Group Outputs
# # ----------------------------------------
# output "alb_security_group_id" {
#   description = "ALB security group ID"
#   value       = module.security_groups.alb_security_group_id
# }

# output "backend_api_security_group_id" {
#   description = "Backend API security group ID"
#   value       = module.security_groups.backend_api_security_group_id
# }

# output "driver_web_security_group_id" {
#   description = "Driver web security group ID"
#   value       = module.security_groups.driver_web_security_group_id
# }

# output "rds_security_group_id" {
#   description = "RDS security group ID (from RDS module)"
#   value       = try(module.rds[0].rds_security_group_id, "RDS not enabled")
# }

# # ----------------------------------------
# # RDS Outputs
# # ----------------------------------------
# output "rds_endpoint" {
#   description = "RDS instance endpoint (host:port) for application connections"
#   value       = try(module.rds[0].rds_endpoint, "RDS not enabled")
# }

# output "rds_address" {
#   description = "RDS instance hostname only (without port)"
#   value       = try(module.rds[0].rds_address, "RDS not enabled")
# }

# output "rds_port" {
#   description = "RDS instance port"
#   value       = try(module.rds[0].rds_port, "RDS not enabled")
# }

# output "db_name" {
#   description = "Database name"
#   value       = try(module.rds[0].db_name, "RDS not enabled")
# }

# output "rds_instance_id" {
#   description = "RDS instance identifier (for lifecycle scripts)"
#   value       = try(module.rds[0].rds_instance_id, "RDS not enabled")
# }

# output "rds_resource_id" {
#   description = "RDS resource ID (for IAM database authentication)"
#   value       = try(module.rds[0].rds_resource_id, "RDS not enabled")
# }

# output "master_password_secret_arn" {
#   description = "ARN of Secrets Manager secret containing master password (admin use only)"
#   value       = try(module.rds[0].master_password_secret_arn, "RDS not enabled")
# }

# output "iam_database_authentication_enabled" {
#   description = "Whether IAM database authentication is enabled"
#   value       = try(module.rds[0].iam_database_authentication_enabled, false)
# }

# ----------------------------------------
# Configuration Summary
# ----------------------------------------
output "environment_summary" {
  description = "Summary of DEV environment configuration"
  value = {
    meta = {
      aws_account_id = data.aws_caller_identity.current.account_id
      aws_region     = var.aws_region
      environment    = var.environment
      project_name   = var.project_name
      domain         = var.domain_name
      tags           = var.tags
    }

    cost = {
      enable_ec2_backend       = var.enable_ec2_backend
      enable_rds               = var.enable_rds
      enable_nat_gateway       = var.enable_nat_gateway
      enable_alb               = var.enable_alb
      enable_ssm_vpc_endpoints = var.enable_ssm_vpc_endpoints
      enable_bastion           = var.enable_bastion
    }

    network = {
      vpc = {
        id                  = module.vpc.vpc_id
        cidr                = var.vpc_cidr
        internet_gateway_id = module.vpc.internet_gateway_id
        nat_gateway_id      = try(module.vpc.nat_gateway_id, null)
        nat_enabled         = var.enable_nat_gateway
      }

      subnets = {
        public = {
          id_primary   = module.vpc.public_subnet_id
          id_secondary = try(module.vpc.public_subnet_id_secondary, null)
          ids          = module.vpc.public_subnet_ids
        }
        private = {
          id_primary = module.vpc.private_subnet_id
          ids        = module.vpc.private_subnet_ids
        }
      }

      route_tables = {
        public_id  = module.vpc.public_route_table_id
        private_id = module.vpc.private_route_table_id
      }
    }

    security_groups = {
      alb_id         = module.security_groups.alb_security_group_id
      backend_api_id = module.security_groups.backend_api_security_group_id
      driver_web_id  = module.security_groups.driver_web_security_group_id
      summary        = module.security_groups.security_group_summary
    }

    ssm = {
      # These are the VPC interface endpoints required for SSM when instances have no public IP.
      vpc_endpoints_enabled = var.enable_ssm_vpc_endpoints
      vpc_endpoints = {
        security_group_id       = try(module.ssm_vpc_endpoints[0].security_group_id, null)
        ssm_endpoint_id         = try(module.ssm_vpc_endpoints[0].ssm_endpoint_id, null)
        ec2messages_endpoint_id = try(module.ssm_vpc_endpoints[0].ec2messages_endpoint_id, null)
        ssmmessages_endpoint_id = try(module.ssm_vpc_endpoints[0].ssmmessages_endpoint_id, null)
      }
    }

    backend = {
      enabled = var.enable_ec2_backend

      ec2 = {
        instance_id               = try(module.ec2_backend[0].instance_id, "EC2 backend not enabled")
        private_ip                = try(module.ec2_backend[0].private_ip, null)
        subnet_id                 = module.vpc.private_subnet_id
        security_group_id         = module.security_groups.backend_api_security_group_id
        instance_type             = var.backend_instance_type
        root_volume_size_gb       = var.backend_root_volume_size
        iam_instance_profile_name = module.iam.backend_api_instance_profile_name
        cloudwatch_log_group_name = try(module.ec2_backend[0].log_group_name, null)
      }

      alb = {
        enabled         = var.enable_alb
        dns_name        = try(module.alb[0].alb_dns_name, null)
        api_url         = var.enable_alb ? (var.route53_zone_id != "" ? "https://api.${var.domain_name}" : null) : null
        route53_zone_id = var.route53_zone_id
      }
    }

    bastion = {
      enabled = var.enable_bastion

      ec2 = {
        instance_id       = try(module.bastion[0].instance_id, null)
        public_ip         = try(module.bastion[0].public_ip, null)
        private_ip        = try(module.bastion[0].private_ip, null)
        security_group_id = try(module.bastion[0].security_group_id, null)
        subnet_id         = module.vpc.public_subnet_id
      }

      access = {
        method_default = "ssm"
        ssh_enabled    = var.bastion_enable_ssh
      }
    }

    deployments = {
      s3 = {
        bucket_name = module.deployments_bucket.bucket_name
        bucket_arn  = module.deployments_bucket.bucket_arn
        # Used by GitHub Actions workflow (.github/workflows/backend-api-deploy-dev.yml)
        github_actions_var_name = "S3_BUCKET"
      }
    }

    frontends = {
      web_admin = {
        enabled = var.enable_web_admin

        s3_bucket_name                 = try(module.web_admin_static[0].bucket_name, null)
        cloudfront_distribution_id     = try(module.web_admin_static[0].cloudfront_distribution_id, null)
        cloudfront_domain_name         = try(module.web_admin_static[0].cloudfront_domain_name, null)
        url                            = try(module.web_admin_static[0].site_url, null)
        github_actions_bucket_var_name = "S3_BUCKET_WEB_ADMIN"
        github_actions_cf_var_name     = "CLOUDFRONT_DISTRIBUTION_ID_WEB_ADMIN"
      }

      web_passenger = {
        enabled = var.enable_web_passenger

        s3_bucket_name                 = try(module.web_passenger_static[0].bucket_name, null)
        cloudfront_distribution_id     = try(module.web_passenger_static[0].cloudfront_distribution_id, null)
        cloudfront_domain_name         = try(module.web_passenger_static[0].cloudfront_domain_name, null)
        url                            = try(module.web_passenger_static[0].site_url, null)
        github_actions_bucket_var_name = "S3_BUCKET_WEB_PASSENGER"
        github_actions_cf_var_name     = "CLOUDFRONT_DISTRIBUTION_ID_WEB_PASSENGER"
      }
    }

    auth = {
      cognito = {
        user_pool_id       = module.cognito.user_pool_id
        user_pool_arn      = module.cognito.user_pool_arn
        user_pool_endpoint = module.cognito.user_pool_endpoint

        issuer   = module.cognito.issuer
        jwks_uri = module.cognito.jwks_uri

        app_client = {
          id   = "*** (sensitive - use: terraform output cognito_app_client_id)"
          name = module.cognito.app_client_name
        }

        roles = ["ADMIN", "DRIVER", "PASSENGER"]
      }
    }

    database = {
      rds = {
        enabled           = var.enable_rds
        endpoint          = try(module.rds[0].rds_endpoint, "RDS not enabled")
        database          = try(module.rds[0].db_name, "RDS not enabled")
        iam_auth_enabled  = try(module.rds[0].iam_database_authentication_enabled, false)
        instance_class    = var.rds_instance_class
        lifecycle_control = "Use infra/scripts/dev-stop.sh to reduce costs"
      }
    }
  }
}
