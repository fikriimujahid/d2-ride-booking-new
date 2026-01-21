variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for backend EC2"
  type        = string
}

variable "security_group_id" {
  description = "Security group for backend EC2"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name (with SSM + CloudWatch + rds-db:connect)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size (cost aware: t3.micro/t4g.micro)"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 16
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
