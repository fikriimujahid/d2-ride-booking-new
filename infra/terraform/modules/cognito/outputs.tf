# ========================================
# Cognito Module - Outputs
# ========================================
# Purpose: Export Cognito identifiers for frontend and backend

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

# ----------------------------------------
# JWT Validation Information
# ----------------------------------------
# WHY: Backend needs these to validate JWT tokens
output "jwks_uri" {
  description = "JWKS URI for JWT signature validation"
  value       = "https://cognito-idp.${aws_cognito_user_pool.main.id}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

output "issuer" {
  description = "JWT issuer (for JWT validation)"
  value       = "https://cognito-idp.${aws_cognito_user_pool.main.id}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

# ----------------------------------------
# Configuration Summary (for documentation)
# ----------------------------------------
output "auth_config_summary" {
  description = "Authentication configuration summary"
  value = {
    user_pool_id       = aws_cognito_user_pool.main.id
    app_client_id      = aws_cognito_user_pool_client.main.id
    username_attribute = "email"
    custom_attributes  = ["custom:role"]
    auth_flows = [
      "USER_PASSWORD_AUTH",
      "REFRESH_TOKEN_AUTH",
      "USER_SRP_AUTH"
    ]
    token_validity = {
      access_token  = "1 hour"
      id_token      = "1 hour"
      refresh_token = "30 days"
    }
  }
}
