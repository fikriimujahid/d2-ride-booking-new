# Optional internet-facing ALB for backend API. Off by default in env to save cost.

locals {
  name = "${var.environment}-${var.project_name}-alb"
}

resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  idle_timeout = 60

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    Service     = "backend-api"
  })
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-${var.project_name}-backend"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name    = "${local.name}-tg"
    Service = "backend-api"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Attach the single DEV EC2 target. Multi-instance/AZ can be added later.
resource "aws_lb_target_group_attachment" "backend_instance" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = var.target_instance_id
  port             = var.target_port
}

resource "aws_route53_record" "api" {
  count   = var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name (useful when Route53 alias not configured)"
}
