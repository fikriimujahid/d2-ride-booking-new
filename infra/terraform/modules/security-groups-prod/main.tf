locals {
  name_prefix = "${var.environment}-${var.project_name}"
}

# =============================================================================
# PROD security groups are intentionally NOT shared with DEV.
# Why: SGs encode connectivity intent. Sharing them across envs makes it easy
# to accidentally grant DEV access into PROD paths (or vice versa), which is not auditable.
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "ALB security group (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-alb"
    Environment = var.environment
    Service     = "alb"
    ManagedBy   = "terraform"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet (redirect to HTTPS)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_security_group" "backend_api" {
  name        = "${local.name_prefix}-backend-api"
  description = "Backend API targets (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-backend-api"
    Environment = var.environment
    Service     = "backend-api"
    ManagedBy   = "terraform"
  })
}

resource "aws_security_group" "driver_web" {
  name        = "${local.name_prefix}-web-driver"
  description = "Web Driver targets (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-web-driver"
    Environment = var.environment
    Service     = "web-driver"
    ManagedBy   = "terraform"
  })
}

# ALB -> backend
resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to backend-api targets"
  referenced_security_group_id = aws_security_group.backend_api.id
  from_port                    = var.backend_api_port
  to_port                      = var.backend_api_port
  ip_protocol                  = "tcp"
}

# ALB -> driver
resource "aws_vpc_security_group_egress_rule" "alb_to_driver" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to web-driver targets"
  referenced_security_group_id = aws_security_group.driver_web.id
  from_port                    = var.driver_web_port
  to_port                      = var.driver_web_port
  ip_protocol                  = "tcp"
}

# backend <- ALB only
resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend_api.id
  description                  = "Backend API only from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.backend_api_port
  to_port                      = var.backend_api_port
  ip_protocol                  = "tcp"
}

# driver <- ALB only
resource "aws_vpc_security_group_ingress_rule" "driver_from_alb" {
  security_group_id            = aws_security_group.driver_web.id
  description                  = "Driver web only from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.driver_web_port
  to_port                      = var.driver_web_port
  ip_protocol                  = "tcp"
}

# Egress: allow HTTPS outbound (SSM, npm, OS updates). Keep narrow: 443 only.
resource "aws_vpc_security_group_egress_rule" "backend_https_out" {
  security_group_id            = aws_security_group.backend_api.id
  description                  = "HTTPS outbound for patching/SSM"
  cidr_ipv4                    = var.vpc_endpoints_security_group_id == null ? var.vpc_cidr : null
  referenced_security_group_id = var.vpc_endpoints_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "driver_https_out" {
  security_group_id            = aws_security_group.driver_web.id
  description                  = "HTTPS outbound for patching/SSM"
  cidr_ipv4                    = var.vpc_endpoints_security_group_id == null ? var.vpc_cidr : null
  referenced_security_group_id = var.vpc_endpoints_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Egress: allow MySQL within VPC (RDS). Avoid SG-to-SG here to prevent dependency cycles with the RDS module.
resource "aws_vpc_security_group_egress_rule" "backend_mysql_out" {
  security_group_id = aws_security_group.backend_api.id
  description       = "MySQL to RDS within VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 3306
  to_port           = 3306
  ip_protocol       = "tcp"
}
