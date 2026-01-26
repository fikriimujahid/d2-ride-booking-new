output "instance_id" {
  value       = aws_instance.backend.id
  description = "EC2 instance ID"
}

output "private_ip" {
  value       = aws_instance.backend.private_ip
  description = "EC2 private IP (ALB target or SSM target)"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.service.name
  description = "CloudWatch log group for this service"
}
