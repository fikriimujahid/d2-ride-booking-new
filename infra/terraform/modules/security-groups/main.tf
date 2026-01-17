# ========================================
# Security Groups Module - Main Configuration
# ========================================
# Purpose: Create least-privilege security groups for DEV environment
# Principle: Default deny, explicit allow only required traffic

# ----------------------------------------
# VALIDATION CHECKLIST (Phase 3)
# ----------------------------------------
# ✓ Security groups block lateral movement
# ✓ No SSH exposure (port 22 removed)
# ✓ No 0.0.0.0/0 unrestricted egress (ALB uses SG references)
# ✓ RDS has NO public access
# ✓ Backend API only accepts traffic from ALB
# ✓ All rules have clear descriptions (WHY)

# ----------------------------------------
# SECURITY GROUP ARCHITECTURE
# ----------------------------------------
# Internet → ALB SG → Backend API SG → RDS SG
#         → Driver Web SG (SSR)
#
# Rules:
# 1. ALB accepts HTTPS from internet (0.0.0.0/0)
# 2. Backend API accepts HTTP only from ALB
# 3. RDS accepts MySQL only from Backend API
# 4. Driver Web accepts HTTP from ALB (for Next.js SSR)

# ----------------------------------------
# ALB Security Group
# ----------------------------------------
# WHY: Application Load Balancer needs to accept HTTPS from internet
# NOTE: ALB not created yet (Phase 4), but SG is needed for planning
resource "aws_security_group" "alb" {
  name        = "${var.environment}-${var.project_name}-alb"
  description = "Security group for Application Load Balancer (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-alb"
      Environment = var.environment
      Service     = "alb"
    }
  )
}

# Inbound: HTTPS from internet
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTPS from internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-https"
    }
  )
}

# Inbound: HTTP from internet (for HTTP→HTTPS redirect)
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP from internet (redirect to HTTPS)"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-http"
    }
  )
}

# Outbound: HTTP to backend API (ALB health checks and traffic forwarding)
# WHY: ALB needs to forward traffic to backend API instances on port 3000
# SECURITY: Restricted to backend API security group only (not 0.0.0.0/0)
resource "aws_vpc_security_group_egress_rule" "alb_to_backend_api" {
  security_group_id = aws_security_group.alb.id

  description                  = "Allow HTTP to backend API targets"
  referenced_security_group_id = aws_security_group.backend_api.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-to-backend-api"
    }
  )
}

# Outbound: HTTP to driver web (ALB health checks and traffic forwarding)
# WHY: ALB needs to forward traffic to driver web instances on port 3000
# SECURITY: Restricted to driver web security group only (not 0.0.0.0/0)
resource "aws_vpc_security_group_egress_rule" "alb_to_driver_web" {
  security_group_id = aws_security_group.alb.id

  description                  = "Allow HTTP to driver web targets"
  referenced_security_group_id = aws_security_group.driver_web.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-to-driver-web"
    }
  )
}

# ----------------------------------------
# Backend API Security Group (NestJS)
# ----------------------------------------
# WHY: Backend API should ONLY accept traffic from ALB
#   - No direct internet access
#   - No SSH (use Session Manager instead)
resource "aws_security_group" "backend_api" {
  name        = "${var.environment}-${var.project_name}-backend-api"
  description = "Security group for backend API (NestJS) - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Environment = var.environment
      Service     = "backend-api"
    }
  )
}

# Inbound: HTTP from ALB only
resource "aws_vpc_security_group_ingress_rule" "backend_api_from_alb" {
  security_group_id = aws_security_group.backend_api.id

  description                  = "Allow HTTP from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000 # NestJS default port
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-from-alb"
    }
  )
}

# Outbound: HTTPS for AWS services (Secrets Manager, CloudWatch)
# WHY: Backend needs to access AWS APIs for Secrets Manager and CloudWatch Logs
# SECURITY: Restricted to VPC CIDR instead of 0.0.0.0/0 for tighter control
# NOTE: For production, use VPC endpoints for AWS services to eliminate internet egress
resource "aws_vpc_security_group_egress_rule" "backend_api_vpc_https" {
  security_group_id = aws_security_group.backend_api.id

  description = "Allow HTTPS within VPC (for VPC endpoints)"
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-https-vpc"
    }
  )
}

# Outbound: HTTP for package managers (npm, yarn)
# WHY: Backend needs to download dependencies during deployment
# SECURITY: Restricted to VPC CIDR instead of 0.0.0.0/0
# NOTE: For production, use private package registry or VPC endpoints
resource "aws_vpc_security_group_egress_rule" "backend_api_vpc_http" {
  security_group_id = aws_security_group.backend_api.id

  description = "Allow HTTP within VPC (for internal services)"
  cidr_ipv4   = var.vpc_cidr
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-http-vpc"
    }
  )
}

# Outbound: MySQL to RDS
resource "aws_vpc_security_group_egress_rule" "backend_api_to_rds" {
  security_group_id = aws_security_group.backend_api.id

  description                  = "Allow MySQL to RDS"
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-to-rds"
    }
  )
}

# ----------------------------------------
# Driver Web Security Group (Next.js)
# ----------------------------------------
# WHY: Driver web app (Next.js SSR) needs to accept traffic from ALB
resource "aws_security_group" "driver_web" {
  name        = "${var.environment}-${var.project_name}-driver-web"
  description = "Security group for driver web app (Next.js) - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Environment = var.environment
      Service     = "driver-web"
    }
  )
}

# Inbound: HTTP from ALB only
resource "aws_vpc_security_group_ingress_rule" "driver_web_from_alb" {
  security_group_id = aws_security_group.driver_web.id

  description                  = "Allow HTTP from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000 # Next.js default port
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-from-alb"
    }
  )
}

# Outbound: HTTPS within VPC
# WHY: Driver web (Next.js) needs to access internal services
# SECURITY: Restricted to VPC CIDR instead of 0.0.0.0/0
# NOTE: For production, use VPC endpoints for AWS services
resource "aws_vpc_security_group_egress_rule" "driver_web_vpc_https" {
  security_group_id = aws_security_group.driver_web.id

  description = "Allow HTTPS within VPC (for VPC endpoints)"
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-https-vpc"
    }
  )
}

# Outbound: HTTP within VPC
resource "aws_vpc_security_group_egress_rule" "driver_web_vpc_http" {
  security_group_id = aws_security_group.driver_web.id

  description = "Allow HTTP within VPC (for internal services)"
  cidr_ipv4   = var.vpc_cidr
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-http-vpc"
    }
  )
}

# ----------------------------------------
# RDS Security Group
# ----------------------------------------
# WHY: Database should ONLY accept traffic from backend API
#   - NO public internet access
#   - Access via SSM port forwarding through backend host (no bastion)
resource "aws_security_group" "rds" {
  name        = "${var.environment}-${var.project_name}-rds"
  description = "Security group for RDS MySQL - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-rds"
      Environment = var.environment
      Service     = "rds"
    }
  )
}

# Inbound: MySQL from backend API only
resource "aws_vpc_security_group_ingress_rule" "rds_from_backend" {
  security_group_id = aws_security_group.rds.id

  description                  = "Allow MySQL from backend API only"
  referenced_security_group_id = aws_security_group.backend_api.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-rds-from-backend"
    }
  )
}

# No outbound rules (RDS doesn't need to initiate connections)
