# ========================================================================================================
# VPC ENDPOINTS MODULE - MAIN CONFIGURATION
# ========================================================================================================
#
# 🎯 WHAT THIS MODULE DOES:
# This module creates VPC Endpoints in AWS. Think of VPC Endpoints as "private doors" that let your
# resources inside your private VPC (Virtual Private Cloud) talk to AWS services WITHOUT going through
# the public internet.
# ========================================================================================================

locals {
  name_prefix = "${var.environment}-${var.project_name}"
}

# ========================================================================================================
# SECURITY GROUP - Firewall for VPC Endpoints
# ========================================================================================================
resource "aws_security_group" "endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints"
  description = "Interface VPC endpoints security group (${var.environment})"
  vpc_id      = var.vpc_id

  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ LIFECYCLE - Special Instructions to Terraform
  # └─────────────────────────────────────────────────────────────────────────────
  # WHAT IS lifecycle?
  # This is a special Terraform meta-argument that controls HOW Terraform manages this resource.
  # It's not an AWS setting - it's instructions to Terraform itself.
  #
  # WHAT IS ignore_changes?
  # Normally, Terraform wants to "own" all aspects of a resource. If something changes outside
  # Terraform (like if someone manually adds a rule in AWS console), Terraform will see the
  # difference and try to "fix" it back to what's in the code.
  #
  # By using ignore_changes = [egress], we tell Terraform:
  # "Don't manage egress rules for this security group. If they change, ignore it."
  #
  # WHY DO WE IGNORE EGRESS RULES?
  # 1. AWS automatically creates a default egress rule (allow all outbound traffic)
  # 2. For VPC endpoints, we only care about INGRESS (incoming traffic on port 443)
  # 3. The return traffic is automatically allowed (connections are "stateful")
  # 4. Managing egress rules here can cause errors when AWS changes internal rule IDs
  #
  # TECHNICAL DETAIL:
  # AWS sometimes changes internal rule IDs for security group rules. If Terraform tries to
  # manage inline egress rules and AWS changes these IDs, you get "InvalidPermission.NotFound"
  # errors when Terraform tries to update them.
  lifecycle {
    ignore_changes = [egress]
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc-endpoints"
    Environment = var.environment
    Service     = "vpc-endpoints"
  })
}

# ========================================================================================================
# SECURITY GROUP INGRESS RULE - Allow HTTPS Traffic From VPC
# ========================================================================================================
resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ SECURITY_GROUP_ID - Which Security Group Does This Rule Apply To?
  # └─────────────────────────────────────────────────────────────────────────────
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow HTTPS from within VPC"

  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ CIDR_IPV4 - The IP Address Range That's Allowed
  # └─────────────────────────────────────────────────────────────────────────────
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-endpoints-https-from-vpc"
  })
}

