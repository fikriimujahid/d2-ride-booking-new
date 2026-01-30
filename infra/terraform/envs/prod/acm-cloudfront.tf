# ================================================================================
# CERTIFICATE (CloudFront) - ACM in us-east-1 (required for CloudFront aliases)
# ================================================================================

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = local.admin_domain
  subject_alternative_names = [local.driver_domain, local.passenger_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-cloudfront-cert"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "cloudfront"
    Domain      = local.domain_base
  })
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = false
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_cert_validation : record.fqdn]
}
