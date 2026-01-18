# ========================================
# COGNITO MODULE - MAIN CONFIGURATION
# ========================================
#
# WHAT IS THIS FILE?
# ---------------------
# This file creates and configures AWS Cognito, which is like a "user management service."
# Think of it as a secure login system that:
#   - Stores user accounts (email, password, profile info)
#   - Handles user registration and login
#   - Issues JWT tokens (like digital ID cards) after successful login
#   - Verifies passwords and sends verification emails
#
# WHAT DOES THIS MODULE CREATE?
# ----------------------------------
# 1. A Cognito User Pool (the database that stores all users)
# 2. A Cognito App Client (the configuration that allows your frontend apps to talk to Cognito)
#
# WHY DO WE NEED COGNITO?
# ---------------------------
# Without Cognito, you'd need to:
#   - Build your own user registration system
#   - Securely store passwords (very hard to do safely!)
#   - Handle password resets and email verification
#   - Create and manage authentication tokens
#   - Worry about security vulnerabilities
# Cognito does ALL of this for you automatically!
#
# HOW DOES THE AUTHENTICATION FLOW WORK?
# ------------------------------------------
# 1. User enters email and password in your web/mobile app (Frontend)
# 2. Frontend sends credentials to Cognito (using AWS SDK)
# 3. Cognito checks if email and password are correct
# 4. If correct, Cognito returns a JWT token (a special encrypted string)
# 5. Frontend stores this JWT token
# 6. Frontend sends JWT token with every API request to Backend
# 7. Backend verifies the JWT token with Cognito's public keys
# 8. Backend reads the user's role from the JWT (ADMIN, DRIVER, or PASSENGER)
# 9. Backend allows or denies the request based on the role
#
# IMPORTANT NOTES:
# --------------------
# - This configuration does NOT use Cognito's Hosted UI (the built-in login page)
# - Your frontend apps will build their own custom login pages
# - Email is used as the username (users don't need a separate username)
# - Custom attribute "role" is stored in the JWT for authorization
# ========================================

