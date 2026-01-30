output "prod_summary" {
  description = "High-level PROD outputs"
  value = {
    environment = var.environment
    region      = var.aws_region
    domain_base = "d2.${var.domain_name}"

    alb = {
      dns_name = try(module.alb.alb_dns_name, null)
      api_url  = var.route53_zone_id != "" ? "https://api.d2.${var.domain_name}" : null
      driver   = var.route53_zone_id != "" ? "https://driver.d2.${var.domain_name}" : null
    }

    static_sites = {
      web_admin = {
        url               = "https://admin.d2.${var.domain_name}"
        bucket_name       = try(module.web_admin_static_site.bucket_name, null)
        distribution_id   = try(module.web_admin_static_site.cloudfront_distribution_id, null)
        cloudfront_domain = try(module.web_admin_static_site.cloudfront_domain_name, null)
      }
      web_passenger = {
        url               = "https://passenger.d2.${var.domain_name}"
        bucket_name       = try(module.web_passenger_static_site.bucket_name, null)
        distribution_id   = try(module.web_passenger_static_site.cloudfront_distribution_id, null)
        cloudfront_domain = try(module.web_passenger_static_site.cloudfront_domain_name, null)
      }
    }

    cognito = {
      user_pool_id  = module.cognito.user_pool_id
      app_client_id = module.cognito.app_client_id
      issuer        = module.cognito.issuer
      jwks_uri      = module.cognito.jwks_uri
      user_pool_arn = module.cognito.user_pool_arn
    }

    rds = var.enable_rds ? {
      endpoint    = module.rds[0].rds_endpoint
      address     = module.rds[0].rds_address
      port        = module.rds[0].rds_port
      resource_id = module.rds[0].rds_resource_id
    } : null

    bastion = var.enable_bastion ? {
      instance_id       = module.bastion[0].instance_id
      public_ip         = module.bastion[0].public_ip
      private_ip        = module.bastion[0].private_ip
      security_group_id = module.bastion[0].security_group_id
      instance_profile  = module.bastion[0].instance_profile_name
    } : null

    asg = {
      backend = {
        name    = module.backend_api_asg.autoscaling_group_name
        desired = var.backend_asg_desired
      }
      driver = null
    }

    cicd = {
      github_actions_role_arn = try(aws_iam_role.github_actions_prod_deploy.arn, null)
    }
  }
}

# ================================================================================
# NETWORK OUTPUTS (PROD) - for later phases
# ================================================================================
output "vpc_id" {
  description = "PROD VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "PROD public subnet IDs (one per AZ)"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "PROD private app subnet IDs (one per AZ)"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "PROD private DB subnet IDs (one per AZ)"
  value       = module.vpc.private_db_subnet_ids
}
