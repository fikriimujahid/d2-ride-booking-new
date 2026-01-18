# -----------------------------------------------------------------------------
# RDS Module Main Configuration
# -----------------------------------------------------------------------------
# IMPORTANT:
# - IAM Database Authentication is ENABLED (required for application access)
# - Master password is stored in Secrets Manager for ADMIN use only
# - Application uses IAM authentication tokens (no password in app config)
# - Single-AZ deployment for DEV cost optimization
# - Deletion protection DISABLED for DEV environment flexibility
# - Minimal backup retention (1 day) to reduce cost
# -----------------------------------------------------------------------------

# ================================================================================
# SECTION 1: MASTER PASSWORD GENERATION
# ================================================================================
# AWS Concept: RDS Master User Password
# - Every RDS database needs a master user who can perform admin tasks
# - This password is ONLY for admins (humans doing maintenance)
# - The application will NOT use this password - it will use IAM tokens instead
# - We generate a secure random password automatically to avoid hardcoding secrets
# ================================================================================
resource "random_password" "rds_master_password" {
  # Set the password length to 32 characters (long = more secure)
  length = 32

  # special = true means: "Include special characters like !@#$%"
  # This makes the password much harder to guess
  special = true

  # Exclude characters that MySQL doesn't like or that cause problems
  # For example, we exclude backticks (`) and quotes (") that might break SQL
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ================================================================================
# SECTION 2: SECRETS MANAGER - SECURE PASSWORD STORAGE
# ================================================================================

# NOTE: This is for administrative access only (e.g., initial setup, migrations)
# Application connections will use IAM database authentication instead
resource "aws_secretsmanager_secret" "rds_master_password" {
  name_prefix = "${var.project_name}-${var.environment}-rds-master"
  description = "RDS master password for admin access only (NOT for application use - use IAM auth)"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-master-password"
      Environment = var.environment
      ManagedBy = "Terraform"
      Purpose = "RDS Admin Access"
    }
  )
}

# Store the actual password value in the secret
# What happens if we remove this:
# - The secret exists but has no value (empty safe with no password!)
# - RDS would fail because it couldn't get the password value
resource "aws_secretsmanager_secret_version" "rds_master_password" {
  # Link to the secret created above (which secret to store this value in)
  secret_id = aws_secretsmanager_secret.rds_master_password.id

  # The actual secret value (the password) to store
  secret_string = random_password.rds_master_password.result
}

# ================================================================================
# SECTION 3: DATABASE SUBNET GROUP - NETWORK PLACEMENT
# ================================================================================

# Places RDS in private subnets with no internet access
# Ensures database is isolated and accessible only via VPC
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}"
  description = "DB subnet group for ${var.project_name} ${var.environment} - private subnets only"
  # subnet_ids: List of PRIVATE subnet IDs where RDS can be deployed
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-db-subnet-group"
      Environment = var.environment
      ManagedBy = "Terraform"
    }
  )
}

# ================================================================================
# SECTION 4: SECURITY GROUP FOR RDS - ACCESS CONTROL
# ================================================================================

# No CIDR-based access - security group reference only
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds"
  description = "Security group for RDS MySQL instance - allows access only from backend API"

  # The RDS will live in this VPC, and this security group protects it
  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-sg"
      Environment = var.environment
      ManagedBy = "Terraform"
    }
  )
}

# ================================================================================
# SECTION 4.1: INGRESS RULE - ALLOW MYSQL FROM BACKEND API
# ================================================================================

# Allow MySQL access from backend API security group
resource "aws_vpc_security_group_ingress_rule" "mysql_from_backend" {
  count = length(var.allowed_security_group_ids)

  # The ID of the security group where this ingress rule will be attached
  security_group_id = aws_security_group.rds.id
  description = "Allow MySQL access from backend API"
  from_port = 3306
  to_port = 3306
  ip_protocol = "tcp"
  # The destination security group that is allowed to receive traffic
  # var.allowed_security_group_ids[count.index] = each security group in the list
  referenced_security_group_id = var.allowed_security_group_ids[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-ingress-mysql"
      Environment = var.environment
    }
  )
}

