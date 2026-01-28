# ================================================================================
# CLOUDWATCH MODULE OUTPUTS
# ================================================================================
# These outputs expose critical information about the observability infrastructure
# so other modules or engineers can reference log groups, alarms, and SNS topics.
#
# ================================================================================

# --------------------------------------------------------------------------------
# LOG GROUP OUTPUTS
# --------------------------------------------------------------------------------
output "backend_api_log_group_name" {
  description = "CloudWatch log group name for backend-api"
  value       = aws_cloudwatch_log_group.backend_api.name
}

output "backend_api_log_group_arn" {
  description = "CloudWatch log group ARN for backend-api"
  value       = aws_cloudwatch_log_group.backend_api.arn
}

output "web_driver_log_group_name" {
  description = "CloudWatch log group name for web-driver"
  value       = aws_cloudwatch_log_group.web_driver.name
}

output "web_driver_log_group_arn" {
  description = "CloudWatch log group ARN for web-driver"
  value       = aws_cloudwatch_log_group.web_driver.arn
}

# --------------------------------------------------------------------------------
# SNS TOPIC OUTPUTS
# --------------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_name" {
  description = "SNS topic name for CloudWatch alarms"
  value       = aws_sns_topic.alarms.name
}

# --------------------------------------------------------------------------------
# ALARM OUTPUTS (CONDITIONAL)
# --------------------------------------------------------------------------------
output "ec2_cpu_alarm_name" {
  description = "EC2 CPU alarm name (empty if alarms disabled)"
  value       = var.enable_alarms && var.ec2_instance_id != "" ? aws_cloudwatch_metric_alarm.ec2_cpu_high[0].alarm_name : ""
}

output "ec2_status_check_alarm_name" {
  description = "EC2 status check alarm name (empty if alarms disabled)"
  value       = var.enable_alarms && var.ec2_instance_id != "" ? aws_cloudwatch_metric_alarm.ec2_status_check_failed[0].alarm_name : ""
}

output "rds_cpu_alarm_name" {
  description = "RDS CPU alarm name (empty if alarms disabled)"
  value       = var.enable_alarms && var.rds_instance_id != "" ? aws_cloudwatch_metric_alarm.rds_cpu_high[0].alarm_name : ""
}

output "rds_storage_alarm_name" {
  description = "RDS storage alarm name (empty if alarms disabled)"
  value       = var.enable_alarms && var.rds_instance_id != "" ? aws_cloudwatch_metric_alarm.rds_storage_low[0].alarm_name : ""
}

output "rds_connections_alarm_name" {
  description = "RDS connections alarm name (empty if alarms disabled)"
  value       = var.enable_alarms && var.rds_instance_id != "" ? aws_cloudwatch_metric_alarm.rds_connections_high[0].alarm_name : ""
}
