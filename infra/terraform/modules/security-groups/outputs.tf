# ========================================
# Security Groups Module - Outputs
# ========================================
# Purpose: Export security group IDs for use in other modules

output "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "backend_api_security_group_id" {
  description = "Security group ID for backend API (NestJS)"
  value       = aws_security_group.backend_api.id
}

output "driver_web_security_group_id" {
  description = "Security group ID for driver web app (Next.js)"
  value       = aws_security_group.driver_web.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS MySQL"
  value       = aws_security_group.rds.id
}

# ----------------------------------------
# Security Group Summary
# ----------------------------------------
output "security_group_summary" {
  description = "Summary of all security groups"
  value = {
    alb = {
      id   = aws_security_group.alb.id
      name = aws_security_group.alb.name
      inbound = [
        "HTTPS from 0.0.0.0/0",
        "HTTP from 0.0.0.0/0"
      ]
    }
    backend_api = {
      id   = aws_security_group.backend_api.id
      name = aws_security_group.backend_api.name
      inbound = [
        "HTTP from ALB only"
      ]
      outbound = [
        "HTTPS within VPC CIDR",
        "HTTP within VPC CIDR",
        "MySQL to RDS"
      ]
    }
    driver_web = {
      id   = aws_security_group.driver_web.id
      name = aws_security_group.driver_web.name
      inbound = [
        "HTTP from ALB only"
      ]
      outbound = [
        "HTTPS within VPC CIDR",
        "HTTP within VPC CIDR"
      ]
    }
    rds = {
      id   = aws_security_group.rds.id
      name = aws_security_group.rds.name
      inbound = [
        "MySQL from backend API"
      ]
    }
  }
}
