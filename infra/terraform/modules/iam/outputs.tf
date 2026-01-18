# ========================================
# BACKEND API OUTPUTS
# ========================================

# OUTPUT: backend_api_role_arn
# WHAT IT EXPORTS: The ARN (Amazon Resource Name) of the backend API role
# WHAT IS AN ARN? A unique identifier for AWS resources
# WHERE IS THIS USED?
#   1. Cognito (in identity provider configuration)
#   2. Other modules (to reference this role)
#   3. Lambda functions (to call API that needs this role)
#   4. API Gateway (to invoke Lambda with this role)
# WHY NEEDED: ARNs are the standard way to reference AWS resources
# WHAT IF REMOVED: Other modules can't find/reference this role
output "backend_api_role_arn" {
  description = "ARN of the backend API IAM role"
  value       = aws_iam_role.backend_api.arn
}

# OUTPUT: backend_api_instance_profile_name
# WHAT IT EXPORTS: The name of the backend API instance profile
# WHERE IS THIS USED?
#   - EC2 module (when launching EC2 instances for backend)
#   - The instance profile contains the IAM role
#   - When you attach instance profile to EC2, the EC2 gets the role's permissions
# HOW IT WORKS:
#   1. EC2 module gets this output: instance_profile_name = "dev-ridebooking-backend-api"
#   2. EC2 module creates EC2 instance with that profile
#   3. EC2 instance automatically gets backend_api role permissions
#   4. Instance can now read Secrets Manager, write CloudWatch logs, etc.
# WHY NAME INSTEAD OF ARN: EC2 API accepts name, not ARN
# WHAT IF REMOVED: EC2 module can't attach the instance profile to instances
output "backend_api_instance_profile_name" {
  description = "Name of the backend API instance profile"
  value       = aws_iam_instance_profile.backend_api.name
}

# OUTPUT: backend_api_instance_profile_arn
# WHAT IT EXPORTS: The ARN of the backend API instance profile
# WHERE IS THIS USED?
#   - Rarely used in this project
#   - Useful when: referencing instance profile in IAM policies or cross-account roles
#   - AWS standard: Many services accept either name or ARN
# WHY BOTH NAME AND ARN: Different services expect different formats
# WHAT IF REMOVED: Some advanced use cases won't work (usually not critical)
output "backend_api_instance_profile_arn" {
  description = "ARN of the backend API instance profile"
  value       = aws_iam_instance_profile.backend_api.arn
}

# ========================================
# DRIVER WEB OUTPUTS
# ========================================

# OUTPUT: driver_web_role_arn
# WHAT IT EXPORTS: The ARN of the driver web (frontend) role
# WHERE IS THIS USED?
#   1. Similar to backend_api_role_arn (referenced in other modules)
#   2. Less critical than backend (frontend doesn't access sensitive services)
# WHY NEEDED: Other modules and services need to reference this role
output "driver_web_role_arn" {
  description = "ARN of the driver web IAM role"
  value       = aws_iam_role.driver_web.arn
}

# OUTPUT: driver_web_instance_profile_name
# WHAT IT EXPORTS: The name of the driver web instance profile
# WHERE IS THIS USED:
#   - EC2 module (when launching EC2 instances for driver web)
#   - Same pattern as backend_api_instance_profile_name
# HOW IT WORKS:
#   1. EC2 module gets this output
#   2. EC2 module creates EC2 instance with this profile
#   3. Instance gets driver_web role permissions
#   4. Instance can only write CloudWatch logs (limited permissions)
output "driver_web_instance_profile_name" {
  description = "Name of the driver web instance profile"
  value       = aws_iam_instance_profile.driver_web.name
}

# OUTPUT: driver_web_instance_profile_arn
# WHAT IT EXPORTS: The ARN of the driver web instance profile
# WHERE IS THIS USED:
#   - Same as backend_api_instance_profile_arn
#   - Advanced use cases (referencing in policies, cross-account access)
output "driver_web_instance_profile_arn" {
  description = "ARN of the driver web instance profile"
  value       = aws_iam_instance_profile.driver_web.arn
}
