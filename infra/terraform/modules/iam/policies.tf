# ========================================
# IAM Policy Documents
# ========================================
# Purpose: Define least-privilege IAM policies as data sources
# WHY: Separating policies from roles improves readability and reusability

# ----------------------------------------
# EC2 AssumeRole Policy (Trust Policy)
# ----------------------------------------
# WHY: Allows EC2 instances to assume IAM roles
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# ----------------------------------------
# Backend API Policy
# ----------------------------------------
# WHY: NestJS API needs ONLY:
#   1. Read DB credentials from Secrets Manager
#   2. Write logs to CloudWatch
#   NO broad permissions (no S3, no DynamoDB, etc.)
data "aws_iam_policy_document" "backend_api" {
  # CloudWatch Logs - Write Only
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    # WHY: Scope to project-specific log groups only
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/ec2/${var.environment}-${var.project_name}-backend*"
    ]
  }

  # Secrets Manager - Read DB Credentials ONLY
  # NOTE: Conditional statement - only added if secrets_manager_arns is not empty
  dynamic "statement" {
    for_each = length(var.secrets_manager_arns) > 0 ? [1] : []
    content {
      sid    = "SecretsManagerReadDBCreds"
      effect = "Allow"

      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]

      # WHY: Only allow access to DB credential secrets (nothing else)
      # Pattern: /dev/ridebooking/db/*
      resources = var.secrets_manager_arns
    }
  }

  # KMS - Decrypt Secrets Manager secrets
  # WHY: Secrets Manager uses KMS for encryption
  # NOTE: Conditional statement - only added if secrets_manager_arns is not empty
  dynamic "statement" {
    for_each = length(var.secrets_manager_arns) > 0 ? [1] : []
    content {
      sid    = "KMSDecryptSecrets"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      # WHY: Only allow decryption of Secrets Manager default key
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.*.amazonaws.com"]
      }
    }
  }
}

# ----------------------------------------
# Driver Web Policy
# ----------------------------------------
# WHY: Driver web app (Next.js) needs ONLY CloudWatch Logs
#   NO access to secrets (frontend gets JWT from Cognito)
#   NO S3 access (static assets served via CDN in later phases)
data "aws_iam_policy_document" "driver_web" {
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:*:*:log-group:/aws/ec2/${var.environment}-${var.project_name}-driver*"
    ]
  }
}

# ----------------------------------------
# CI/CD Role (GitHub OIDC) - AssumeRole Policy
# ----------------------------------------
# WHY: Allows GitHub Actions to assume role via OIDC (no long-lived credentials)
# NOTE: This is a PLACEHOLDER - will be implemented in Phase 4
data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # WHY: Restrict to specific GitHub org/repo
    # NOTE: Update with actual GitHub org/repo in Phase 4
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:YOUR_ORG/YOUR_REPO:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ----------------------------------------
# CI/CD Role Policy
# ----------------------------------------
# WHY: GitHub Actions needs to deploy infrastructure and applications
# NOTE: This is a PLACEHOLDER - permissions will be refined in Phase 4
data "aws_iam_policy_document" "cicd" {
  # Terraform State Access (for CI/CD)
  statement {
    sid    = "TerraformStateAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    # WHY: CI/CD needs to read/write Terraform state
    # NOTE: Update with actual state bucket ARN
    resources = [
      "arn:aws:s3:::${var.environment}-${var.project_name}-tfstate",
      "arn:aws:s3:::${var.environment}-${var.project_name}-tfstate/*"
    ]
  }

  # Placeholder for ECR, ECS, Lambda permissions
  # WHY: Will be added in Phase 4 when deploying containers
  statement {
    sid    = "PlaceholderForFuturePermissions"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }
}
