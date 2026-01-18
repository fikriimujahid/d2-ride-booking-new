# ==============================================================================
# TERRAFORM BOOTSTRAP MODULE - MAIN CONFIGURATION FILE
# ==============================================================================
#
# WHAT THIS MODULE DOES:
# This module sets up the "bootstrap" infrastructure for your AWS account.
# "Bootstrap" means "the initial setup that makes everything else possible."
# Think of it like building the foundation of a house before you build the rooms.
#
# WHEN IT IS USED:
# This runs ONCE when you first set up your AWS account for this project.
# It creates the IAM roles and permissions that your CI/CD pipeline (GitHub Actions)
# needs to deploy your application automatically.
#
# WHICH AWS SERVICES IT TOUCHES:
# - IAM (Identity and Access Management): Creates roles and permissions
# - S3 (Simple Storage Service): Grants access to storage buckets
# - EC2 (Elastic Compute Cloud): Grants access to virtual servers
# - SSM (Systems Manager): Allows remote command execution
# - CloudWatch: Allows reading logs and metrics
#
# WHY THIS EXISTS:
# GitHub Actions needs permission to deploy your app to AWS. Instead of storing
# AWS passwords in GitHub (insecure!), we use "OIDC" - a secure way for GitHub
# to prove its identity to AWS without passwords.
#
# ==============================================================================

# ==============================================================================
# DATA SOURCE: AWS Account Information
# ==============================================================================
#
# WHAT IS A "DATA SOURCE" IN TERRAFORM?
# A data source is like asking AWS "hey, tell me about something that already exists."
# We're not creating anything new here, just fetching information.
#
# WHAT THIS SPECIFIC DATA SOURCE DOES:
# This fetches information about YOUR current AWS account:
# - Account ID (a 12-digit number that uniquely identifies your AWS account)
# - User ID (who is running this Terraform)
# - ARN (Amazon Resource Name - like a full address for your account)
#
# WHAT IF WE REMOVED THIS?
# If we're not using data.aws_caller_identity.current.account_id anywhere else
# in this file, removing it won't break anything. However, it's often kept for
# future reference or debugging purposes.
data "aws_caller_identity" "current" {}

# ==============================================================================
# LOCALS: GitHub OIDC Subjects (Who May Assume Roles)
# ==============================================================================
# WHAT IS "LOCALS" IN TERRAFORM?
# "locals" is like creating variables inside this file that we can reuse.
# Think of it like defining shortcuts or calculated values.
#
# WHAT IS AN "OIDC SUBJECT"?
# When GitHub Actions tries to access AWS, it says "I am GitHub Actions from
# this specific repo and branch." This identity statement is called a "subject."
#
# WHY DO WE NEED THIS LIST?
# Security! We're creating a whitelist of which GitHub workflows are allowed
# to deploy to AWS. It's like saying "only these specific GitHub workflows
# can unlock the door to our AWS account."
#
# UNDERSTANDING THE FORMAT:
# "repo:owner/repo-name:ref:refs/heads/dev"
#   └─┬─┘ └────┬────────┘ └──────┬─────────┘
#     │        │                  │
#     │        │                  └─ The Git branch name
#     │        └─ Your GitHub repository
#     └─ Always starts with "repo:"
#
# WHAT IF WE REMOVED A LINE?
# If you remove "repo:${var.github_repo}:ref:refs/heads/dev", then GitHub
# Actions running from the dev branch will be DENIED access to AWS.
# Deployments from that branch will fail!
locals {
  allowed_subs = [
    # DEV BRANCH: When code is pushed to the 'dev' branch
    "repo:${var.github_repo}:ref:refs/heads/dev",

    # DEV ENVIRONMENT: When manually deploying to 'dev' environment
    # (GitHub allows you to define "environments" like dev, staging, prod)
    "repo:${var.github_repo}:environment:dev",

    # STAGING BRANCH: (Currently commented out/disabled)
    # Uncomment these two lines if you want to enable staging deployments
    #"repo:${var.github_repo}:ref:refs/heads/staging",
    #"repo:${var.github_repo}:environment:staging",

    # MAIN BRANCH: When code is pushed to the 'main' branch (production)
    "repo:${var.github_repo}:ref:refs/heads/main",

    # MAIN ENVIRONMENT: Alternative way to deploy to production
    "repo:${var.github_repo}:environment:main",

    # PULL REQUESTS: When someone opens a PR (Pull Request)
    # This allows GitHub Actions to run tests on PRs before merging
    # NOTE: You might want to give PR workflows LIMITED permissions
    "repo:${var.github_repo}:pull_request",
  ]
}

