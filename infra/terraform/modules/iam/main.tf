# ========================================
# BACKEND API ROLE (NestJS Application)
# ========================================
#
# WHAT IS THIS?
# Think of this as a "job description" for the backend server. The server will use this role to access AWS services.
#
# WHY IS THIS NEEDED?
# 1. Backend server needs to fetch database passwords from Secrets Manager
# 2. Backend server needs to send logs to CloudWatch for debugging
# 3. Backend server should NOT access S3, DynamoDB, or other services
resource "aws_iam_role" "backend_api" {
  name = "${var.environment}-${var.project_name}-backend-api"

  # ARGUMENT: assume_role_policy
  # WHAT IT DOES: This is the "TRUST POLICY" - controls WHO can use this role
  # WHY IT MATTERS: Without this, nobody can use the role (not even EC2)
  # WHO CAN USE IT: Only "ec2.amazonaws.com" service (EC2 instances)
  # WHAT IT SAYS: "EC2 service, you are TRUSTED to use this role"
  # WHAT IF CHANGED: Remove this and EC2 can't use the role, your app breaks
  # DATA SOURCE: Defined in policies.tf - this references that definition
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for backend API (NestJS) - ${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Service     = "backend-api"
      Environment = var.environment
    }
  )
}

# ========================================
# ATTACHING PERMISSIONS TO BACKEND ROLE
# ========================================
# IMPORTANT CONCEPT: A role with no permissions is useless. This block gives the backend role actual permissions.
#
# TWO WAYS TO ATTACH PERMISSIONS:
#   1. Inline policy (below) - permissions written directly to the role
#   2. Managed policy (below) - AWS-provided reusable policies
#
# WHICH TO USE?
#   - Inline: For custom permissions specific to this service
#   - Managed: For AWS standard permissions (SSM, S3, etc.)

# INLINE POLICY: Backend API permissions
# WHAT IT DOES: Attaches custom permissions to the backend_api role
# WHERE ARE PERMISSIONS DEFINED: In policies.tf (data.aws_iam_policy_document.backend_api)
# WHAT PERMISSIONS: Listed in policies.tf
resource "aws_iam_role_policy" "backend_api" {
  name = "backend-api-policy"

  # ARGUMENT: role
  # WHAT IT DOES: Attaches this policy to the backend_api role
  # WHY THIS VALUE: aws_iam_role.backend_api.id gets the role's ID
  # WHAT IF CHANGED: Role won't have these permissions, app breaks
  role = aws_iam_role.backend_api.id

  # ARGUMENT: policy
  # WHAT IT DOES: Contains the actual permissions
  # FORMAT: JSON document (defined in policies.tf)
  # HOW IT'S CREATED: Terraform converts aws_iam_policy_document to JSON
  # WHAT IT SAYS: "Allow EC2 to read secrets, write logs, auth to RDS"
  policy = data.aws_iam_policy_document.backend_api.json
}

# AWS MANAGED POLICY: Session Manager access
# WHAT IT DOES: Allows engineers to log into EC2 instances without SSH keys
# WHY IT'S NEEDED: Instead of using SSH keys (risky!), use AWS Session Manager
# HOW IT WORKS: 
#   1. Engineer runs: "aws ssm start-session --target instance-id"
#   2. AWS checks if engineer is authorized (in IAM)
#   3. AWS opens secure connection to instance
#   4. No SSH keys, no open ports - more secure!
resource "aws_iam_role_policy_attachment" "backend_api_ssm_core" {
  # ARGUMENT: role
  # WHAT IT DOES: Name of the role to attach this policy to
  role = aws_iam_role.backend_api.name

  # ARGUMENT: policy_arn
  # WHY THIS SPECIFIC POLICY: Provides minimum permissions for Session Manager
  # WHAT IF CHANGED: Engineers can't log into instances without SSH keys
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# INSTANCE PROFILE: Bridge between EC2 and IAM role
# WHAT IS THIS?
# An instance profile is a CONTAINER that holds an IAM role. EC2 instances use instance profiles, not roles directly.
#
# ANALOGY: 
#   - IAM role = the actual certificate of credentials
#   - Instance profile = the wallet that holds the certificate
#   - EC2 instance = the person using the wallet
#
# WHY IS THIS NEEDED?
# When you launch an EC2 instance, you assign an instance profile (not a role).
# The instance profile contains the role inside.
#
# WHAT HAPPENS WHEN ATTACHED:
#   1. EC2 instance automatically gets the role's permissions
#   2. Instance can fetch temporary credentials from metadata service
#   3. Instance uses those credentials to access AWS services
#   4. Credentials rotate automatically (no secret key management!)
#
resource "aws_iam_instance_profile" "backend_api" {
  name = "${var.environment}-${var.project_name}-backend-api"

  # ARGUMENT: role
  # WHAT IT DOES: Puts the IAM role INSIDE this instance profile
  # WHY IT MATTERS: Without this, the profile is empty and useless
  # NOTE: When you create instance profile, you assign one role to it
  # WHAT IF CHANGED: Instance profile won't contain the role, EC2 has no permissions
  role = aws_iam_role.backend_api.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Environment = var.environment
    }
  )
}

