# ----------------------------------------------------------------------------
# VPC CIDR BLOCK
# ----------------------------------------------------------------------------
variable "vpc_cidr" {
  type = string
  description = "CIDR block for the VPC"
}

# ----------------------------------------------------------------------------
# PUBLIC SUBNET CIDR BLOCK
# ----------------------------------------------------------------------------
variable "public_subnet_cidr" {
  type = string
  description = "CIDR block for the public subnet"
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET CIDR BLOCK
# ----------------------------------------------------------------------------
variable "private_subnet_cidr" {
  type = string
  description = "CIDR block for the private subnet"
}

# ----------------------------------------------------------------------------
# SECONDARY PRIVATE SUBNET CIDR (OPTIONAL)
# ----------------------------------------------------------------------------
variable "private_subnet_cidr_secondary" {
  type = string
  description = "CIDR block for an optional secondary private subnet"
  default = null
}

# ----------------------------------------------------------------------------
# AVAILABILITY ZONE
# ----------------------------------------------------------------------------
variable "availability_zone" {
  type = string
  description = "Single AZ for subnets (DEV is single-AZ)"
}

# ----------------------------------------------------------------------------
# SECONDARY AVAILABILITY ZONE (OPTIONAL)
# ----------------------------------------------------------------------------
variable "availability_zone_secondary" {
  type = string
  description = "Secondary AZ for optional private subnet"
  default = null
}

# ----------------------------------------------------------------------------
# ENABLE NAT GATEWAY FLAG
# ----------------------------------------------------------------------------
variable "enable_nat_gateway" {
  # type: Boolean (true or false)
  type = bool
  description = "Whether to create a NAT Gateway (+ EIP) and private default route"
  default = false
}

# ----------------------------------------------------------------------------
# TAGS
# ----------------------------------------------------------------------------
variable "tags" {
  # type: map(string) means a set of key-value pairs
  # Example: { Project = "ride-booking", Environment = "dev" }
  type = map(string)
  description = "Base tags applied to all resources"
  default = {}
}
