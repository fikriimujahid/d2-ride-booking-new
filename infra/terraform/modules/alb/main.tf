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
  target_type = "instance"

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
# SSL/TLS CERTIFICATE - For HTTPS encryption
# ------------------------------------------------------------------------------
# WHAT IS AN SSL/TLS CERTIFICATE?
# - A digital document that proves your website's identity
# - Like a passport or driver's license for your domain
# - Contains your domain name and a cryptographic key
# - Enables HTTPS (the lock icon in browsers)
# - Issued by a trusted Certificate Authority (CA)
#
# WHY DO WE NEED IT?
# - HTTPS requires a certificate to encrypt traffic
# - Browsers won't show the lock icon without it
# - Modern browsers show "Not Secure" warning without it
# - Required for security best practices
#
# AWS CERTIFICATE MANAGER (ACM):
# - AWS service that provides FREE SSL certificates
# - Automatically renews certificates before expiration
# - No need to buy from third-party vendors
# - Integrates seamlessly with ALB
#
# TWO WAYS TO PROVIDE A CERTIFICATE:
# 1. Use an existing certificate (pass ARN via var.certificate_arn)
# 2. Let this module create one automatically (what this resource does)
resource "aws_acm_certificate" "api" {
  count = var.certificate_arn == "" && var.hosted_zone_id != "" ? 1 : 0

  # --------------------------------------------------------------------------
  # domain_name: Which domain(s) this certificate is valid for
  # --------------------------------------------------------------------------
  domain_name = "*.${var.domain_name}"

  # --------------------------------------------------------------------------
  # validation_method: How to prove you own the domain
  # --------------------------------------------------------------------------
  # TWO VALIDATION METHODS:
  # 1. "DNS" (what we use):
  #    - AWS gives you a special DNS record
  #    - You add it to your domain's DNS settings
  #    - AWS checks if the record exists
  #    - If yes, you own the domain → certificate issued
  #
  # 2. "EMAIL":
  #    - AWS sends email to admin@yourdomain.com
  #    - You click a link in the email
  #    - More manual, harder to automate
  validation_method = "DNS"

  # --------------------------------------------------------------------------
  # lifecycle: Special Terraform behavior rules
  # --------------------------------------------------------------------------
  # WHAT IS lifecycle?
  # - Meta-arguments that control HOW Terraform manages resources
  # - Affects the order of creation and destruction
  # - Prevents downtime during updates
  lifecycle {
    # ------------------------------------------------------------------------
    # create_before_destroy: Create new resource before deleting old one
    # ------------------------------------------------------------------------
    # WHAT IT DOES: Changes the default Terraform behavior
    #
    # NORMAL TERRAFORM BEHAVIOR:
    # 1. Destroy old certificate
    # 2. Create new certificate
    # 3. Problem: Your site is down between steps 1 and 2!
    #
    # WITH create_before_destroy = true:
    # 1. Create new certificate
    # 2. Switch ALB to use new certificate
    # 3. Destroy old certificate
    # 4. Result: No downtime!
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${local.name}-cert"
    Environment = var.environment
    Service     = "backend-api"
  })
}

