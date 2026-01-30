output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "backend_api_security_group_id" {
  description = "Backend API security group ID"
  value       = aws_security_group.backend_api.id
}

output "driver_web_security_group_id" {
  description = "Driver web security group ID"
  value       = aws_security_group.driver_web.id
}
