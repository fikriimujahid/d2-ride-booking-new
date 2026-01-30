# ================================================================================
# STATIC WEBSITES (PROD) - web-admin + web-passenger via CloudFront + private S3 origin
# ================================================================================

module "web_admin_static_site" {
  source = "../../modules/cloudfront-static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  site_name               = "web-admin"
  domain_name             = local.admin_domain
  hosted_zone_id          = var.route53_zone_id
  acm_certificate_arn     = aws_acm_certificate_validation.cloudfront.certificate_arn
  force_destroy           = true
  enable_waf              = true
  waf_managed_rules_mode  = "none"
  enable_security_headers = true

  tags = var.tags
}

module "web_passenger_static_site" {
  source = "../../modules/cloudfront-static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment    = var.environment
  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id

  site_name               = "web-passenger"
  domain_name             = local.passenger_domain
  hosted_zone_id          = var.route53_zone_id
  acm_certificate_arn     = aws_acm_certificate_validation.cloudfront.certificate_arn
  force_destroy           = true
  enable_waf              = true
  waf_managed_rules_mode  = "none"
  enable_security_headers = true

  tags = var.tags
}
