# ========================================
# IAM Module - Outputs
# ========================================
# Purpose: Export IAM role ARNs for use in other modules

output "backend_api_role_arn" {
  description = "ARN of the backend API IAM role"
  value       = aws_iam_role.backend_api.arn
}

output "backend_api_instance_profile_name" {
  description = "Name of the backend API instance profile"
  value       = aws_iam_instance_profile.backend_api.name
}

output "backend_api_instance_profile_arn" {
  description = "ARN of the backend API instance profile"
  value       = aws_iam_instance_profile.backend_api.arn
}

output "driver_web_role_arn" {
  description = "ARN of the driver web IAM role"
  value       = aws_iam_role.driver_web.arn
}

output "driver_web_instance_profile_name" {
  description = "Name of the driver web instance profile"
  value       = aws_iam_instance_profile.driver_web.name
}

output "driver_web_instance_profile_arn" {
  description = "ARN of the driver web instance profile"
  value       = aws_iam_instance_profile.driver_web.arn
}

# CI/CD outputs (uncomment when role is created in Phase 4)
# output "cicd_role_arn" {
#   description = "ARN of the CI/CD IAM role (GitHub OIDC)"
#   value       = aws_iam_role.cicd.arn
# }