# ========================================================================================================
# VPC ENDPOINT FOR SYSTEMS MANAGER (SSM)
# ========================================================================================================
# WHAT IS SYSTEMS MANAGER (SSM)?
# AWS Systems Manager (SSM) is a service that helps you manage your EC2 instances remotely.
# You can:
# - Run commands on servers without SSH
# - Get a terminal session (Session Manager)
# - Apply patches
# - View inventory of installed software
# - And much more
#
# WHY DO WE NEED A VPC ENDPOINT FOR SSM?
# Without this endpoint:
# - Your EC2 instances would need internet access (via NAT Gateway or Internet Gateway)
# - They'd talk to SSM over the public internet
# - This costs money (NAT Gateway charges $0.045/GB) and is less secure
#
resource "aws_vpc_endpoint" "ssm" {
  vpc_id = var.vpc_id

  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ SERVICE_NAME - Which AWS Service This Endpoint Connects To
  # └─────────────────────────────────────────────────────────────────────────────
  service_name = "com.amazonaws.${var.aws_region}.ssm"

  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ VPC_ENDPOINT_TYPE - Interface or Gateway?
  # └─────────────────────────────────────────────────────────────────────────────
  # WHAT ARE THE TYPES OF VPC ENDPOINTS?
  # AWS offers two types:
  #
  # 1. GATEWAY ENDPOINTS:
  #    - Only for S3 and DynamoDB
  #    - Free (no hourly charge)
  #    - Uses route tables (no ENIs)
  #    - Limited to these two services
  #
  # 2. INTERFACE ENDPOINTS:
  #    - For all other AWS services (SSM, EC2, Secrets Manager, etc.)
  #    - Costs money (~$7/month per AZ)
  #    - Creates ENIs (network interfaces) in your subnets
  #    - Can use security groups for fine-grained control
  #    - This is what we're using
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.endpoints.id]

  # ┌─────────────────────────────────────────────────────────────────────────────
  # │ PRIVATE_DNS_ENABLED - Automatic DNS Resolution
  # └─────────────────────────────────────────────────────────────────────────────
  # WHAT IS PRIVATE DNS?
  # When you enable private DNS, AWS automatically creates DNS records so that:
  # - Your EC2 instances can use the standard AWS service URLs
  # - Those URLs automatically resolve to your private VPC endpoint
  # - No code changes needed in your applications
  #
  # HOW IT WORKS:
  # 
  # WITHOUT private_dns_enabled = true:
  # - Your app tries to reach: ssm.us-east-1.amazonaws.com
  # - DNS resolves to PUBLIC IP address
  # - Traffic goes through NAT Gateway to internet
  # - You DON'T use the VPC endpoint (defeating the purpose!)
  #
  # WITH private_dns_enabled = true:
  # - Your app tries to reach: ssm.us-east-1.amazonaws.com
  # - DNS resolves to PRIVATE IP of the VPC endpoint ENI
  # - Traffic stays inside your VPC
  # - Uses the VPC endpoint (exactly what we want!)
  # REQUIREMENT:
  # For private DNS to work, your VPC must have:
  # - DNS resolution enabled (enableDnsSupport = true)
  # - DNS hostnames enabled (enableDnsHostnames = true)
  # Without these, private DNS won't function.
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ssm"
    Environment = var.environment
  })
}

# ========================================================================================================
# VPC ENDPOINT FOR EC2 MESSAGES
# ========================================================================================================
# WHAT IS EC2MESSAGES?
# EC2Messages is NOT a standalone AWS service that you use directly. It's a SUPPORTING service
# that Systems Manager uses behind the scenes.
#
# WHAT DOES IT DO?
# EC2Messages handles the communication channel for sending commands from Systems Manager to your
# EC2 instances. Think of it as the "delivery truck" that carries your commands:
# - You send a command through SSM (the front desk)
# - SSM packages the command
# - EC2Messages delivers it to your EC2 instance
# - Your instance executes it
# - Results come back through the same channel
#
# RELATIONSHIP TO SSM:
# For Systems Manager to work, you need ALL THREE endpoints:
# 1. ssm - Main service API
# 2. ec2messages - Command delivery ← THIS ONE
# 3. ssmmessages - Session Manager connections
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ec2messages"
    Environment = var.environment
  })
}

# ========================================================================================================
# VPC ENDPOINT FOR SSM MESSAGES
# ========================================================================================================
#
# WHAT IS SSMMESSAGES?
# SSMMessages is another SUPPORTING service for Systems Manager. It handles a specific feature:
# Session Manager - the ability to get an interactive terminal session to your EC2 instance
# without SSH or opening port 22.
#
# WHAT DOES IT DO?
# This service creates a secure tunnel for real-time, interactive communication:
# - You click "Connect" in Session Manager
# - SSMMessages establishes a WebSocket connection
# - You get a terminal in your browser
# - All traffic flows through this private endpoint
#
# ANALOGY:
# - SSM = Post office (send/receive mail)
# - EC2Messages = Mail delivery truck (deliver packages/commands)
# - SSMMessages = Phone line (real-time conversation) ← THIS ONE
#
# RELATIONSHIP TO SSM:
# For FULL Systems Manager functionality, you need all three:
# 1. ssm - Main service API
# 2. ec2messages - Command delivery
# 3. ssmmessages - Session Manager ← THIS ONE
#
# SECURITY BENEFIT:
# With this endpoint:
# - No need to open SSH port 22
# - No need for SSH key management
# - No need for bastion hosts
# - All access controlled by IAM (not network rules)
# - All sessions logged to CloudWatch Logs or S3
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpce-ssmmessages"
    Environment = var.environment
  })
}