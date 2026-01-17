# ========================================
# IAM Module - Main Configuration
# ========================================
# Purpose: Create least-privilege IAM roles for DEV environment
# Principle: Grant ONLY what each service needs, nothing more

# ----------------------------------------
# VALIDATION CHECKLIST (Phase 3)
# ----------------------------------------
# ✓ IAM roles follow least privilege
# ✓ No wildcard resources except where AWS requires it
# ✓ Policies use data sources (no inline JSON)
# ✓ Roles are clearly named with environment prefix
# ✓ Backend role: ONLY Secrets Manager (DB) + CloudWatch + SSM core
# ✓ Driver web role: ONLY CloudWatch + SSM core
# ✓ CI/CD role: Placeholder for GitHub OIDC (Phase 4)

# ----------------------------------------
# Backend API Role (NestJS on EC2)
# ----------------------------------------
# WHY: Backend needs to:
#   1. Read DB credentials from Secrets Manager
#   2. Write application logs to CloudWatch
resource "aws_iam_role" "backend_api" {
  name               = "${var.environment}-${var.project_name}-backend-api"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  description = "IAM role for backend API (NestJS) - ${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Service     = "backend-api"
      Environment = var.environment
    }
  )
}

# Attach inline policy (from policy document)
resource "aws_iam_role_policy" "backend_api" {
  name   = "backend-api-policy"
  role   = aws_iam_role.backend_api.id
  policy = data.aws_iam_policy_document.backend_api.json
}

# Managed policy: SSM core for Session Manager access (no SSH keys)
resource "aws_iam_role_policy_attachment" "backend_api_ssm_core" {
  role       = aws_iam_role.backend_api.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for EC2 attachment
resource "aws_iam_instance_profile" "backend_api" {
  name = "${var.environment}-${var.project_name}-backend-api"
  role = aws_iam_role.backend_api.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Environment = var.environment
    }
  )
}

# ----------------------------------------
# Driver Web Role (Next.js on EC2)
# ----------------------------------------
# WHY: Driver web app is a frontend application
#   - Gets JWT from Cognito (no direct AWS credentials)
#   - Only needs CloudWatch for server-side logs
#   - NO access to secrets or databases
resource "aws_iam_role" "driver_web" {
  name               = "${var.environment}-${var.project_name}-driver-web"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  description = "IAM role for driver web app (Next.js) - ${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Service     = "driver-web"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "driver_web" {
  name   = "driver-web-policy"
  role   = aws_iam_role.driver_web.id
  policy = data.aws_iam_policy_document.driver_web.json
}

# Managed policy: SSM core for Session Manager access (no SSH keys)
resource "aws_iam_role_policy_attachment" "driver_web_ssm_core" {
  role       = aws_iam_role.driver_web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "driver_web" {
  name = "${var.environment}-${var.project_name}-driver-web"
  role = aws_iam_role.driver_web.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Environment = var.environment
    }
  )
}

# ----------------------------------------
# CI/CD Role (GitHub OIDC) - PLACEHOLDER
# ----------------------------------------
# WHY: Future use for GitHub Actions to deploy infrastructure
# NOTE: This is a PLACEHOLDER for Phase 4
#   - OIDC provider must be created first
#   - GitHub org/repo must be configured
#   - Permissions will be refined based on deployment needs

# Uncomment when OIDC provider is ready (Phase 4)
# resource "aws_iam_role" "cicd" {
#   name               = "${var.environment}-${var.project_name}-cicd"
#   assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json
#
#   description = "IAM role for CI/CD (GitHub Actions) - ${var.environment}"
#
#   tags = merge(
#     var.tags,
#     {
#       Name        = "${var.environment}-${var.project_name}-cicd"
#       Service     = "cicd"
#       Environment = var.environment
#       Status      = "Placeholder for Phase 4"
#     }
#   )
# }
#
# resource "aws_iam_role_policy" "cicd" {
#   name   = "cicd-policy"
#   role   = aws_iam_role.cicd.id
#   policy = data.aws_iam_policy_document.cicd.json
# }