# ========================================
# DRIVER WEB ROLE (Next.js Frontend on EC2)
# ========================================
#
# WHAT IS THIS?
# Think of this as a "job description" for the frontend server.
# This is DIFFERENT from the backend role!
#
# IMPORTANT DIFFERENCE FROM BACKEND:
# - Backend: Needs access to database and secrets (HIGH risk)
# - Frontend: DOES NOT need access to secrets (LOW risk)
#
# WHY? Because the frontend is a web server that serves HTML/JavaScript.
# The JavaScript runs in the user's browser, not the server.
#
# WHAT DOES THIS FRONTEND NEED?
#   1. Write logs to CloudWatch (for debugging server-side errors)
#   2. SSH Session Manager access (for engineers to manage the server)
#   3. NOTHING ELSE - especially NOT database credentials!
#
# WHERE DO CREDENTIALS COME FROM?
# - Frontend gets JWT tokens from Cognito authentication service
# - JWT tokens are temporary, limited-privilege, and don't touch AWS
# - Much safer than giving frontend AWS credentials!
#
resource "aws_iam_role" "driver_web" {
  name = "${var.environment}-${var.project_name}-driver-web"

  # ARGUMENT: assume_role_policy
  # WHAT IT DOES: This is the "TRUST POLICY" - controls WHO can use this role
  # WHO CAN USE: Only "ec2.amazonaws.com" service (EC2 instances)
  # WHAT IT SAYS: "EC2 service, you are TRUSTED to use this role"
  # WHAT IF CHANGED: Remove this and EC2 can't use the role, frontend breaks
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for driver web app (Next.js) - ${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Service     = "driver-web"
      Environment = var.environment
    }
  )
}

# INLINE POLICY: Driver web permissions
# WHAT IT DOES: Attaches custom permissions to the driver_web role
# WHERE DEFINED: In policies.tf (data.aws_iam_policy_document.driver_web)
# WHAT PERMISSIONS: CloudWatch logs ONLY (no secrets, no database)
resource "aws_iam_role_policy" "driver_web" {
  name = "driver-web-policy"

  # ARGUMENT: role
  # WHAT IT DOES: Attaches this policy to the driver_web role
  # WHY THIS VALUE: aws_iam_role.driver_web.id gets the role's ID
  # WHAT IF CHANGED: Role won't have these permissions, app can't write logs
  role = aws_iam_role.driver_web.id

  # ARGUMENT: policy
  # WHAT IT DOES: Contains the actual permissions (JSON format)
  # DEFINED IN: policies.tf (aws_iam_policy_document.driver_web)
  # WHAT IT SAYS: "Allow writing logs to CloudWatch only"
  policy = data.aws_iam_policy_document.driver_web.json
}

# AWS MANAGED POLICY: Session Manager access
# WHAT IT DOES: Allows engineers to remotely log into EC2 instances
# WHY IT'S NEEDED: Secure way to access servers without SSH keys
# HOW IT WORKS: Same as backend (see explanation above)
resource "aws_iam_role_policy_attachment" "driver_web_ssm_core" {
  # ARGUMENT: role
  # WHAT IT DOES: Attaches policy to this role
  role = aws_iam_role.driver_web.name

  # ARGUMENT: policy_arn
  # WHAT IT DOES: Identifies which AWS policy to attach
  # WHY THIS ONE: Provides Session Manager permissions
  # WHAT IF CHANGED: Engineers can't access instances
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# INSTANCE PROFILE: Bridge between EC2 and IAM role
# WHAT IT DOES: Holds the driver_web role for attachment to EC2
# WHY IT'S NEEDED: EC2 instances use instance profiles, not roles directly
# (See explanation in backend_api section above)
resource "aws_iam_instance_profile" "driver_web" {
  name = "${var.environment}-${var.project_name}-driver-web"

  # ARGUMENT: role
  # WHAT IT DOES: Puts the driver_web role INSIDE this instance profile
  # WHAT IF CHANGED: Instance profile is empty, EC2 has no permissions
  role = aws_iam_role.driver_web.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Environment = var.environment
    }
  )
}
# ========================================
# CONSOLIDATED APP HOST ROLE (DEV ONLY)
# ========================================
# DEV-ONLY: Single role for both backend-api and web-driver on one EC2 instance
# PROD: Must use separate roles for security isolation
#
# PERMISSIONS MERGED:
# - CloudWatch Logs (both /dev/backend-api and /dev/web-driver)
# - SSM Parameter Store (both service configs)
# - RDS IAM Auth (backend-api only)
# - S3 deployment artifacts (both apps/backend and apps/frontend)
# - Cognito (backend-api only)
# - Secrets Manager (backend-api only, if configured)
resource "aws_iam_role" "app_host" {
  name               = "${var.environment}-${var.project_name}-app-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for consolidated app host (backend-api + web-driver) - ${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-app-host"
      Service     = "app-host"
      Services    = "backend-api+web-driver"
      Environment = var.environment
      Comment     = "DEV-ONLY Consolidated role for backend-api and web-driver"
    }
  )
}

# Attach consolidated permissions
resource "aws_iam_role_policy" "app_host" {
  name   = "app-host-policy"
  role   = aws_iam_role.app_host.id
  policy = data.aws_iam_policy_document.app_host.json
}

# SSM managed instance core
resource "aws_iam_role_policy_attachment" "app_host_ssm_core" {
  role       = aws_iam_role.app_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for consolidated app host
resource "aws_iam_instance_profile" "app_host" {
  name = "${var.environment}-${var.project_name}-app-host"
  role = aws_iam_role.app_host.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-app-host"
      Environment = var.environment
      Comment     = "DEV-ONLY: Consolidated instance profile"
    }
  )
}

# ========================================

# SSM SERVICE ROLE (Run Command output -> CloudWatch Logs)

# ========================================

# This role is used by SSM *service* when you enable --cloud-watch-output-config.

# Without it, CloudWatch output can be enabled but still not appear.



