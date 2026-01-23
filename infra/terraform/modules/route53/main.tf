locals {
  # DNS flow (DEV):
  # - admin.<domain> and passenger.<domain> point to S3 website endpoints (no CloudFront).
  # - driver.<domain> points to the shared ALB (host-based routing forwards to driver EC2).
  #
  # WHY: Cost minimization (no CloudFront) and simplicity for DEV.

  use_s3_alias = var.s3_website_zone_id != ""
}

# -----------------------------------------------------------------------------
# ADMIN DNS
# -----------------------------------------------------------------------------
resource "aws_route53_record" "admin_alias" {
  count   = local.use_s3_alias ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "admin.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.admin_website_domain
    zone_id                = var.s3_website_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin_cname" {
  count   = local.use_s3_alias ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = "admin.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.admin_website_domain]
}

# -----------------------------------------------------------------------------
# PASSENGER DNS
# -----------------------------------------------------------------------------
resource "aws_route53_record" "passenger_alias" {
  count   = local.use_s3_alias ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "passenger.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.passenger_website_domain
    zone_id                = var.s3_website_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "passenger_cname" {
  count   = local.use_s3_alias ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = "passenger.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.passenger_website_domain]
}

# -----------------------------------------------------------------------------
# DRIVER DNS (to ALB)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "driver" {
  count   = var.enable_driver_record ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "driver.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = var.alb_dns_name != "" && var.alb_zone_id != ""
      error_message = "enable_driver_record=true requires alb_dns_name and alb_zone_id to be set (usually from the ALB module outputs)."
    }
  }
}
