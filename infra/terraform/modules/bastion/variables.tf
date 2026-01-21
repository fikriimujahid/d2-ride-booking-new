variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name for naming/tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (used for optional scoped rules)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the bastion (typically public subnet)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "enable_ssh" {
  description = "Whether to allow inbound SSH (22)"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion when enable_ssh=true"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
