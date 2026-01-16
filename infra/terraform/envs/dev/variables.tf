variable "aws_region" {
  type        = string
  description = "AWS region for the DEV environment"
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the DEV VPC"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV public subnet"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the DEV private subnet"
}

variable "availability_zone" {
  type        = string
  description = "Single AZ for DEV (fixed)"
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway (cost toggle)"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
}
