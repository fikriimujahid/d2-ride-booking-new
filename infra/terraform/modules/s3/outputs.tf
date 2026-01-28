output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "website_hostname" {
  description = "S3 website hostname (no scheme): <bucket>.s3-website-<region>.amazonaws.com"
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_endpoint" {
  description = "S3 website URL (http://<bucket>.s3-website-<region>.amazonaws.com)"
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}

output "website_domain" {
  description = "S3 website domain (no scheme), used for Route53 alias/CNAME"
  # NOTE: aws_s3_bucket_website_configuration.this.website_domain is expected to be
  # '<bucket>.s3-website-<region>.amazonaws.com', but in some provider versions it
  # can be returned as just 's3-website-<region>.amazonaws.com'.
  # website_endpoint is consistently the full hostname, so derive from that.
  value = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_url" {
  description = "S3 website URL (http://<bucket>.s3-website-<region>.amazonaws.com)"
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}
