output "instance_id" {
  value       = aws_instance.backend.id
  description = "Backend EC2 instance ID"
}

output "private_ip" {
  value       = aws_instance.backend.private_ip
  description = "Backend EC2 private IP (ALB target or SSM target)"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.backend.name
  description = "CloudWatch log group for backend service"
}