# ================================================================================
# SECTION 4.2: EGRESS RULE - ALLOW ALL OUTBOUND
# ================================================================================

# Egress: Allow all outbound (for updates, patches)
# Can be further restricted if needed
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.rds.id
  description = "Allow HTTPS within VPC (for VPC endpoints)"
  # IPv4 CIDR block that outbound traffic is allowed to reach
  cidr_ipv4 = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-egress-all"
      Environment = var.environment
    }
  )
}

# ================================================================================
# SECTION 5: THE RDS MYSQL INSTANCE - THE DATABASE ITSELF
# ================================================================================

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-rds-mysql"
  engine = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class
  allocated_storage = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  # storage_type = "gp3" means:
  #   - gp = "general purpose"
  #   - 3 = version 3 (latest and best)
  # Types:
  #   - gp3 = best for most workloads (fast, affordable)
  #   - io1 = very fast but expensive (for high I/O workloads)
  #   - st1 = slow but cheap (for big data, analytics)
  storage_type = "gp3"

  # storage_encrypted = true means "Encrypt the database storage on disk"
  # At-rest encryption:
  #   - Data on disk is encrypted with AWS keys
  #   - If someone steals the physical hard drive, they can't read the data
  #   - Slight performance impact (AWS encrypts/decrypts on the fly)
  # 
  # What if we set this to false?
  #   - Faster database (no encryption overhead)
  #   - HUGE security risk! Data not protected if drive is stolen
  #   - Bad for compliance (HIPAA, PCI-DSS, etc.)
  storage_encrypted = true
  db_name = var.db_name
  username = var.db_username
  password = random_password.rds_master_password.result
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible = false

  # iam_database_authentication_enabled = true means:
  #   - RDS accepts authentication tokens from AWS IAM
  #   - Instead of password, application sends a temporary token
  #   - Token generated by AWS SDK (like boto3 for Python, AWS SDK for Go)
  #   - Token is valid for 15 minutes only
  #   - Each token is unique (good for audit logging)
  #
  # What would happen to authentication if we disable this in production?
  #   - App suddenly can't connect (assumes IAM auth)
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  multi_az = var.multi_az
  backup_retention_period = var.backup_retention_period

  # backup_window = "03:00-04:00" means "Run backups between 3 AM and 4 AM UTC"
  # RDS automatically creates a backup once per day in this window
  backup_window = "03:00-04:00"

  # maintenance_window = "Mon:04:00-Mon:05:00" means:
  #   - Run maintenance on Monday between 4-5 AM UTC
  #   - Maintenance = security patches, version updates, etc.
  #   - AWS might restart RDS during this window
  maintenance_window = "Mon:04:00-Mon:05:00"

  deletion_protection = var.deletion_protection

  # skip_final_snapshot = true means "Don't create a backup on deletion"
  skip_final_snapshot = var.skip_final_snapshot

  # enabled_cloudwatch_logs_exports sends database logs to CloudWatch
  # [error, general, slowquery] means send three types of logs:
  #   - error: Database errors (connection failures, SQL errors, etc.)
  #   - general: General activity log (who connected, when, etc.)
  #   - slowquery: Queries that take longer than slow_query_log_time
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # monitoring_interval = 0 means "Don't use enhanced monitoring"
  # AWS has two monitoring options:
  #   - monitoring_interval = 0: Only basic metrics (CPU, memory, disk)
  #   - monitoring_interval = 60: Enhanced monitoring (every 60 seconds)
  monitoring_interval = 0

  auto_minor_version_upgrade = true

  # apply_immediately = true means "Apply changes right away"
  # Some RDS changes require a restart:
  #   - apply_immediately = true: Restart now (downtime immediately)
  #   - apply_immediately = false: Restart in next maintenance window (less impact)
  apply_immediately = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-mysql"
      Environment = var.environment
      ManagedBy = "Terraform"
      Purpose = "Application Database"
      CostControl = "Can be stopped/started via scripts"
    }
  )
}