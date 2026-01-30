# ================================================================================
# ROUTE53 RECORDS (PROD) - api + driver -> ALB
# (admin + passenger are managed by the CloudFront static site modules)
# ================================================================================

module "route53_api_driver" {
  source = "../../modules/route53"

  hosted_zone_id = var.route53_zone_id
  domain_name    = local.domain_base
  aws_region     = var.aws_region

  enable_admin_record      = false
  enable_passenger_record  = false
  s3_website_zone_id       = ""
  admin_website_domain     = ""
  passenger_website_domain = ""

  enable_api_record    = true
  enable_driver_record = true
  alb_dns_name         = module.alb.alb_dns_name
  alb_zone_id          = module.alb.alb_zone_id

  tags = var.tags
}
