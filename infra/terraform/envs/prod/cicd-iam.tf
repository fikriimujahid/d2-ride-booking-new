# ================================================================================
# CI/CD IAM (PROD) - Dedicated GitHub Actions role
# ================================================================================

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_prod_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow either pushes to main or the GitHub Environment named "prod".
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:prod",
      ]
    }
  }
}

data "aws_iam_policy_document" "github_actions_prod_deploy" {
  statement {
    sid    = "S3UploadProdArtifacts"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      module.deployments_bucket.bucket_arn,
      "${module.deployments_bucket.bucket_arn}/apps/*"
    ]
  }

  statement {
    sid    = "S3DeployStaticSites"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      module.web_admin_static_site.bucket_arn,
      "${module.web_admin_static_site.bucket_arn}/*",
      module.web_passenger_static_site.bucket_arn,
      "${module.web_passenger_static_site.bucket_arn}/*"
    ]
  }

  statement {
    sid    = "KMSUseForStaticSiteUploads"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [
      module.web_admin_static_site.s3_kms_key_arn,
      module.web_passenger_static_site.s3_kms_key_arn
    ]
  }

  statement {
    sid    = "CloudFrontInvalidateStaticSites"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation"
    ]
    resources = [
      format(
        "arn:aws:cloudfront::%s:distribution/%s",
        data.aws_caller_identity.current.account_id,
        module.web_admin_static_site.cloudfront_distribution_id
      ),
      format(
        "arn:aws:cloudfront::%s:distribution/%s",
        data.aws_caller_identity.current.account_id,
        module.web_passenger_static_site.cloudfront_distribution_id
      )
    ]
  }

  statement {
    sid    = "SSMReadRuntimeConfig"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:*:*:parameter/${var.environment}/${var.project_name}/backend-api",
      "arn:aws:ssm:*:*:parameter/${var.environment}/${var.project_name}/backend-api/*",
      "arn:aws:ssm:*:*:parameter/${var.environment}/${var.project_name}/web-driver",
      "arn:aws:ssm:*:*:parameter/${var.environment}/${var.project_name}/web-driver/*"
    ]
  }

  statement {
    sid    = "SSMSendCommandToProdTaggedInstances"
    effect = "Allow"
    actions = [
      "ssm:SendCommand"
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ManagedBy"
      values   = ["terraform"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Service"
      values   = ["backend-api", "web-driver"]
    }
  }

  statement {
    sid    = "SSMSendCommandDocument"
    effect = "Allow"
    actions = [
      "ssm:SendCommand"
    ]
    resources = [
      "arn:aws:ssm:*::document/AWS-RunShellScript",
      "arn:aws:ssm:*:*:document/AWS-RunShellScript"
    ]
  }

  statement {
    sid    = "SSMCommandRead"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands"
    ]
    resources = ["*"]
  }

  # Explicitly disallow interactive Session Manager sessions from CI.
  statement {
    sid    = "DenySessionManagerInteractive"
    effect = "Deny"
    actions = [
      "ssm:StartSession",
      "ssm:ResumeSession",
      "ssm:TerminateSession"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "github_actions_prod_deploy" {
  name               = "github-actions-deploy-prod-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_prod_assume.json

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-github-actions-deploy"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "cicd"
  })
}

resource "aws_iam_policy" "github_actions_prod_deploy" {
  name        = "${var.environment}-${var.project_name}-github-actions-deploy"
  description = "Least-privilege CI/CD role for PROD (S3 artifacts + SSM rolling deploy)"
  policy      = data.aws_iam_policy_document.github_actions_prod_deploy.json

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "cicd"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_prod_deploy" {
  role       = aws_iam_role.github_actions_prod_deploy.name
  policy_arn = aws_iam_policy.github_actions_prod_deploy.arn
}
