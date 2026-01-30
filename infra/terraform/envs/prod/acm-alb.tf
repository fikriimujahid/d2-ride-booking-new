# ================================================================================
# CERTIFICATE (ALB) - Regional ACM (same region as ALB)
# ================================================================================

resource "aws_acm_certificate" "alb" {
  domain_name               = "*.${local.domain_base}"
  subject_alternative_names = [local.domain_base]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-alb-cert"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "alb"
    Domain      = local.domain_base
  })
}

resource "aws_route53_record" "alb_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_cert_validation : record.fqdn]
}
