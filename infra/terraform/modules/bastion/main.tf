# WHAT IS A BASTION HOST?
# Think of a bastion host like the front desk security guard at a building:
# - Your private database (RDS) is inside a locked room (private subnet)
# - You cannot access it directly from the internet
# - The bastion host is a special server that sits between the internet and your private resources
# - You connect to the bastion first, then from the bastion you can access your database
#
# WHY DO WE NEED THIS?
# - AWS best practice is to keep databases in PRIVATE subnets (no internet access)
# - But developers and ops teams sometimes need to connect to the database
# - Instead of exposing the database to the internet (dangerous!), we create one small
#   server (the bastion) that IS accessible from the internet
# - This bastion can then connect to the private database
# - This way, we only have ONE entry point to secure, not the whole database
# ==============================================================================

locals {
  name = "${var.environment}-${var.project_name}-bastion"
}

# ------------------------------------------------------------------------------
# DATA SOURCE: AMAZON LINUX 2023 AMI
# ------------------------------------------------------------------------------
#
# WHAT IS AN AMI?
# - AMI = Amazon Machine Image
# - Think of it like a "template" or "blueprint" for a computer
# - It contains the operating system (like Windows or Linux) and pre-installed software
# - When you create an EC2 instance, you choose which AMI to use
#
# WHAT IS THIS DATA SOURCE DOING?
# - Instead of hardcoding an AMI ID (like "ami-12345678"), we're looking it up dynamically
# - AWS publishes official AMI IDs in a special service called Systems Manager (SSM) Parameter Store
# - This is like asking AWS: "What's the latest Amazon Linux 2023 AMI ID right now?"
#
# WHY NOT JUST HARDCODE THE AMI ID?
# - AMI IDs change when AWS releases updates
# - Different AWS regions have different AMI IDs
# - Hardcoding = you'd have to manually update this file every time
# - Dynamic lookup = always gets the latest AMI automatically
#
# WHAT IS "data" IN TERRAFORM?
# - "data" blocks FETCH information from AWS (they don't CREATE anything)
# - "resource" blocks CREATE things
# - Think of "data" like a read-only query
#
data "aws_ssm_parameter" "al2023_ami" {
  # This is the path where AWS publishes the latest Amazon Linux 2023 AMI ID
  # AWS maintains this - you don't need to change it
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "bastion" {
  # name_prefix = AWS will generate a unique name starting with this prefix
  # Example result: "ride-booking-dev-bastion-20240115123456"
  # 
  # WHY name_prefix instead of name?
  # - If you try to recreate a resource with the same exact name, AWS will reject it
  # - name_prefix adds a random suffix, avoiding naming conflicts
  # - Useful when doing replacements during updates
  name_prefix = "${var.project_name}-${var.environment}-bastion"
  description = "Bastion host security group (SSM by default; optional SSH)"

  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Bastion"
  })
}

# ------------------------------------------------------------------------------
# SECURITY GROUP INGRESS RULE - SSH (Optional)
# ------------------------------------------------------------------------------
#
# WHAT IS THIS RULE DOING?
# - This creates an INGRESS (incoming) rule to allow SSH connections
# - SSH = Secure Shell, traditional way to connect to Linux servers (port 22)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  # LOGIC:
  # IF enable_ssh is true:
  #   Create one rule for EACH IP address in the ssh_allowed_cidrs list
  # ELSE:
  #   Create 0 rules (skip SSH entirely)
  count = var.enable_ssh ? length(var.ssh_allowed_cidrs) : 0

  security_group_id = aws_security_group.bastion.id
  description       = "Allow SSH to bastion"

  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.ssh_allowed_cidrs[count.index]
}

# ------------------------------------------------------------------------------
# SECURITY GROUP EGRESS RULE - Allow All Outbound
# ------------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0104
#tfsec:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound"

  # ip_protocol = "-1" means ALL protocols (TCP, UDP, ICMP, everything)
  ip_protocol = "-1"

  # cidr_ipv4 = "0.0.0.0/0" means "allow connections to ANY IP address"
  # This means the bastion can connect to:
  # - RDS in the private subnet
  # - AWS service endpoints
  # - The internet (for updates)
  cidr_ipv4 = "0.0.0.0/0" 
}

