# ========================================
# IAM POLICY DOCUMENTS - DETAILED TUTORIAL
# ========================================
#
# WHAT IS THIS FILE?
# This file defines the ACTUAL PERMISSIONS that IAM roles have.
# Think of it like a list of rules:
#   - "Who can do what?"
#   - "On what resources?"
#   - "Under what conditions?"
#
# WHY SEPARATE FILE?
# Policies are complex JSON documents.
# Terraform's aws_iam_policy_document makes writing JSON easier:
#   - No manual JSON syntax (Terraform handles it)
#   - Easier to read and maintain
#   - Can be reused across multiple roles
#
# KEY CONCEPTS:
#   - Statement = One rule
#   - Effect = Allow or Deny
#   - Actions = What can be done (e.g., "s3:GetObject")
#   - Resources = What it applies to (e.g., specific S3 bucket)
#   - Condition = When the rule applies (optional)

# ========================================
# EC2 ASSUME ROLE POLICY (TRUST POLICY)
# ========================================
#
# WHAT IS THIS?
# The "TRUST POLICY" - controls WHO can use an IAM role
# Think of it like a key that unlocks who gets to use the role.
#
# KEY DIFFERENCE FROM PERMISSION POLICIES:
#   - Permission Policy = "What can this role do?" (used IN the role)
#   - Trust Policy = "Who can use this role?" (who assumes it)
#
# WITHOUT THIS:
# Even if a role has great permissions, nobody can use it!
#
data "aws_iam_policy_document" "ec2_assume_role" {
  # STATEMENT: "EC2 service can assume this role"
  statement {
    effect = "Allow"

    # ARGUMENT: principals
    # WHAT IT DOES: Specifies WHO can use this role
    # TYPES:
    #   - "Service" = AWS services (EC2, Lambda, etc.)
    #   - "AWS" = AWS accounts or users/roles
    #   - "Federated" = External identity providers (GitHub, Google, etc.)
    # WHY "Service": EC2 is an AWS service, not a user
    principals {
      type = "Service"
      # SECURITY NOTE: Only trust the services you actually need
      identifiers = ["ec2.amazonaws.com"]
    }

    # ARGUMENT: actions
    # VALUE: ["sts:AssumeRole"]
    # WHAT IT MEANS: Allow assuming (using) this role
    # WHY "sts:AssumeRole": STS = Security Token Service (AWS security service)
    #   - "sts:AssumeRole" = action to assume (use) a role
    #   - "sts:AssumeRoleWithWebIdentity" = for federated (GitHub OIDC)
    #   - "sts:AssumeRoleWithSAML" = for enterprise SAML
    # RESULT: EC2 can now use this role when instances start
    actions = ["sts:AssumeRole"]
  }
}

# ========================================
# BACKEND API PERMISSION POLICY
# ========================================
#
# WHAT IS THIS?
# The permission policy for the backend API role.
# Defines WHAT the backend can do after EC2 assumes the role.
#
# LEAST PRIVILEGE PRINCIPLE:
# "Grant ONLY what is needed, nothing more"
#
# WHY?
#   - If backend is compromised, attacker CAN'T access S3
#   - If code has bug, it CAN'T accidentally delete everything
#   - Limits blast radius of security incidents
#
data "aws_iam_policy_document" "backend_api" {
  # ========================================
  # STATEMENT 1: CloudWatch Logs - Write Permission
  # ========================================
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/ec2/${var.environment}-${var.project_name}-backend*"
    ]
  }

  # ========================================
  # STATEMENT 2: Secrets Manager - Read Permissions (CONDITIONAL)
  # ========================================
  dynamic "statement" {
    for_each = length(var.secrets_manager_arns) > 0 ? [1] : []
    content {
      sid    = "SecretsManagerReadDBCreds"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      resources = var.secrets_manager_arns
    }
  }

  # ========================================
  # STATEMENT 3: KMS - Decrypt Permission (CONDITIONAL)
  # ========================================
  dynamic "statement" {
    for_each = length(var.secrets_manager_arns) > 0 ? [1] : []
    content {
      sid    = "KMSDecryptSecrets"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      # WARNING: This looks too permissive, BUT there's a CONDITION below!
      resources = ["*"]
      condition {
        # CONDITION TYPE: StringEquals
        # VALUE: variable must EQUAL the value exactly
        # OTHER TYPES:
        #   - StringLike: Pattern matching (supports *)
        #   - StringNotEquals: Must NOT equal
        #   - IpAddress: For IP restrictions
        #   - Bool: For true/false checks
        test = "StringEquals"

        # VARIABLE TO CHECK
        variable = "kms:ViaService"

        # RESULT: Backend can't accidentally use KMS to decrypt other things
        values = ["secretsmanager.*.amazonaws.com"]
      }
    }
  }

  # ========================================
  # STATEMENT 4: RDS IAM Database Authentication
  # ========================================
  dynamic "statement" {
    for_each = var.rds_resource_id != "" ? [1] : []
    content {
      sid    = "RDSIAMAuthentication"
      effect = "Allow"
      actions = [
        "rds-db:connect"
      ]
      resources = [
        "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${var.rds_resource_id}/${var.rds_db_user}"
      ]
    }
  }
}

# ========================================
# DRIVER WEB PERMISSION POLICY
# ========================================
data "aws_iam_policy_document" "driver_web" {
  # STATEMENT: CloudWatch Logs Write Permission
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