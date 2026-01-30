output "bucket_name" {
  description = "S3 bucket name (origin bucket)"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "s3_kms_key_arn" {
  description = "KMS key ARN used for SSE-KMS on the origin bucket"
  value       = aws_kms_key.s3.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution id"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (e.g., dxxxxx.cloudfront.net)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "site_domain_name" {
  description = "Custom domain name for the site"
  value       = var.domain_name
}

output "site_url" {
  description = "HTTPS URL for the site"
  value       = "https://${var.domain_name}"
}
