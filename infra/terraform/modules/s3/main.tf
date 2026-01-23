locals {
  # Bucket names must be globally unique.
  # We include AWS account id to avoid collisions across accounts.
  bucket_name = "${var.project_name}-${var.site_name}-${var.environment}-${var.aws_account_id}"
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name        = local.bucket_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "static-website-dev"
    Site        = var.site_name
  })
}

# DEV ONLY: this bucket must be publicly readable to serve a static website.
# We explicitly disable S3 Block Public Access for this bucket.
# WARNING: Do not use this pattern for production; use CloudFront + OAC.
#
# Trivy findings suppressed (DEV-only exception):
# - AVD-AWS-0086: block public ACLs
# - AVD-AWS-0087: block public bucket policies
# - AVD-AWS-0091: ignore public ACLs
# - AVD-AWS-0093: restrict public buckets
#
#trivy:ignore:AVD-AWS-0086
#tfsec:ignore:AVD-AWS-0086
#trivy:ignore:AVD-AWS-0087
#tfsec:ignore:AVD-AWS-0087
#trivy:ignore:AVD-AWS-0091
#tfsec:ignore:AVD-AWS-0091
#trivy:ignore:AVD-AWS-0093
#tfsec:ignore:AVD-AWS-0093
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AVD-AWS-0132
#tfsec:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = "index.html"
  }

  # SPA-friendly: serve index.html for unknown paths (client-side routing).
  error_document {
    key = "index.html"
  }
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid     = "PublicReadGetObject"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.public_read.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
