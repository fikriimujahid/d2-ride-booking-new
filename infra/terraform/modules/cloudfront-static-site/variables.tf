variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name used for naming"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used to make bucket names globally unique)"
  type        = string
}

variable "site_name" {
  description = "Logical site name (e.g., web-admin, web-passenger)"
  type        = string
}

variable "domain_name" {
  description = "Full custom domain for the site (e.g., admin.example.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone id for the domain (if empty, no Route53 records are created)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  type        = string
}

variable "force_destroy" {
  description = "DEV-friendly: allow destroy even if objects exist"
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
