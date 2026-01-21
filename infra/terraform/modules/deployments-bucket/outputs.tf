output "bucket_name" {
  description = "S3 bucket name for deployment artifacts"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN for deployment artifacts"
  value       = aws_s3_bucket.this.arn
}
