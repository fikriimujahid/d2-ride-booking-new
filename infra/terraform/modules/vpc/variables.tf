variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private subnet"
}

variable "availability_zone" {
  type        = string
  description = "Single AZ for subnets (DEV is single-AZ)"
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to create a NAT Gateway (+ EIP) and private default route"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to all resources"
  default     = {}
}
