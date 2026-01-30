# ----------------------------------------------------------------------------
# VPC CIDR BLOCK
# ----------------------------------------------------------------------------
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

# ----------------------------------------------------------------------------
# PUBLIC SUBNET CIDR BLOCK
# ----------------------------------------------------------------------------
variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
}

# Optional secondary public subnet to support internet-facing ALB across two AZs.
variable "public_subnet_cidr_secondary" {
  type        = string
  description = "CIDR block for an optional secondary public subnet"
  default     = null

  validation {
    condition     = var.public_subnet_cidr_secondary == null || can(cidrhost(var.public_subnet_cidr_secondary, 0))
    error_message = "public_subnet_cidr_secondary must be a valid CIDR block when set."
  }
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET CIDR BLOCK
# ----------------------------------------------------------------------------
variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private subnet"
}

# ----------------------------------------------------------------------------
# SECONDARY PRIVATE SUBNET CIDR (OPTIONAL)
# ----------------------------------------------------------------------------
variable "private_subnet_cidr_secondary" {
  type        = string
  description = "CIDR block for an optional secondary private subnet"
  default     = null

  validation {
    condition     = var.private_subnet_cidr_secondary == null || can(cidrhost(var.private_subnet_cidr_secondary, 0))
    error_message = "private_subnet_cidr_secondary must be a valid CIDR block when set."
  }
}

# ----------------------------------------------------------------------------
# AVAILABILITY ZONE
# ----------------------------------------------------------------------------
variable "availability_zone" {
  type        = string
  description = "Single AZ for subnets (DEV is single-AZ)"
}

# ----------------------------------------------------------------------------
# SECONDARY AVAILABILITY ZONE (OPTIONAL)
# ----------------------------------------------------------------------------
variable "availability_zone_secondary" {
  type        = string
  description = "Secondary AZ for optional private subnet"
  default     = null
}

# ----------------------------------------------------------------------------
# ENABLE NAT GATEWAY FLAG
# ----------------------------------------------------------------------------
variable "enable_nat_gateway" {
  # type: Boolean (true or false)
  type        = bool
  description = "Whether to create a NAT Gateway (+ EIP) and private default route"
  default     = false
}

# ----------------------------------------------------------------------------
# MULTI-AZ CONTROLS (BACKWARD-COMPATIBLE)
# ----------------------------------------------------------------------------
# NOTE:
# - The module historically supports 1 AZ by default, with an OPTIONAL second AZ
#   via the existing *_secondary variables.
# - These new variables do not change defaults, so DEV behavior is preserved.
variable "enable_multi_az" {
  type        = bool
  description = "If true, expects secondary subnet CIDRs + secondary AZ to be provided to span multiple AZs. Defaults to false to preserve DEV single-AZ behavior."
  default     = false
}

variable "az_count" {
  type        = number
  description = "Number of AZs to span (currently supported: 1 or 2). Defaults to 1 to preserve DEV behavior."
  default     = 1

  validation {
    condition     = var.az_count == 1 || var.az_count == 2
    error_message = "az_count must be 1 or 2 for this module version."
  }
}

# ----------------------------------------------------------------------------
# SUBNET TIERS (OPTIONAL) - APP + DB
# ----------------------------------------------------------------------------
# App tier CIDRs are kept as an explicit list for environment configuration
# consistency (PROD uses lists), but the module's existing variables remain the
# authoritative inputs for the app tier to avoid changing DEV state/resource names.
variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "Optional list of private app subnet CIDRs (one per AZ). Provided for config consistency; the module uses private_subnet_cidr + private_subnet_cidr_secondary for the app tier to preserve backward compatibility."
  default     = []
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "Optional list of private DB subnet CIDRs (one per AZ). When set, the module creates separate DB subnets and a dedicated route table."
  default     = []
}

# ----------------------------------------------------------------------------
# TAGS
# ----------------------------------------------------------------------------
variable "tags" {
  # type: map(string) means a set of key-value pairs
  # Example: { Project = "ride-booking", Environment = "dev" }
  type        = map(string)
  description = "Base tags applied to all resources"
  default     = {}
}