# ========================================
# COGNITO USER POOL
# ========================================
# WHAT IS A USER POOL?
# ------------------------
# A User Pool is like a database that stores user accounts.
# Think of it as a secure vault that contains:
#   - User emails and encrypted passwords
#   - User profile information (name, role, phone, etc.)
#   - Email verification status
#   - Password reset requests
#   - Login history
resource "aws_cognito_user_pool" "main" {
  name                = "${var.environment}-${var.project_name}"
  username_attributes = ["email"]
  # After a user registers, Cognito automatically sends a verification email
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length    = var.password_minimum_length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
    # NOTE:
    # This only applies to admin-created accounts.
    # Self-registered users create their own password immediately (no temporary password).
    temporary_password_validity_days = 7
  }

  # CRITICAL WARNING:
  # Custom attributes are PERMANENT! Once created, you CANNOT: Delete, Rename them, Change their data type (String → Number)
  # If you need to change it, you must delete and recreate the entire User Pool (losing all users).
  schema {
    name                = "role"
    attribute_data_type = "String"
    # "mutable = true" just means it's POSSIBLE to change, not that anyone can change it.
    mutable = true

    string_attribute_constraints {
      min_length = 5
      max_length = 10
    }

    # DEVELOPER ONLY ATTRIBUTE
    # ----------------------------
    # WHAT IS THIS?
    # If true: Only admins/backend can read/write this attribute (users can't see it)
    # If false: Regular users can read/write this attribute (more open)
    # NOTE:
    # Even though this is false, users still can't CHANGE their role.
    # That's controlled by IAM policies and backend logic, not this setting.
    developer_only_attribute = false

    # REQUIRED ATTRIBUTE
    # ----------------------
    # WHAT DOES "required = false" MEAN?
    # If true: Every user MUST have a role when they register
    # If false: Role is optional (user can register without a role)
    # IMPORTANT:
    # Your backend API should check if a user has a role before allowing actions!
    # Don't assume every user has a role just because they're logged in.
    required = false
  }

  # --------------------------------------------------
  # EMAIL CONFIGURATION
  # --------------------------------------------------
  # WHAT IS THIS SECTION?
  # Cognito needs to send emails to users for:
  #   - Email verification (when they register)
  #   - Password reset requests (when they forget password)
  #   - Account notifications
  #
  # TWO OPTIONS FOR SENDING EMAILS:
  # 1. COGNITO_DEFAULT: Cognito uses its own email service (free but limited)
  # 2. DEVELOPER: You use Amazon SES (Simple Email Service) for more control
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  account_recovery_setting {
    # RECOVERY MECHANISM
    # ----------------------
    # WHAT IS A RECOVERY MECHANISM?
    # It's a method users can use to prove they own the account.
    # Options:
    #   - "verified_email": Send reset code to verified email
    #   - "verified_phone_number": Send reset code via SMS to verified phone
    #   - "admin_only": Only admins can reset passwords (very restrictive)
    #
    # PRIORITY:
    # If you have multiple recovery mechanisms, priority determines the order.
    # priority = 1 means this is the PRIMARY method (tried first).
    # priority = 2 would be the SECONDARY method (tried if primary fails).
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  deletion_protection = "INACTIVE"
  mfa_configuration   = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

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

# ========================================
# COGNITO USER POOL CLIENT (APP CLIENT)
# ========================================
# WHAT IS AN APP CLIENT?
# ------------------------
# An App Client is like a "key" that allows your frontend applications to talk to Cognito.
# Think of it like this:
#   - User Pool = The building (stores all users)
#   - App Client = The key card to enter the building (allows apps to authenticate users)
#
# WHY DO WE NEED IT?
# Without an App Client, your frontend apps (web/mobile) cannot:
#   - Register new users
#   - Log in users
#   - Get JWT tokens
#   - Refresh expired tokens
#   - Call any Cognito authentication APIs
#
# ONE USER POOL, MULTIPLE APP CLIENTS
# You can have multiple App Clients for the same User Pool:
#   - Web app client (for your website)
#   - Mobile app client (for iOS/Android apps)
#   - Admin app client (for admin dashboard)
# Each client can have different settings (token expiration, allowed auth flows, etc.)
#
# PUBLIC vs CONFIDENTIAL CLIENTS
# - Public clients: Web browsers, mobile apps (can't keep secrets secure)
# - Confidential clients: Backend servers (can store secrets securely)
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.environment}-${var.project_name}-client"
  # This links the App Client to the User Pool created above.
  user_pool_id = aws_cognito_user_pool.main.id

  # --------------------------------------------------
  # CLIENT SECRET (CONFIDENTIAL vs PUBLIC)
  # --------------------------------------------------
  # WHAT IS A CLIENT SECRET?
  # A client secret is like a password for your application.
  # When your app talks to Cognito, it proves its identity by providing:
  #   1. Client ID (public, everyone can see it)
  #   2. Client Secret (private, only your app knows it)
  #
  # TWO TYPES OF CLIENTS:
  # 1. CONFIDENTIAL CLIENTS (generate_secret = true):
  #    - Backend servers, API servers
  #    - Can store secrets securely (not visible to users)
  #    - Example: Node.js server running on AWS
  #
  # 2. PUBLIC CLIENTS (generate_secret = false):
  #    - Web browsers, mobile apps
  #    - CANNOT store secrets securely (users can see the code)
  #    - Example: React app running in user's browser
  #
  # IMPORTANT:
  # Once you create an app client, you CANNOT change this setting!
  # You'd need to create a NEW app client.
  generate_secret = false

  # --------------------------------------------------
  # AUTHENTICATION FLOWS (HOW USERS CAN LOG IN)
  # --------------------------------------------------
  explicit_auth_flows = [
    # FLOW #1: USER_PASSWORD_AUTH
    # -------------------------------------
    # WHAT IS THIS?
    # This is the simplest authentication method:
    #   - User provides username (email) and password
    #   - App sends BOTH directly to Cognito
    #   - Cognito checks if they match
    #   - If correct, Cognito returns JWT tokens
    #
    # HOW IT WORKS:
    # 1. User types email: "john@example.com"
    # 2. User types password: "MyPassword123!"
    # 3. App calls: InitiateAuth API with username and password
    # 4. Cognito validates credentials
    # 5. Cognito returns: access_token, id_token, refresh_token
    #
    # SECURITY CONCERN:
    # The password is sent over the network (though it's encrypted with HTTPS).
    # This is why SRP (below) is more secure.
    # But this method is:
    #   - Easier to implement
    #   - Widely supported
    #   - Acceptable for most applications (when using HTTPS)
    #
    # WHY WE USE THIS:
    # - Simple to implement in frontend
    # - Works with all types of apps
    # - Standard username/password login (what users expect)
    "ALLOW_USER_PASSWORD_AUTH",

    # FLOW #2: REFRESH_TOKEN_AUTH
    # -------------------------------------
    # WHAT IS THIS?
    # This allows users to get NEW access tokens without logging in again.
    #
    # THE PROBLEM IT SOLVES:
    # Access tokens expire after 1 hour (for security).
    # Without refresh tokens:
    #   - After 1 hour, user is logged out
    #   - User must enter email and password AGAIN
    #
    # HOW REFRESH TOKENS WORK:
    # 1. User logs in → Gets access_token (expires in 1 hour) + refresh_token (expires in 30 days)
    # 2. App stores both tokens securely
    # 3. After 1 hour, access_token expires
    # 4. App sends refresh_token to Cognito
    # 5. Cognito gives a NEW access_token (good for another hour)
    # 6. User stays logged in! No need to type password again.
    #
    # SECURITY NOTE:
    # Refresh tokens are MORE powerful than access tokens.
    # If someone steals a refresh token, they can generate new access tokens!
    # So:
    #   - Store refresh tokens VERY securely (encrypted storage)
    #   - Never send refresh tokens to your backend
    #   - Only send access tokens to your backend
    "ALLOW_REFRESH_TOKEN_AUTH",

    # FLOW #3: USER_SRP_AUTH
    # -------------------------------------
    # WHAT IS SRP?
    # SRP stands for "Secure Remote Password" protocol.
    # It's a more secure way to authenticate without sending the password over the network.
    #
    # THE PROBLEM WITH SENDING PASSWORDS:
    # Even with HTTPS encryption:
    #   - Password travels over the network
    #   - Middlemen (CDNs, proxies) might log requests
    #   - Potential SSL vulnerabilities
    #
    # HOW SRP WORKS (SIMPLIFIED):
    # This uses cryptographic math (don't worry about the details!):
    # 1. User types password (stays in the browser/app, never sent!)
    # 2. App uses password to generate a "proof" (mathematical calculation)
    # 3. App sends the "proof" to Cognito (NOT the password!)
    # 4. Cognito has its own proof stored
    # 5. Cognito verifies both proofs match
    # 6. If they match, user is authenticated
    "ALLOW_USER_SRP_AUTH"
  ]

  # --------------------------------------------------
  # - Used to access protected resources (your backend APIs)
  # - Contains user info and permissions
  # - Your backend validates this token
  # - SHORT lifespan (for security)
  # --------------------------------------------------
  access_token_validity = 1 # 1 hour

  # --------------------------------------------------
  # - Contains user profile information (email, role, etc.)
  # - Used by your frontend to display user info
  # - Not meant for API authentication (that's access token's job)
  # - SHORT lifespan (same as access token)
  id_token_validity = 1 # 1 hour

  # --------------------------------------------------
  # - Used to get NEW access and ID tokens without logging in again
  # - More powerful (can generate new tokens)
  # - LONG lifespan (for user convenience)
  # --------------------------------------------------
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours" # Interpret access_token_validity as hours
    id_token      = "hours" # Interpret id_token_validity as hours
    refresh_token = "days"  # Interpret refresh_token_validity as days
  }

  # --------------------------------------------------
  # OAUTH 2.0 CONFIGURATION
  # --------------------------------------------------
  # WHAT IS OAUTH?
  # OAuth 2.0 is an authorization protocol used for:
  #   - Social login ("Sign in with Google", "Sign in with Facebook")
  #   - Third-party app access ("Allow App X to access your data")
  #   - Hosted UI (Cognito's built-in login page)
  allowed_oauth_flows = []

  # This is a master switch for OAuth.
  # false = OAuth is completely disabled for this App Client.
  # true = OAuth is enabled (and flows above would be allowed).
  allowed_oauth_flows_user_pool_client = false

  # OAuth scopes define what permissions an app is requesting.
  # Examples: "email", "profile", "openid", "aws.cognito.signin.user.admin"
  # We set it to [] (empty) because we're not using OAuth.
  allowed_oauth_scopes = []

  # WHAT ARE CALLBACK URLs?
  # After successful OAuth login, where should Cognito redirect the user?
  # Example: ["https://myapp.com/auth/callback"]
  #
  # HOW IT WORKS (IF OAUTH WAS ENABLED):
  # 1. User clicks "Sign in with Google"
  # 2. Redirected to Google login page
  # 3. User logs in to Google
  # 4. Google redirects BACK to your callback URL with a code
  # 5. Your app exchanges code for tokens
  # We set it to [] because we're not using OAuth (no redirects needed).
  callback_urls = []

  # logout_urls = []
  # WHAT ARE LOGOUT URLs?
  # After user logs out from Cognito Hosted UI, where should they be redirected?
  # Example: ["https://myapp.com/goodbye"]
  #
  # We set it to [] because we're not using Hosted UI.
  logout_urls = []

  read_attributes = [
    "email",
    "email_verified",
    "custom:role"
  ]

  write_attributes = [
    "email",
    "custom:role"
  ]
  prevent_user_existence_errors = "ENABLED"
}