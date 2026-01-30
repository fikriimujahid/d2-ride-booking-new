# ================================================================================
# COMPUTE (ASG) - backend-api only
# ================================================================================

module "backend_api_asg" {
  source = "../../modules/asg"

  environment  = var.environment
  project_name = var.project_name
  service_name = "backend-api"

  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_ids = [module.security_groups.backend_api_security_group_id]

  instance_profile_name = module.iam.backend_api_instance_profile_name
  instance_type         = var.backend_instance_type
  root_volume_size_gb   = var.backend_root_volume_size
  app_port              = 3000

  min_size         = var.backend_asg_min
  desired_capacity = var.backend_asg_desired
  max_size         = var.backend_asg_max

  target_group_arns = [module.alb.backend_target_group_arn]

  health_check_grace_period_seconds = var.asg_health_check_grace_period_seconds
  health_check_type_override        = var.asg_health_check_type_override

  tags = var.tags
}
