# ==============================================================================
# PROJECT IDENTIFICATION
# ==============================================================================

project    = "d2-ride-booking-new"
aws_region = "ap-southeast-1"

# ==============================================================================
# TERRAFORM STATE MANAGEMENT
# ==============================================================================
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TERRAFORM STATE BUCKET
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The name of the S3 bucket where Terraform stores its state file remotely.
# The state file is like a database that tracks what Terraform has created.
# CURRENT STATE STORAGE:
# Check the .terraform/ directory or run: terraform show
# If state is local: You'll see terraform.tfstate in this directory
# If state is remote: The state is in S3
terraform_state_bucket = "terraform-731099197523"

# ==============================================================================
# GITHUB INTEGRATION
# ==============================================================================
github_repo = "fikriimujahid/d2-ride-booking-new"