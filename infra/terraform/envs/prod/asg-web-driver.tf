# ================================================================================
# COMPUTE (ASG) - web-driver
# ================================================================================

module "web_driver_asg" {
  source = "../../modules/asg"

  environment  = var.environment
  project_name = var.project_name
  service_name = "web-driver"

  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_ids = [module.security_groups.driver_web_security_group_id]

  instance_profile_name = module.iam.driver_web_instance_profile_name
  instance_type         = var.driver_instance_type
  root_volume_size_gb   = var.driver_root_volume_size
  app_port              = 3001

  min_size         = var.driver_asg_min
  desired_capacity = var.driver_asg_desired
  max_size         = var.driver_asg_max

  target_group_arns = [module.alb.driver_target_group_arn]

  health_check_grace_period_seconds = var.asg_health_check_grace_period_seconds
  health_check_type_override        = var.asg_health_check_type_override

  tags = var.tags
}
