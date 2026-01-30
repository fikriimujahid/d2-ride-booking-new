locals {
  name = "${var.environment}-${var.project_name}-alb"
}

#trivy:ignore:AVD-AWS-0053
#tfsec:ignore:AVD-AWS-0053
resource "aws_lb" "this" {
  name = local.name

  # --------------------------------------------------------------------------
  # load_balancer_type: Specifies which kind of load balancer
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Tells AWS to create an "Application" Load Balancer
  # 
  # AWS HAS 3 TYPES OF LOAD BALANCERS:
  # 1. "application" - For HTTP/HTTPS web traffic (what we use)
  #    - Understands web protocols
  #    - Can route based on URL paths (/api, /admin)
  #    - Can inspect HTTP headers
  #
  # 2. "network" - For TCP/UDP traffic (lower level)
  #    - Faster, but less smart
  #    - Can't read HTTP content
  #
  # 3. "gateway" - For third-party virtual appliances
  #    - Very specialized use case
  load_balancer_type = "application"

  # --------------------------------------------------------------------------
  # internal: Whether the ALB is accessible from the internet
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Controls if the ALB has a public IP address
  # 
  # TWO OPTIONS:
  # - false (what we use) = "internet-facing" ALB
  #   - Gets a public DNS name anyone on the internet can reach
  #   - Your users can access api.yourdomain.com
  #
  # - true = "internal" ALB
  #   - Only accessible from inside your VPC
  #   - Used for internal microservices that shouldn't be public
  internal = false

  security_groups = [var.alb_security_group_id]
  subnets         = var.public_subnet_ids

  # --------------------------------------------------------------------------
  # idle_timeout: How long to wait before closing inactive connections
  # --------------------------------------------------------------------------
  idle_timeout = 60

  # --------------------------------------------------------------------------
  # drop_invalid_header_fields: Security feature to block malicious headers
  # --------------------------------------------------------------------------
  # Tells the ALB to remove HTTP headers that don't follow
  # the HTTP specification standards
  drop_invalid_header_fields = true

  tags = merge(var.tags, {
    Name        = local.name
    Environment = var.environment
    Service     = "backend-api"
  })
}

# ------------------------------------------------------------------------------
# TARGET GROUP - Where the ALB sends traffic
# ------------------------------------------------------------------------------
# WHAT IS A TARGET GROUP IN AWS?
# A Target Group is like a "group of destinations" that the ALB can send traffic to.
# Think of it as a contact list of backend servers.
resource "aws_lb_target_group" "backend" {
  name = "${var.environment}-${var.project_name}-backend"
  port = var.target_port

  # --------------------------------------------------------------------------
  # protocol: Which communication protocol to use
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Specifies HTTP protocol for ALB-to-backend communication
  #
  # OPTIONS:
  # - "HTTP": Unencrypted traffic (what we use for ALB-to-backend)
  # - "HTTPS": Encrypted traffic (adds complexity and latency)
  #
  # WHY HTTP (NOT HTTPS)?
  # - The ALB and backend are both in our private AWS VPC
  # - Traffic never leaves our secure network
  # - HTTPS from internet terminates at the ALB (called "SSL termination")
  # - Using HTTP internally reduces CPU overhead and latency
  #
  protocol = "HTTP"

  # --------------------------------------------------------------------------
  # target_type: What kind of resources are in this target group
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Tells AWS what type of targets will be registered
  #
  # OPTIONS:
  # - "instance": EC2 instances (what we use)
  #   - You specify instance IDs
  #   - ALB sends traffic to the instance's private IP
  #
  # - "ip": IP addresses
  #   - You specify exact IP addresses
  #   - Used for containers, Lambda, or resources outside AWS
  #
  # - "lambda": AWS Lambda functions
  #   - For serverless architectures
  target_type          = var.backend_target_type
  deregistration_delay = var.deregistration_delay_seconds

  vpc_id = var.vpc_id

  health_check {
    enabled = true

    # ------------------------------------------------------------------------
    # healthy_threshold: How many successes needed to be marked healthy
    # ------------------------------------------------------------------------
    healthy_threshold = 3

    # ------------------------------------------------------------------------
    # unhealthy_threshold: How many failures needed to mark unhealthy
    unhealthy_threshold = 3

    # ------------------------------------------------------------------------
    # interval: How often to perform health checks (in seconds)
    # ------------------------------------------------------------------------
    interval = 30

    # ------------------------------------------------------------------------
    # path: The URL path to check for health
    # ------------------------------------------------------------------------
    path = var.health_check_path

    # ------------------------------------------------------------------------
    # matcher: What HTTP response codes indicate success
    # ------------------------------------------------------------------------
    matcher = "200"
  }

  tags = merge(var.tags, {
    Name    = "${local.name}-tg"
    Service = "backend-api"
  })
}

