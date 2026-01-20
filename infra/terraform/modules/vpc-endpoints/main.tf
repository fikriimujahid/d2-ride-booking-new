locals {
  name_prefix = "${var.environment}-${var.project_name}"
}

# Security group attached to the Interface endpoint ENIs.
# Clients in the VPC connect to these ENIs over 443.
resource "aws_security_group" "endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints"
  description = "Interface VPC endpoints security group (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc-endpoints"
    Environment = var.environment
    Service     = "vpc-endpoints"
  })
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow HTTPS from within VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-endpoints-https-from-vpc"
  })
}

# Egress isn't used much for endpoint ENIs, but allow all to avoid surprises.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow all egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-endpoints-egress-all"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ssm"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ec2messages"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ssmmessages"
    Environment = var.environment
  })
}
