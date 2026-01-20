variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "aws_region" {
  type        = string
  description = "AWS region (used to construct endpoint service names)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Interface endpoints (typically private subnets)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR (used to allow clients to connect to endpoints on 443)"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