# ------------------------------------------------------------------------------
# OPTIONAL TARGET GROUP - Driver web (Next.js) for driver.<domain_name>
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "driver_web" {
  count = var.enable_driver_web ? 1 : 0

  name                 = "${var.environment}-${var.project_name}-driver-web"
  port                 = var.driver_target_port
  protocol             = "HTTP"
  target_type          = var.driver_target_type
  deregistration_delay = var.deregistration_delay_seconds
  vpc_id               = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    path                = var.driver_health_check_path
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name    = "${local.name}-driver-tg"
    Service = "driver-web"
  })
}

# ------------------------------------------------------------------------------
# SECURITY SCAN IGNORES (for HTTP listener)
# ------------------------------------------------------------------------------
# Same as before - tells security scanners to skip this check
# AVD-AWS-0054: Wants HTTPS listener instead of HTTP
#
# WHY IGNORE FOR HTTP LISTENER?
# - This HTTP listener exists ONLY to redirect to HTTPS
# - It doesn't actually serve traffic, just redirects
# - Having an HTTP→HTTPS redirect is a security BEST PRACTICE
# - The actual traffic flows through HTTPS (defined later in this file)
#trivy:ignore:AVD-AWS-0054
#tfsec:ignore:AVD-AWS-0054

# ------------------------------------------------------------------------------
# HTTP LISTENER - Redirects to HTTPS
# ------------------------------------------------------------------------------
# WHAT IS A LISTENER IN AWS?
# A listener is a "rule" that tells the ALB:
# "When you receive traffic on port X using protocol Y, do Z with it"
#
# The ALB can have multiple listeners:
# - One for port 80 (HTTP)
# - One for port 443 (HTTPS)
# - Each listener has its own rules and actions
resource "aws_lb_listener" "http" {
  # --------------------------------------------------------------------------
  # load_balancer_arn: Which ALB this listener belongs to
  # --------------------------------------------------------------------------
  load_balancer_arn = aws_lb.this.arn

  port     = 80
  protocol = "HTTP"

  # --------------------------------------------------------------------------
  # default_action: What to do with requests received on this listener
  # --------------------------------------------------------------------------
  default_action {
    # ------------------------------------------------------------------------
    # type: Which kind of action to perform
    # ------------------------------------------------------------------------
    type = "redirect"

    # This block specifies HOW to redirect the traffic
    redirect {
      # ----------------------------------------------------------------------
      # port: Which port to redirect to
      # ----------------------------------------------------------------------
      port     = "443"
      protocol = "HTTPS"

      # ----------------------------------------------------------------------
      # status_code: Which HTTP status code to use for redirect
      # ----------------------------------------------------------------------
      # VALUE: "HTTP_301" (Permanent Redirect)
      #
      # HTTP REDIRECT CODES:
      # - 301: Permanent redirect (what we use)
      #   - Tells browsers: "Always use HTTPS from now on"
      #   - Browsers cache this and skip HTTP next time
      #   - Search engines update their links to HTTPS
      #
      # - 302: Temporary redirect
      #   - Tells browsers: "Use HTTPS this time, but might change later"
      #   - Browsers DON'T cache it
      #   - Would redirect every single time (slower)
      #
      status_code = "HTTP_301"
    }
  }
}

