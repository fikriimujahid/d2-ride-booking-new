# EC2 module: single DEV instance with IAM role + SSM + CloudWatch logs.

locals {
  effective_app_root   = var.app_root != "" ? var.app_root : "/opt/apps/${var.service_name}"
  effective_pm2_app    = var.pm2_app_name != "" ? var.pm2_app_name : var.service_name
  name                 = "${var.environment}-${var.project_name}-${var.service_name}"
  cloudwatch_log_group = "/aws/ec2/${var.environment}-${var.project_name}-${var.service_name}"
}

# AL2023 with SSM agent baked in; SSM parameter keeps AMI patched without hardcoding IDs.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = local.cloudwatch_log_group
  retention_in_days = 14
  tags = merge(var.tags, {
    Name = local.name
  })
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.instance_profile_name
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = false
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    log_group_name = aws_cloudwatch_log_group.backend.name,
    env            = var.environment,
    project        = var.project_name,
    app_root       = local.effective_app_root,
    pm2_app_name   = local.effective_pm2_app
  })

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    Service     = var.service_name
    ManagedBy   = "terraform"
  })
}