# ==============================================================================
# CI/CD ROLE: github-actions-deploy-role
# ==============================================================================
resource "aws_iam_role" "github_actions_deploy_role" {
  # If you change this, you must update your GitHub Actions workflows!
  name = "github-actions-deploy-role"

  # ASSUME ROLE POLICY: "Who is allowed to use this role?"
  assume_role_policy = jsonencode({
    # Version: This is always "2012-10-17" for IAM policies
    Version = "2012-10-17"

    # Statement: A list of permission rules (we have one rule here)
    Statement = [{
      Effect = "Allow"

      # Principal: WHO is allowed to assume this role?
      # "Federated" means "an external identity provider"
      Principal = {
        Federated = var.github_oidc_provider_arn
      }

      # Action: WHAT action is being allowed?
      # "AssumeRoleWithWebIdentity" means "log in using a web-based identity token"
      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }

        StringLike = {
          # SECURITY IMPORTANCE:
          # Without this condition, ANY GitHub repository could use this role!
          # This line ensures ONLY your specific repo (and branches) can deploy.
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
    Version = "2012-10-17" # Standard IAM policy version (don't change)

    # Statement: Array of permission rules
    # Each {} block below is one permission rule
    Statement = [
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #1: EC2 Deployment Access
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "EC2DeploymentAccess"
        Effect = "Allow"

        # ACTIONS: What EC2 operations are allowed?
        Action = [
          "ec2:DescribeInstances", # See list of running servers
          "ec2:DescribeTags",      # View tags/labels on servers
          "ec2:CreateTags"         # Add/update tags on servers
        ]

        # ⚠️ SECURITY NOTE:
        # Using "*" is broad! In production, you might want to limit this to
        # specific instances using ARNs like:
        # "arn:aws:ec2:us-east-1:123456789:instance/i-xxxxx"
        Resource = "*"
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #2: S3 Artifacts Upload
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "S3ArtifactsUpload"
        Effect = "Allow"

        # ACTIONS: What S3 operations are allowed?
        Action = [
          "s3:PutObject", # Upload files to S3
          "s3:GetObject", # Download files from S3
          "s3:ListBucket" # View list of files in bucket
        ]

        Resource = [
          "arn:aws:s3:::${var.project}-deployments-*",  # The bucket itself
          "arn:aws:s3:::${var.project}-deployments-*/*" # All files in bucket (/* = all objects)
        ]
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #3: S3 Bootstrap Artifacts - Objects
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "S3BootstrapArtifactsObjects"
        Effect = "Allow"

        Action = [
          "s3:PutObject",           # Upload files
          "s3:GetObject",           # Download files
          "s3:AbortMultipartUpload" # Cancel large file uploads if they fail
        ]

        Resource = "arn:aws:s3:::${var.project}-*-bootstrap/artifacts/*"
      },
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #4: S3 Bootstrap Artifacts - List
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "S3BootstrapArtifactsList"
        Effect = "Allow"

        Action = [
          "s3:ListBucket" # View the list of files in the bucket
        ]

        # ListBucket is a BUCKET-level operation, so it needs a separate rule
        Resource = "arn:aws:s3:::${var.project}-*-bootstrap"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "artifacts/*", # Files inside artifacts/ folder
              "artifacts"    # The artifacts folder itself
            ]
          }
        }
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #5: S3 Static Site Admin - Buckets
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "S3StaticSiteAdminBuckets"
        Effect = "Allow"

        Action = [
          "s3:ListBucket",       # View files in the bucket
          "s3:GetBucketLocation" # Find out which AWS region the bucket is in
        ]

        Resource = [
          "arn:aws:s3:::${var.project}-*-admin-*"
        ]
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #6: S3 Static Site Admin - Objects
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "S3StaticSiteAdminObjects"
        Effect = "Allow"

        Action = [
          "s3:PutObject",           # Upload new/updated files
          "s3:GetObject",           # Download files
          "s3:DeleteObject",        # Delete old files
          "s3:AbortMultipartUpload" # Cancel failed large uploads
        ]

        Resource = [
          "arn:aws:s3:::${var.project}-*-admin-*/*"
        ]
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #7: S3 Static Site Driver - Buckets
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #8: S3 Static Site Driver - Objects
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #9: CloudWatch Read-Only
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"

        Action = [
          # Get metric data (e.g., CPU usage over the last hour)
          "cloudwatch:GetMetricData",

          # Search through log files (e.g., find all error messages)
          "logs:FilterLogEvents",

          # Read raw log entries (e.g., see the last 100 log lines)
          "logs:GetLogEvents"
        ]

        # ⚠️ SECURITY NOTE:
        # This allows reading ALL logs in your account. If you have sensitive
        # logs (e.g., payment processing), consider restricting this to
        # specific log groups:
        # "arn:aws:logs:*:*:log-group:/aws/application-name/*"
        #
        Resource = "*"
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #10: SSM Send Command to Tagged Instances
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #11: SSM Send Command Document
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "SSMSendCommandDocument"
        Effect = "Allow"

        Action = [
          "ssm:SendCommand"
        ]

        Resource = [
          "arn:aws:ssm:*::document/AWS-RunShellScript", # AWS public document
          "arn:aws:ssm:*:*:document/AWS-RunShellScript" # Account-specific reference
        ]
      },

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # PERMISSION RULE #12: SSM Get Command Invocation
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      {
        Sid    = "SSMGetCommandInvocation"
        Effect = "Allow"

        Action = [
          # Get detailed results of a specific command
          "ssm:GetCommandInvocation",

          # List all command invocations (history of commands run)
          "ssm:ListCommandInvocations",

          # List all commands (summary view)
          "ssm:ListCommands"
        ]

        # 🔒 SECURITY NOTE:
        # This is read-only (just viewing status), so "*" is generally safe.
        # However, command output might contain sensitive data (passwords, keys).
        # In high-security environments, consider restricting to specific
        # command IDs or instances.
        #
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
# POLICY ATTACHMENT: Connect Policy to Role
# ==============================================================================
resource "aws_iam_role_policy_attachment" "github_actions_deploy_attach" {
  role       = aws_iam_role.github_actions_deploy_role.name
  policy_arn = aws_iam_policy.github_actions_deploy_policy.arn
}