# ------------------------------------------------------------------------------
# IAM ROLE - Permissions for the Bastion
# ------------------------------------------------------------------------------
resource "aws_iam_role" "bastion" {
  # name_prefix = Generate a unique name starting with this prefix
  # AWS will add a random suffix to avoid naming conflicts
  name_prefix = "${var.project_name}-${var.environment}-bastion-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ------------------------------------------------------------------------------
# IAM ROLE POLICY ATTACHMENT - Attach AWS-Managed Policy to Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# IAM INSTANCE PROFILE - Bridge Between IAM Role and EC2
# ------------------------------------------------------------------------------
resource "aws_iam_instance_profile" "bastion" {
  # name_prefix = Generate a unique name with random suffix
  name_prefix = "${var.project_name}-${var.environment}-bastion-"
  # role = Link this instance profile to the IAM role we created above
  role = aws_iam_role.bastion.name

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ------------------------------------------------------------------------------
# EC2 INSTANCE - The Actual Bastion Server
# ------------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  # ami = Amazon Machine Image (the operating system and software template)
  # We use the AMI ID we looked up earlier from SSM Parameter Store
  # .value gets the actual AMI ID string (like "ami-0abc123def456")
  # 
  # This will be Amazon Linux 2023 (latest version)
  # Amazon Linux 2023 includes SSM agent pre-installed (no manual setup needed)
  ami = data.aws_ssm_parameter.al2023_ami.value

  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # associate_public_ip_address = Give this instance a public IP address
  associate_public_ip_address = true

  # key_name = The SSH key pair name to allow SSH access
  key_name = var.enable_ssh ? var.key_name : null

  # metadata_options = Configuration for the Instance Metadata Service (IMDS)
  # 
  # WHAT IS IMDS?
  # - EC2 instances have a special internal API at http://169.254.169.254/
  # - Applications running on the instance can call this API to get:
  #   * Instance ID
  #   * IAM role credentials
  #   * Network information
  #   * User data script
  #
  # SECURITY CONCERN - IMDSv1 vs IMDSv2:
  # - IMDSv1 (old): Simple HTTP GET requests (vulnerable to SSRF attacks)
  # - IMDSv2 (new): Requires a session token first (prevents SSRF)
  #
  # WHAT IS AN SSRF ATTACK?
  # - SSRF = Server-Side Request Forgery
  # - Attacker tricks your application into making requests to internal APIs
  # - Example: Vulnerable web app could be tricked into:
  #   1. Calling http://169.254.169.254/latest/meta-data/iam/security-credentials/
  #   2. Stealing IAM role credentials
  #   3. Using those credentials to access AWS resources
  #
  metadata_options {
    # http_tokens = "required" means FORCE IMDSv2 (secure mode)
    # Options:
    # - "required" = Only IMDSv2 works (most secure)
    # - "optional" = Both IMDSv1 and IMDSv2 work (backward compatible, less secure)
    #
    # AWS BEST PRACTICE:
    # - Always use "required" for new instances
    # - IMDSv2 prevents credential theft via SSRF
    # - All modern software supports IMDSv2
    #
    # WHAT WOULD HAPPEN IF YOU CHANGED THIS TO "optional"?
    # - Security tools would flag this as a finding
    # - Vulnerable to SSRF attacks if applications have security holes
    # - Not recommended unless you have legacy software that can't use IMDSv2
    http_tokens = "required"
  }

  # root_block_device = Configuration for the root disk (storage drive)
  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name        = local.name      # The name shown in AWS console
    Environment = var.environment # dev, staging, prod
    Service     = "bastion"       # Helps filter/group related resources
    ManagedBy   = "Terraform"     # Important: tells people not to manually modify
  })
}