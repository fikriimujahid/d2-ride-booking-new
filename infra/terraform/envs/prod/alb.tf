# ================================================================================
# LOAD BALANCER (PROD) - backend-api + web-driver
# ================================================================================

module "alb" {
  source = "../../modules/alb"

  environment           = var.environment
  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id

  # PROD uses ASGs -> do NOT attach specific instance IDs.
  attach_targets = false

  target_port       = 3000
  health_check_path = "/health"

  enable_driver_web        = true
  driver_target_port       = 3001
  driver_health_check_path = "/health"

  domain_name         = local.domain_base
  hosted_zone_id      = var.route53_zone_id
  certificate_arn     = aws_acm_certificate_validation.alb.certificate_arn
  enable_https        = true
  enable_host_routing = true

  deregistration_delay_seconds = 30

  tags = var.tags
}