# ------------------------------------------------------------------------------
# HTTPS LISTENER - Handles secure traffic and forwards to backend
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  # --------------------------------------------------------------------------
  # count: Only create if HTTPS is enabled
  # --------------------------------------------------------------------------
  # CONDITION: var.enable_https
  # - Must be a plan-time boolean value
  # - Certificate ARN must be provided when enabled
  # - Using boolean instead of checking certificate_arn to work with computed values
  count = var.enable_https ? 1 : 0

  # --------------------------------------------------------------------------
  # load_balancer_arn: Which ALB this listener belongs to
  # --------------------------------------------------------------------------
  load_balancer_arn = aws_lb.this.arn

  port     = 443
  protocol = "HTTPS"

  # --------------------------------------------------------------------------
  # ssl_policy: Which SSL/TLS security settings to use
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Defines which encryption protocols and ciphers are allowed
  # VALUE: "ELBSecurityPolicy-TLS13-1-2-2021-06"
  #
  # SSL POLICY EXPLAINED:
  # - A pre-defined set of security rules
  # - Controls which TLS versions are accepted
  # - Controls which encryption algorithms (ciphers) are allowed
  # - Balances security and compatibility
  #
  # TLS VERSIONS:
  # - TLS 1.0: Old, insecure (deprecated)
  # - TLS 1.1: Old, insecure (deprecated)
  # - TLS 1.2: Secure, widely supported
  # - TLS 1.3: Most secure, modern
  #
  # THIS POLICY: ELBSecurityPolicy-TLS13-1-2-2021-06
  # - Supports TLS 1.2 and TLS 1.3
  # - Uses strong encryption ciphers
  # - Meets modern security standards
  # - Released June 2021 by AWS
  #
  # WHY THIS POLICY?
  # - Balances security and compatibility
  # - Supports modern browsers (Chrome, Firefox, Safari, Edge)
  # - Blocks old, insecure connections
  # - Recommended by AWS for most use cases
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # --------------------------------------------------------------------------
  # certificate_arn: Which SSL certificate to use
  # --------------------------------------------------------------------------
  certificate_arn = var.certificate_arn

  dynamic "default_action" {
    # PROD posture: explicit host rules only; default should be a hard 404.
    for_each = var.enable_host_routing ? [1] : []
    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    # DEV posture: forward by default (keeps setup simple/cheap).
    for_each = var.enable_host_routing ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.backend.arn
    }
  }
}

# ------------------------------------------------------------------------------
# HTTPS LISTENER RULE - api.<domain_name> -> backend target group
# ------------------------------------------------------------------------------
resource "aws_lb_listener_rule" "api_host" {
  count = (var.enable_https && var.enable_host_routing) ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = ["api.${var.domain_name}"]
    }
  }
}

# ------------------------------------------------------------------------------
# HTTPS LISTENER RULE - driver.<domain_name> -> driver target group
# ------------------------------------------------------------------------------
resource "aws_lb_listener_rule" "driver_host" {
  count = (var.enable_driver_web && var.enable_https) ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.driver_web[0].arn
  }

  condition {
    host_header {
      values = ["driver.${var.domain_name}"]
    }
  }
}

# ------------------------------------------------------------------------------
# TARGET GROUP ATTACHMENT - Registers backend server with target group
# ------------------------------------------------------------------------------
# WHAT IS THIS RESOURCE?
# - Registers a specific EC2 instance to receive traffic from the ALB
resource "aws_lb_target_group_attachment" "backend_instance" {
  count = var.attach_targets ? 1 : 0
  # --------------------------------------------------------------------------
  # target_group_arn: Which target group to add this server to
  # --------------------------------------------------------------------------
  target_group_arn = aws_lb_target_group.backend.arn

  # --------------------------------------------------------------------------
  # target_id: Which server/instance to register
  # --------------------------------------------------------------------------
  target_id = var.target_instance_id
  port      = var.target_port

  lifecycle {
    precondition {
      condition     = var.target_instance_id != ""
      error_message = "attach_targets=true requires target_instance_id to be set."
    }
  }
}

resource "aws_lb_target_group_attachment" "driver_instance" {
  count = (var.attach_targets && var.enable_driver_web) ? 1 : 0

  target_group_arn = aws_lb_target_group.driver_web[0].arn
  target_id        = var.driver_target_instance_id
  port             = var.driver_target_port
}

# ==============================================================================
# OUTPUT VALUES - Information exposed by this module
# ==============================================================================
output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name (useful when Route53 alias not configured)"
}

output "alb_zone_id" {
  value       = aws_lb.this.zone_id
  description = "ALB hosted zone id (required for Route53 alias records)"
}

output "alb_arn_suffix" {
  value       = aws_lb.this.arn_suffix
  description = "ALB ARN suffix (for CloudWatch dimensions)"
}

output "backend_target_group_arn" {
  value       = aws_lb_target_group.backend.arn
  description = "Backend target group ARN (useful for ASG attachment)"
}

output "backend_target_group_arn_suffix" {
  value       = aws_lb_target_group.backend.arn_suffix
  description = "Backend target group ARN suffix (for CloudWatch dimensions)"
}

output "driver_target_group_arn" {
  value       = try(aws_lb_target_group.driver_web[0].arn, "")
  description = "Driver target group ARN (useful for ASG attachment)"
}

output "driver_target_group_arn_suffix" {
  value       = try(aws_lb_target_group.driver_web[0].arn_suffix, "")
  description = "Driver target group ARN suffix (for CloudWatch dimensions)"
}
