# ================================================================================
# KMS KEY - SNS TOPIC ENCRYPTION (CUSTOMER MANAGED)
# ================================================================================
#
# Trivy/Aqua check AVD-AWS-0136 requires SNS topics to use a customer-managed KMS
# key instead of the AWS-managed alias/aws/sns.
#

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "sns_kms" {
  statement {
    sid = "EnableRootPermissions"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid = "AllowSNSUseOfKey"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "sns" {
  description         = "${var.environment}-${var.project_name} SNS topic encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.sns_kms.json

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-sns"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "sns-encryption"
  })
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${var.environment}-${var.project_name}-sns"
  target_key_id = aws_kms_key.sns.key_id
}
