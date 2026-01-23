variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for the base domain"
  type        = string
}

variable "domain_name" {
  description = "Base domain (e.g., d2.fikri.dev)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used only if you want alias-to-S3-website records)"
  type        = string
}

variable "s3_website_zone_id" {
  description = "Optional: S3 website hosted zone ID for your region. If empty, module falls back to CNAME (valid for subdomains)."
  type        = string
  default     = ""
}

variable "admin_website_domain" {
  description = "S3 website domain for admin site (e.g., bucket.s3-website-REGION.amazonaws.com)"
  type        = string
}

variable "passenger_website_domain" {
  description = "S3 website domain for passenger site"
  type        = string
}

variable "alb_dns_name" {
  description = "Optional: ALB DNS name for driver site"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Optional: ALB hosted zone id (required for Route53 alias)"
  type        = string
  default     = ""
}

variable "enable_driver_record" {
  description = "Whether to create the driver.<domain> Route53 record pointing at the ALB. Must be a plan-time boolean (do not derive from resource attributes)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags (not directly used by Route53 records, kept for consistency)"
  type        = map(string)
  default     = {}
}
