# ================================================================================
# CLOUDWATCH MODULE VARIABLES
# ================================================================================

# --------------------------------------------------------------------------------
# GENERAL CONFIGURATION
# --------------------------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
}

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

# --------------------------------------------------------------------------------
# ALARM CONTROL
# --------------------------------------------------------------------------------
variable "enable_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms. Set to false to disable all alarms (useful during demos, load testing, or when you need silence)."
  default     = true
}

# --------------------------------------------------------------------------------
# LOG RETENTION
# --------------------------------------------------------------------------------
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days. DEV: 7-14 days. PROD: 30-90 days. Keep short to control costs."
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653"
  }
}

# --------------------------------------------------------------------------------
# EC2 MONITORING CONFIGURATION
# --------------------------------------------------------------------------------
variable "enable_ec2_monitoring" {
  type        = bool
  description = "Enable EC2 instance monitoring (must be known at plan time)"
  default     = false
}

variable "ec2_instance_id" {
  type        = string
  description = "EC2 instance ID to monitor (the consolidated app-host instance running both backend-api and web-driver)"
  default     = ""
}

variable "ec2_instance_name" {
  type        = string
  description = "EC2 instance name for alarm descriptions"
  default     = "app-host"
}

# --------------------------------------------------------------------------------
# RDS MONITORING CONFIGURATION
# --------------------------------------------------------------------------------
variable "enable_rds_monitoring" {
  type        = bool
  description = "Enable RDS instance monitoring (must be known at plan time)"
  default     = false
}

variable "rds_instance_id" {
  type        = string
  description = "RDS instance identifier to monitor"
  default     = ""
}

variable "rds_instance_name" {
  type        = string
  description = "RDS instance name for alarm descriptions"
  default     = "database"
}

# --------------------------------------------------------------------------------
# SNS NOTIFICATION CONFIGURATION
# --------------------------------------------------------------------------------
variable "alarm_email" {
  type        = string
  description = "Email address for alarm notifications. Leave empty to skip email subscription. In DEV, consider using a team distribution list instead of personal emails to avoid spam."
  default     = ""
}

# --------------------------------------------------------------------------------
# ALB / TARGET GROUP MONITORING (PROD)
# --------------------------------------------------------------------------------
variable "enable_alb_monitoring" {
  type        = bool
  description = "Enable ALB target health alarms (UnHealthyHostCount)."
  default     = false
}

variable "alb_arn_suffix" {
  type        = string
  description = "ALB ARN suffix (dimension LoadBalancer)."
  default     = ""
}

variable "backend_target_group_arn_suffix" {
  type        = string
  description = "Backend target group ARN suffix (dimension TargetGroup)."
  default     = ""
}

variable "driver_target_group_arn_suffix" {
  type        = string
  description = "Driver target group ARN suffix (dimension TargetGroup)."
  default     = ""
}

variable "alb_unhealthy_host_threshold" {
  type        = number
  description = "Alarm when UnHealthyHostCount >= this value."
  default     = 1
}

variable "alb_alarm_period_seconds" {
  type        = number
  description = "CloudWatch alarm period for ALB target health. PROD should keep this short (e.g. 60)."
  default     = 60
}

variable "alb_alarm_evaluation_periods" {
  type        = number
  description = "Evaluation periods for ALB target health alarms. PROD should be stricter than DEV."
  default     = 2
}
