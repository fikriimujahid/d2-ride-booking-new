# ========================================
# INDIVIDUAL SECURITY GROUP ID EXPORTS
# ========================================
# These are simple, straightforward exports:
# For each security group, we export its ID so other resources can use it
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

# ========================================
# COMPREHENSIVE SECURITY GROUP SUMMARY
# ========================================
# This output provides a human-readable overview of all security groups
# and their rules. Useful for documentation and debugging.

output "security_group_summary" {
  description = "Summary of all security groups"
  value = {
    # SECTION: ALB SECURITY GROUP SUMMARY
    alb = {
      id   = aws_security_group.alb.id
      name = aws_security_group.alb.name
      inbound = [
        "HTTPS from 0.0.0.0/0",
        "HTTP from 0.0.0.0/0"
      ]
    }

    # SECTION: BACKEND API SECURITY GROUP SUMMARY
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

    # SECTION: DRIVER WEB SECURITY GROUP SUMMARY
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
  }
}
