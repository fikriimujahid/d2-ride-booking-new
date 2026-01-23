output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "website_endpoint" {
  description = "S3 website endpoint (http://...)"
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_domain" {
  description = "S3 website domain (no scheme), used for Route53 alias/CNAME"
  value       = aws_s3_bucket_website_configuration.this.website_domain
}
