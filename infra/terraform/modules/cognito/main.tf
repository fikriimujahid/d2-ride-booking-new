# ========================================
# Cognito Module - Main Configuration
# ========================================
# Purpose: Create Cognito User Pool for JWT-based authentication
# Authentication Flow: Username/Password → JWT → Backend validation
# NO Hosted UI: Frontend handles all auth UI

# ----------------------------------------
# VALIDATION CHECKLIST (Phase 3)
# ----------------------------------------
# ✓ Cognito has no Hosted UI
# ✓ Email as username (auto-verify)
# ✓ Custom attribute: role (ADMIN, DRIVER, PASSENGER)
# ✓ JWT role strategy is clear (role in custom:role claim)
# ✓ Password policy is strong but DEV-acceptable
# ✓ App client: No secret, USER_PASSWORD_AUTH enabled
# ✓ Refresh tokens enabled

# ----------------------------------------
# AUTHORIZATION STRATEGY
# ----------------------------------------
# JWT Claims Structure:
# {
#   "sub": "user-uuid",
#   "email": "user@example.com",
#   "custom:role": "DRIVER" | "PASSENGER" | "ADMIN",
#   "cognito:groups": [] // Not used (role is in custom attribute)
# }
#
# Backend Authorization:
# 1. Frontend obtains JWT from Cognito (InitiateAuth API)
# 2. Frontend sends JWT in Authorization header
# 3. Backend validates JWT signature using Cognito public keys
# 4. Backend reads "custom:role" claim for authorization
# 5. Backend enforces role-based access control (RBAC)
#
# Role Definitions:
# - ADMIN: Full access (manage users, bookings, drivers)
# - DRIVER: Driver-specific actions (accept rides, update status)
# - PASSENGER: Passenger-specific actions (book rides, rate drivers)

# ----------------------------------------
# Cognito User Pool
# ----------------------------------------
resource "aws_cognito_user_pool" "main" {
  name = "${var.environment}-${var.project_name}"

  # ----------------------------------------
  # Username Configuration
  # ----------------------------------------
  # WHY: Email as username simplifies user experience
  #   - Users don't need to remember separate username
  #   - Email is already required for verification
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # WHY: Case-insensitive email prevents duplicate accounts
  username_configuration {
    case_sensitive = false
  }

  # ----------------------------------------
  # Password Policy
  # ----------------------------------------
  # WHY: Strong passwords protect user accounts
  # NOTE: DEV uses 8 chars minimum (PROD should use 12+)
  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # ----------------------------------------
  # Custom Attributes
  # ----------------------------------------
  # WHY: Store user role in JWT for authorization
  # NOTE: Custom attributes are immutable (cannot be changed after creation)
  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true # Allow role changes (e.g., PASSENGER → DRIVER)

    # WHY: Min/Max lengths enforce valid role values
    string_attribute_constraints {
      min_length = 5  # "ADMIN" is 5 chars
      max_length = 10 # "PASSENGER" is 9 chars
    }

    # Custom attribute appears as "custom:role" in JWT
    developer_only_attribute = false
    required                 = false # Make optional to allow initial signup without role
  }

  # ----------------------------------------
  # Email Configuration
  # ----------------------------------------
  # WHY: Cognito sends verification emails
  # NOTE: Using Cognito default email (limited to 50/day)
  # TODO: Integrate SES in Phase 4 for production email
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # ----------------------------------------
  # Account Recovery
  # ----------------------------------------
  # WHY: Allow users to recover forgotten passwords via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # ----------------------------------------
  # User Pool Deletion Protection
  # ----------------------------------------
  # WHY: DEV environment can be destroyed easily
  # NOTE: Set to ACTIVE in PROD to prevent accidental deletion
  deletion_protection = "INACTIVE"

  # ----------------------------------------
  # MFA Configuration (Optional)
  # ----------------------------------------
  # WHY: MFA is optional in DEV (can be enabled per user)
  # NOTE: Consider requiring MFA for ADMIN role in PROD
  mfa_configuration = "OPTIONAL"

  # Enable software token (TOTP) MFA
  software_token_mfa_configuration {
    enabled = true
  }

  # ----------------------------------------
  # Tags
  # ----------------------------------------
  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}"
      Environment = var.environment
      Service     = "cognito"
      Purpose     = "JWT-based authentication with role-based authorization"
    }
  )
}

# ----------------------------------------
# Cognito User Pool Client (App Client)
# ----------------------------------------
# WHY: Frontend applications need app client to authenticate users
# NOTE: NO client secret (public clients like web/mobile apps)
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.environment}-${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # ----------------------------------------
  # Client Secret
  # ----------------------------------------
  # WHY: NO client secret for public clients (web/mobile)
  #   - Secrets cannot be protected in frontend code
  #   - Use PKCE for additional security (future enhancement)
  generate_secret = false

  # ----------------------------------------
  # Authentication Flows
  # ----------------------------------------
  # WHY: Enable USER_PASSWORD_AUTH for direct username/password login
  # NOTE: Hosted UI is NOT used (frontend handles all auth UI)
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH", # Direct username/password login
    "ALLOW_REFRESH_TOKEN_AUTH", # Refresh tokens for session management
    "ALLOW_USER_SRP_AUTH"       # Secure Remote Password (SRP) protocol
  ]

  # ----------------------------------------
  # Token Validity
  # ----------------------------------------
  # WHY: Balance security and user experience
  #   - Short access tokens (1 hour) limit exposure
  #   - Long refresh tokens (30 days) reduce login frequency
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # ----------------------------------------
  # OAuth Configuration
  # ----------------------------------------
  # WHY: Disable OAuth flows (not using Hosted UI)
  # NOTE: If social login is needed later, enable OAuth here
  allowed_oauth_flows                  = []
  allowed_oauth_flows_user_pool_client = false
  allowed_oauth_scopes                 = []
  callback_urls                        = []
  logout_urls                          = []

  # ----------------------------------------
  # Attribute Permissions
  # ----------------------------------------
  # WHY: Allow clients to read/write custom:role attribute
  read_attributes = [
    "email",
    "email_verified",
    "custom:role"
  ]

  write_attributes = [
    "email",
    "custom:role"
  ]

  # ----------------------------------------
  # Prevent User Existence Errors
  # ----------------------------------------
  # WHY: Don't reveal if email exists (security best practice)
  prevent_user_existence_errors = "ENABLED"
}

# ----------------------------------------
# Cognito User Pool Domain (Optional)
# ----------------------------------------
# NOTE: Only needed if using Hosted UI (we're NOT)
# Commenting out for clarity

# resource "aws_cognito_user_pool_domain" "main" {
#   domain       = "${var.environment}-${var.project_name}"
#   user_pool_id = aws_cognito_user_pool.main.id
# }
