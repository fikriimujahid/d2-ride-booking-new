# ============================================================================
# IAM Role Outputs
# ============================================================================
output "github_actions_deploy_role_arn" {
  description = "ARN of the github_actions_deploy_role"
  value       = aws_iam_role.github_actions_deploy_role.arn
}

# ============================================================================
# Instance Profile Outputs
# ============================================================================
