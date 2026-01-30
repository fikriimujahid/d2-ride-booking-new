output "autoscaling_group_name" {
  description = "ASG name"
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_arn" {
  description = "ASG ARN"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Launch template latest version"
  value       = aws_launch_template.this.latest_version
}
