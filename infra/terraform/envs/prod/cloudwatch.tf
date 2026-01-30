# ================================================================================
# OBSERVABILITY (PROD UPGRADE)
# ================================================================================

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment  = var.environment
  project_name = var.project_name
  tags         = var.tags

  enable_alarms      = var.enable_alarms
  alarm_email        = var.alarm_email
  log_retention_days = var.log_retention_days

  # In PROD, EC2 is an ASG (no single instance id alarm). We focus on ALB target health.
  enable_ec2_monitoring = false

  enable_rds_monitoring = var.enable_rds
  rds_instance_id       = try(module.rds[0].rds_instance_id, "")
  rds_instance_name     = "prod-mysql"

  enable_alb_monitoring           = true
  alb_arn_suffix                  = module.alb.alb_arn_suffix
  backend_target_group_arn_suffix = module.alb.backend_target_group_arn_suffix

  driver_target_group_arn_suffix = module.alb.driver_target_group_arn_suffix

  # PROD is stricter than DEV: shorter periods and fewer eval periods.
  alb_alarm_period_seconds     = 60
  alb_alarm_evaluation_periods = 2
  alb_unhealthy_host_threshold = 1
}
