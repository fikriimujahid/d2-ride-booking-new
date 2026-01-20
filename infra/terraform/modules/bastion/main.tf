locals {
  name = "${var.environment}-${var.project_name}-bastion"
}

# AL2023 includes SSM agent; we resolve AMI via SSM parameter to avoid hardcoding.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# -------------------------------
# Security group
# -------------------------------
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion"
  description = "Bastion host security group (SSM by default; optional SSH)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Bastion"
  })
}

# Optional inbound SSH. Prefer SSM Session Manager instead.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count             = var.enable_ssh ? length(var.ssh_allowed_cidrs) : 0
  security_group_id = aws_security_group.bastion.id

  description = "Allow SSH to bastion"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.ssh_allowed_cidrs[count.index]
}

# Allow all outbound so the bastion can reach RDS + SSM endpoints.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.bastion.id

  description = "Allow all outbound"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# -------------------------------
# IAM role + instance profile (SSM)
# -------------------------------
resource "aws_iam_role" "bastion" {
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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion-"
  role        = aws_iam_role.bastion.name

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# -------------------------------
# EC2 instance
# -------------------------------
resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # Put it in the public subnet with a public IP for easy SSM without NAT/endpoints.
  associate_public_ip_address = true

  key_name = var.enable_ssh ? var.key_name : null

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    Service     = "bastion"
    ManagedBy   = "Terraform"
  })
}
