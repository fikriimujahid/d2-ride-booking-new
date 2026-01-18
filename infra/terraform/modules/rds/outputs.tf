# ================================================================================
# SECTION 1: RDS INSTANCE IDENTIFICATION OUTPUTS
# ================================================================================
output "rds_instance_id" {
  description = "RDS instance identifier (unique AWS name)"
  value       = aws_db_instance.main.id
}

output "rds_instance_arn" {
  description = "RDS instance ARN (required for IAM database authentication)"
  value       = aws_db_instance.main.arn
}

# ================================================================================
# SECTION 2: CONNECTION INFORMATION OUTPUTS
# ================================================================================
output "rds_endpoint" {
  description = "RDS instance endpoint (hostname:port) for application connections"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS instance hostname only (without port)"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS instance port number (usually 3306 for MySQL)"
  value       = aws_db_instance.main.port
}

# ================================================================================
# SECTION 3: DATABASE INFORMATION OUTPUTS
# ================================================================================
output "db_name" {
  description = "Database name created on the RDS instance"
  value       = aws_db_instance.main.db_name
}

output "db_master_username" {
  description = "Master username (for admin purposes only - NOT for application use)"
  value       = aws_db_instance.main.username
  sensitive   = true # Don't print this in logs/console
}

# ================================================================================
# SECTION 4: SECURITY CONFIGURATION OUTPUTS
# ================================================================================
output "rds_security_group_id" {
  description = "Security group ID for RDS instance (firewall rules)"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name (defines network placement)"
  value       = aws_db_subnet_group.main.name
}

# ================================================================================
# SECTION 5: SECRETS MANAGER OUTPUTS
# ================================================================================
output "master_password_secret_arn" {
  description = "ARN of Secrets Manager secret containing master password (admin use only)"
  value       = aws_secretsmanager_secret.rds_master_password.arn
}

output "master_password_secret_name" {
  description = "Name of Secrets Manager secret containing master password (admin use only)"
  value       = aws_secretsmanager_secret.rds_master_password.name
}

# ================================================================================
# SECTION 6: IAM AUTHENTICATION OUTPUTS
# ================================================================================
output "iam_database_authentication_enabled" {
  description = "Whether IAM database authentication is enabled (should be true)"
  value       = aws_db_instance.main.iam_database_authentication_enabled
}

output "rds_resource_id" {
  description = "RDS resource ID (required for IAM database authentication policy)"
  value       = aws_db_instance.main.resource_id
}

# ================================================================================
# SECTION 7: APPLICATION INTEGRATION GUIDE (INFORMATIONAL)
# ================================================================================
output "application_integration_guide" {
  description = "Guide for application integration with IAM database authentication"
  value = {
    # Connection details for your application
    connection_info = "Use ${aws_db_instance.main.endpoint} with TLS/SSL enabled"

    # Authentication method
    authentication = "Generate IAM auth token using AWS SDK"

    # Which database to connect to
    database_name = aws_db_instance.main.db_name

    # Example code for generating the token
    # This is pseudocode - actual implementation depends on your language
    iam_auth_example = "token := rds.GenerateDBAuthToken(endpoint, region, dbUser, credentials)"

    # SQL command to create the application database user
    # This must be run manually by an admin
    db_user_creation = "CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'"

    # IAM policy that the application's IAM role needs
    # Replace resource values with actual values from this output
    iam_policy_required = "rds-db:connect on resource: arn:aws:rds-db:region:account:dbuser:${aws_db_instance.main.resource_id}/app_user"

    # How long the token is valid
    token_validity = "15 minutes"

    # TLS is required when using IAM authentication
    tls_required = true
  }
}

# ================================================================================
# SECTION 8: COST CONTROL INFORMATION
# ================================================================================
output "cost_control_info" {
  # This output provides information about cost optimization
  # Useful for understanding what you're paying for
  description = "Information about cost control for DEV environment"
  value = {
    # What instance class (size) is being used
    instance_class = aws_db_instance.main.instance_class # e.g., db.t3.micro

    # Is this Multi-AZ (costs 2x if true)
    multi_az = aws_db_instance.main.multi_az # e.g., false

    # Storage configuration
    # Starts at allocated_storage, can grow to max_allocated_storage
    storage_size = "${aws_db_instance.main.allocated_storage} GB (autoscaling to ${var.max_allocated_storage} GB)"

    # Backup retention cost
    # Each backup costs approximately 0.10 USD per GB per day
    backup_retention = "${aws_db_instance.main.backup_retention_period} day(s)"

    # Cost-saving commands for DEV
    # Stop RDS during off-hours
    lifecycle_control = "Use infra/scripts/dev-stop.sh to stop RDS when not in use"

    # Cost savings from stopping
    # Stopping instance = no compute costs, storage costs continue
    cost_impact = "Stopping RDS eliminates instance charges (storage charges continue)"
  }
}
