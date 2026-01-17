# ==============================================================================
# DATA SOURCE: AWS Account Information
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ==============================================================================
# LOCALS: GitHub OIDC Subjects (who may assume roles)
# ------------------------------------------------------------------------------
locals {
  allowed_subs = [
    "repo:${var.github_repo}:ref:refs/heads/dev", # Dev branch pushes
    "repo:${var.github_repo}:environment:dev",    # Dev environment deploys

    #"repo:${var.github_repo}:ref:refs/heads/staging",  # Staging branch pushes
    #"repo:${var.github_repo}:environment:staging",     # Staging environment deploys

    "repo:${var.github_repo}:ref:refs/heads/main", # Main branch pushes
    "repo:${var.github_repo}:environment:main",    # Main environment deploys (alternative naming)

    "repo:${var.github_repo}:pull_request/*", # All pull requests (requires wildcard)
  ]
}

# ==============================================================================
# CI/CD ROLE: github-actions-deploy-role
# ==============================================================================
resource "aws_iam_role" "github_actions_deploy_role" {
  name = "github-actions-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.github_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.allowed_subs
        }
      }
    }]
  })

  tags = {
    project     = var.project
    environment = "shared"
    managed_by  = "terraform"
  }
}

# ==============================================================================
# CI/CD POLICY: github-actions-deploy-policy
# ==============================================================================
resource "aws_iam_policy" "github_actions_deploy_policy" {
  name        = "github-actions-deploy-policy"
  description = "Policy for github-actions-deploy-role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DeploymentAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ArtifactsUpload"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-deployments-*",
          "arn:aws:s3:::${var.project}-deployments-*/*"
        ]
      },
      {
        Sid    = "S3BootstrapArtifactsObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "arn:aws:s3:::${var.project}-*-bootstrap/artifacts/*"
      },
      {
        Sid    = "S3BootstrapArtifactsList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.project}-*-bootstrap"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "artifacts/*",
              "artifacts"
            ]
          }
        }
      },
      {
        Sid    = "S3StaticSiteAdminBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-*-admin-*"
        ]
      },
      {
        Sid    = "S3StaticSiteAdminObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-*-admin-*/*"
        ]
      },
      {
        Sid    = "S3StaticSiteDriverBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-*-driver-*"
        ]
      },
      {
        Sid    = "S3StaticSiteDriverObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-*-driver-*/*"
        ]
      },
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "logs:FilterLogEvents",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMSendCommandToTaggedInstances"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/project" = var.project
          }
        }
      },
      {
        Sid    = "SSMSendCommandDocument"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ssm:*::document/AWS-RunShellScript",
          "arn:aws:ssm:*:*:document/AWS-RunShellScript"
        ]
      },
      {
        Sid    = "SSMGetCommandInvocation"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    project     = var.project
    environment = "shared"
    managed_by  = "terraform"
  }
}

# ==============================================================================
# POLICY ATTACHMENTS: Connect Policies to Roles
# ==============================================================================

resource "aws_iam_role_policy_attachment" "github_actions_deploy_attach" {
  role       = aws_iam_role.github_actions_deploy_role.name
  policy_arn = aws_iam_policy.github_actions_deploy_policy.arn
}
