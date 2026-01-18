output "user_pool_id" {
  description = "Cognito User Pool ID (for backend JWT validation)"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint (for backend JWT validation)"
  value       = aws_cognito_user_pool.main.endpoint
}

output "app_client_id" {
  description = "Cognito App Client ID (for frontend authentication)"
  value       = aws_cognito_user_pool_client.main.id
}

output "app_client_name" {
  description = "Cognito App Client name"
  value       = aws_cognito_user_pool_client.main.name
}

# ========================================
# JWT VALIDATION INFORMATION (FOR BACKEND)
# ========================================
#
# WHAT IS JWT VALIDATION?
# ---------------------------
# When your backend API receives a JWT token from the frontend, it MUST verify:
#   1. The token was issued by YOUR Cognito (not a fake token)
#   2. The token hasn't been tampered with (signature is valid)
#   3. The token hasn't expired (check expiration time)
#   4. The token is intended for your application (audience check)
#
# HOW JWT VALIDATION WORKS:
# 1. Frontend logs in user → Gets JWT token from Cognito
# 2. Frontend sends token to backend: Authorization: Bearer <token>
# 3. Backend downloads public keys from Cognito (using jwks_uri)
# 4. Backend verifies token signature using public keys
# 5. Backend checks token issuer matches expected issuer
# 6. Backend checks token expiration
# 7. If all checks pass → Token is valid → Allow request
# 8. If any check fails → Token is invalid → Reject request (401 Unauthorized)
#
# THE TWO OUTPUTS BELOW ARE FOR JWT VALIDATION:
# - jwks_uri: Where to get public keys
# - issuer: Who issued the token (should match your Cognito)
# ========================================

# --------------------------------------------------
# OUTPUT: jwks_uri
# --------------------------------------------------
# WHAT IS JWKS?
# JWKS = JSON Web Key Set
# It's a URL that returns public cryptographic keys used to verify JWT signatures.
#
# HOW JWT SIGNATURES WORK (SIMPLIFIED):
# Think of it like a wax seal on a letter:
#   1. Cognito has a PRIVATE key (kept secret)
#   2. When creating a JWT, Cognito "signs" it with the private key (adds signature)
#   3. Cognito publishes PUBLIC keys at the JWKS URI (available to everyone)
#   4. Your backend downloads the public keys
#   5. Backend uses public keys to verify the signature
#   6. If signature is valid → Token came from Cognito and wasn't tampered with
#
# WHERE IS THIS USED?
# 1. BACKEND JWT VALIDATION:
#    Your backend needs this URL to download public keys.
#
# 2. JWT VERIFICATION LIBRARIES:
#    Most JWT libraries can automatically fetch keys from JWKS URI:
#    - jsonwebtoken (Node.js)
#    - jose (Node.js)
#    - python-jose (Python)
#    - java-jwt (Java)
#
# KEY ROTATION:
# Cognito periodically rotates its signing keys for security.
# The JWKS endpoint always returns the current valid keys.
# Your backend should:
#   - Cache keys for performance (don't fetch on every request)
#   - Refresh cache periodically (e.g., every hour)
#   - Handle key rotation gracefully (fetch new keys if verification fails)
# CRITICAL FOR SECURITY:
# Your backend MUST use this EXACT URL!
# If you use a different URL, you'll be validating against wrong keys!
# Result: All tokens will be rejected (or worse, fake tokens accepted)!
output "jwks_uri" {
  description = "JWKS URI for JWT signature validation (backend must use this to verify tokens)"
  value       = "https://cognito-idp.${aws_cognito_user_pool.main.id}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

# --------------------------------------------------
# OUTPUT: issuer
# --------------------------------------------------
# WHAT IS AN ISSUER?
# The "issuer" (iss) is a claim in every JWT token that identifies WHO created the token.
# Think of it like the return address on a letter.
#
# WHY VALIDATE THE ISSUER?
# When your backend receives a JWT, it should check:
#   1. Is this token from MY Cognito User Pool? (check issuer)
#   2. Or is it from someone else's Cognito? (reject!)
#   3. Or is it a completely fake token? (reject!)
#
# SECURITY SCENARIO:
# Without issuer validation:
#   - Attacker creates their own Cognito User Pool
#   - Attacker generates a valid JWT from THEIR pool
#   - Attacker sends the token to YOUR backend
#   - If you only check signature (not issuer), token would be VALID!
#   - Attacker gains unauthorized access!
#
# With issuer validation:
#   - Backend checks: "Is iss = my expected issuer?"
#   - Attacker's token has different issuer
#   - Backend rejects the token
#   - Attack prevented!
#
# WHERE IS THIS USED?
# Backend JWT validation libraries have an "issuer" parameter:
# THIS MATCHES THE JWKS URI:
# Notice the issuer and jwks_uri have the same base URL?
# That's by design! They're from the same Cognito User Pool.
#
# BACKEND MUST VALIDATE THIS:
# Your backend JWT validation MUST include issuer checking:
#   1. Extract "iss" claim from JWT
#   2. Compare with expected issuer (this output value)
#   3. If they don't match → Reject token
#   4. If they match → Continue with other validations
#
# VALIDATION CHECKLIST:
# A secure JWT validation checks:
# Signature (using jwks_uri)
# Issuer (using this issuer output)
# Expiration (exp claim)
# Audience (aud claim, should be client_id)
# Token type (should be "access" or "id")
output "issuer" {
  description = "JWT issuer (backend must verify tokens come from this issuer)"
  value       = "https://cognito-idp.${aws_cognito_user_pool.main.id}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "auth_config_summary" {
  description = "Complete authentication configuration summary (all settings in one place)"
  value = {
    # User Pool identifier
    user_pool_id = aws_cognito_user_pool.main.id

    # App Client identifier
    app_client_id = aws_cognito_user_pool_client.main.id

    # What users use as username (in our case, email)
    username_attribute = "email"

    # Custom attributes we defined (in our case, just role)
    custom_attributes = ["custom:role"]

    # Enabled authentication flows (how users can log in)
    auth_flows = [
      "USER_PASSWORD_AUTH", # Direct username/password authentication
      "REFRESH_TOKEN_AUTH", # Refresh expired access tokens
      "USER_SRP_AUTH"       # Secure Remote Password protocol
    ]

    # How long each token type is valid
    token_validity = {
      access_token  = "1 hour"  # Access token expires after 1 hour
      id_token      = "1 hour"  # ID token expires after 1 hour
      refresh_token = "30 days" # Refresh token expires after 30 days
    }
  }
}