# ------------------------------------------------------------------------------
# DNS VALIDATION RECORDS - Proves you own the domain
# ------------------------------------------------------------------------------
# WHAT IS THIS RESOURCE?
# - Creates DNS records in Route53 to validate the SSL certificate
# - Required for ACM to issue the certificate
# - Proves to AWS that you control the domain
resource "aws_route53_record" "api_cert_validation" {
  for_each = var.certificate_arn == "" && var.hosted_zone_id != "" ? {
    for dvo in aws_acm_certificate.api[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  # --------------------------------------------------------------------------
  # zone_id: Which Route53 hosted zone to create the record in
  # --------------------------------------------------------------------------
  zone_id = var.hosted_zone_id

  # --------------------------------------------------------------------------
  # name: The DNS record name (from ACM validation requirements)
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Sets the subdomain for the validation record
  name = each.value.name

  # --------------------------------------------------------------------------
  # type: The DNS record type
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Specifies the kind of DNS record
  # VALUE: Usually "CNAME" for ACM validation
  #
  # DNS RECORD TYPES REFRESHER:
  # - "A": Maps domain to IPv4 address (e.g., 1.2.3.4)
  # - "AAAA": Maps domain to IPv6 address
  # - "CNAME": Maps domain to another domain (alias)
  # - "MX": Mail server records
  # - "TXT": Text data (used for various verifications)
  type = each.value.type

  # --------------------------------------------------------------------------
  # ttl: Time To Live - how long DNS resolvers cache this record
  # --------------------------------------------------------------------------
  # VALUE: 60 (1 minute)
  ttl = 60

  # --------------------------------------------------------------------------
  # records: The actual DNS record value(s)
  # --------------------------------------------------------------------------
  records = [each.value.record]
}

# ------------------------------------------------------------------------------
# CERTIFICATE VALIDATION WAITER - Waits for certificate to be issued
# ------------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "api" {
  count = var.certificate_arn == "" && var.hosted_zone_id != "" ? 1 : 0

  # --------------------------------------------------------------------------
  # certificate_arn: Which certificate to wait for
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Specifies which certificate we're validating
  certificate_arn = aws_acm_certificate.api[0].arn

  # --------------------------------------------------------------------------
  # validation_record_fqdns: DNS records that need to exist for validation
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Tells ACM which DNS records to check for validation
  # VALUE: List of fully qualified domain names from our validation records
  #
  # FQDN EXPLAINED:
  # - Fully Qualified Domain Name
  # - Complete domain name including all parts
  # - Example: "_abc123.d2.fikri.dev" (not just "_abc123")
  #
  # THE for EXPRESSION BREAKDOWN:
  # [for r in aws_route53_record.api_cert_validation : r.fqdn]
  # - Loops through each validation record we created
  # - Extracts the "fqdn" attribute from each
  # - Creates a list of FQDNs
  #
  # EXAMPLE RESULT: ["_abc123.d2.fikri.dev"]
  #
  # WHY THIS MATTERS:
  # - Ensures validation records are created before waiting
  # - ACM checks these specific DNS names
  # - If records don't exist, validation fails
  validation_record_fqdns = [for r in aws_route53_record.api_cert_validation : r.fqdn]
}

# ------------------------------------------------------------------------------
# HTTPS LISTENER - Handles secure traffic and forwards to backend
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  # --------------------------------------------------------------------------
  # count: Conditional creation based on certificate availability
  # --------------------------------------------------------------------------
  # COMPLEX LOGIC BREAKDOWN:
  # (var.certificate_arn != "" || var.hosted_zone_id != "") ? 1 : 0
  #
  # CONDITION 1: var.certificate_arn != ""
  # - User provided an existing certificate ARN
  # - We can use it immediately
  # - Create the listener (count = 1)
  #
  # CONDITION 2: var.hosted_zone_id != ""
  # - User provided Route53 hosted zone
  # - We can create and validate a certificate
  # - Create the listener (count = 1)
  count = (var.certificate_arn != "" || var.hosted_zone_id != "") ? 1 : 0

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
  #
  # OTHER POLICY OPTIONS:
  # - "ELBSecurityPolicy-2016-08": Very old, supports TLS 1.0 (avoid!)
  # - "ELBSecurityPolicy-TLS-1-2-2017-01": Only TLS 1.2 (no TLS 1.3)
  # - "ELBSecurityPolicy-FS-1-2-Res-2020-10": Forward secrecy focused
  #
  # ⚠️ WHAT IF YOU USE OLDER POLICY?
  # - Allows insecure TLS 1.0/1.1 connections
  # - Vulnerable to known attacks (POODLE, BEAST, etc.)
  # - Security scanners will flag it
  # - Compliance issues (PCI DSS, HIPAA, etc.)
  #
  # ⚠️ WHAT IF YOU USE TLS 1.3-ONLY POLICY?
  # - More secure
  # - But blocks older browsers/clients
  # - Some enterprise systems might not connect
  # - User complaints about compatibility
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # --------------------------------------------------------------------------
  # certificate_arn: Which SSL certificate to use
  # --------------------------------------------------------------------------
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate.api[0].arn

  depends_on = [aws_acm_certificate_validation.api]

  # --------------------------------------------------------------------------
  # default_action: What to do with requests received on this listener
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Defines how to handle HTTPS requests
  # This is the "main" action - forwarding to backend servers
  default_action {
    # ------------------------------------------------------------------------
    # type: Which kind of action to perform
    # ------------------------------------------------------------------------
    # TYPES OF ACTIONS:
    # - "forward": Send to target group (what we use)
    # - "redirect": Send to different URL (used in HTTP listener)
    # - "fixed-response": Return static content
    # - "authenticate-oidc": Require login (OAuth/OIDC)
    # - "authenticate-cognito": Require login (AWS Cognito)
    type = "forward"

    # ------------------------------------------------------------------------
    # target_group_arn: Which target group to forward to
    # ------------------------------------------------------------------------
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ------------------------------------------------------------------------------
# TARGET GROUP ATTACHMENT - Registers backend server with target group
# ------------------------------------------------------------------------------
# WHAT IS THIS RESOURCE?
# - Registers a specific EC2 instance to receive traffic from the ALB
resource "aws_lb_target_group_attachment" "backend_instance" {
  # --------------------------------------------------------------------------
  # target_group_arn: Which target group to add this server to
  # --------------------------------------------------------------------------
  target_group_arn = aws_lb_target_group.backend.arn

  # --------------------------------------------------------------------------
  # target_id: Which server/instance to register
  # --------------------------------------------------------------------------
  target_id = var.target_instance_id
  port      = var.target_port
}

# ------------------------------------------------------------------------------
# DNS RECORD FOR API - Points api.yourdomain.com to the ALB
# ------------------------------------------------------------------------------
resource "aws_route53_record" "api" {
  # --------------------------------------------------------------------------
  # count: Only create if Route53 hosted zone is available
  # --------------------------------------------------------------------------
  count = var.hosted_zone_id != "" ? 1 : 0

  # --------------------------------------------------------------------------
  # zone_id: Which Route53 hosted zone to create the record in
  # --------------------------------------------------------------------------
  zone_id = var.hosted_zone_id

  # --------------------------------------------------------------------------
  # name: The subdomain/hostname for this record
  # --------------------------------------------------------------------------
  name = "api.${var.domain_name}"

  # --------------------------------------------------------------------------
  # type: The DNS record type
  # --------------------------------------------------------------------------
  # WHAT IT DOES: Specifies this is an "A" record
  # VALUE: "A"
  #
  # DNS RECORD TYPES REFRESHER:
  # - "A": Maps domain to IPv4 address
  # - "AAAA": Maps domain to IPv6 address
  # - "CNAME": Maps domain to another domain (alias)
  # - "MX": Mail server records
  # - "TXT": Text data
  #
  # WHY "A" RECORD?
  # - "A" stands for "Address"
  # - Traditionally maps to an IP address
  # - But in AWS, we use it with an "alias" (special AWS feature)
  #
  # WAIT, BUT WE'RE NOT USING AN IP ADDRESS?
  # - True! We're using an AWS "alias" record (see below)
  # - It's still type "A", but with special alias properties
  # - AWS extension to standard DNS
  #
  # WHY NOT CNAME?
  # - CNAME can't be used for apex/root domains
  # - CNAME has extra DNS lookup overhead
  # - AWS alias records are faster and more efficient
  # - Alias records are free, CNAMEs cost money in Route53
  type = "A"

  # --------------------------------------------------------------------------
  # alias: Special AWS feature for pointing to AWS resources
  # --------------------------------------------------------------------------
  alias {
    # ------------------------------------------------------------------------
    # name: The DNS name of the AWS resource (ALB)
    # ------------------------------------------------------------------------
    name = aws_lb.this.dns_name

    # ------------------------------------------------------------------------
    # zone_id: The hosted zone ID of the AWS resource (ALB)
    # ------------------------------------------------------------------------
    zone_id = aws_lb.this.zone_id

    # ------------------------------------------------------------------------
    # evaluate_target_health: Should Route53 check if ALB is healthy?
    # ------------------------------------------------------------------------
    # HOW IT WORKS:
    # - Route53 continuously checks if ALB is responding
    # - If ALB is healthy: Return its IP addresses normally
    # - If ALB is unhealthy: Can fail over to backup (if configured)
    evaluate_target_health = true
  }
}

# ==============================================================================
# OUTPUT VALUES - Information exposed by this module
# ==============================================================================
output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name (useful when Route53 alias not configured)"
}
