# ========================================
# SECTION 1: ALB (APPLICATION LOAD BALANCER) SECURITY GROUP
# ========================================
# WHAT IS AN ALB?
#   The Application Load Balancer is like a receptionist:
#   - Users connect to the ALB (with HTTPS)
#   - ALB receives the request and distributes ("balances") it to backend servers
#   - It health-checks backend servers (are they alive and working?)
#
# WHY DO WE NEED AN ALB SECURITY GROUP?
#   - The ALB itself is an AWS resource that needs network access rules
#   - It must accept connections from the internet (port 443 HTTPS)
#   - It must be able to forward traffic to backend servers (port 3000)
#   - If we didn't restrict this, the backend API would be directly exposed to the internet
#
# WHEN WOULD WE USE THIS?
#   Every production architecture needs a load balancer in front of app servers.
#   This security group protects the ALB itself.
resource "aws_security_group" "alb" {
  name        = "${var.environment}-${var.project_name}-alb"
  description = "Security group for Application Load Balancer (${var.environment})"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-alb"
      Environment = var.environment
      Service     = "alb"
    }
  )
}

# ========================================
# ALB INBOUND RULES (traffic coming INTO the ALB)
# ========================================
# CONCEPT: Inbound rules = Ingress = "who is allowed to connect TO this resource?"
# QUESTION: Should we allow everyone on the internet to reach our ALB?
# ANSWER: YES! That's the whole point - ALB is publicly accessible

# ----------------------------------------
# ALB Inbound Rule #1: HTTPS from internet
# ----------------------------------------
# WHY THIS RULE:
#   Users on the internet want to reach our application (example: https://ridebooking.com)
#   HTTPS = HTTP Secure = encrypted, safe connection
#   Port 443 = default HTTPS port
#
# WHAT HAPPENS WITHOUT THIS RULE:
#   Users get "connection refused" or timeout - they can't reach the website
#
# WHO CAN USE THIS:
#   Anyone on the internet (0.0.0.0/0 means "all IPv4 addresses")
#   Think: if you publish a website, you want the whole world to reach it
#
# SECURITY IMPLICATIONS:
#   This IS open to the internet, but HTTPS means traffic is encrypted
#   (attacker can see you're connecting, but not what you're sending)

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  # The ID of the security group where this ingress rule will be attached
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"
  # IPv4 CIDR block allowed to access this security group
  cidr_ipv4 = "0.0.0.0/0"
  # Starting port of the allowed port range
  from_port = 443
  # Ending port of the allowed port range
  to_port = 443
  # Network protocol used for this rule
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-https"
    }
  )
}

# ----------------------------------------
# ALB Inbound Rule #2: HTTP from internet
# ----------------------------------------
# WHY THIS RULE:
#   Users might try to connect to http://ridebooking.com (without "s")
#   We want to redirect them to HTTPS (secure version)
#   To do the redirect, ALB must FIRST accept the HTTP connection on port 80
#
# WHAT HAPPENS WITHOUT THIS RULE:
#   Users trying http:// get "connection refused" before redirect can happen
#
# SECURITY NOTE:
#   This rule is only used for the redirect. The ALB immediately sends a
#   "301 Permanent Redirect" message: "Use HTTPS instead"
#   We don't serve actual content over HTTP (that would be insecure)

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP from internet (redirect to HTTPS)"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-http"
    }
  )
}

# ========================================
# ALB OUTBOUND RULES (traffic going OUT FROM the ALB)
# ========================================
# CONCEPT: Outbound rules = Egress = "who is allowed to receive connections FROM this resource?"


# ----------------------------------------
# ALB Outbound Rule #1: HTTP to Backend API
# ----------------------------------------
# WHY THIS RULE:
#   ALB receives HTTPS from users
#   ALB needs to forward that to backend API (NestJS) on port 3000
#   This is how the request reaches your actual application code
#
# SECURITY: Using referenced_security_group_id instead of CIDR
#   Instead of "0.0.0.0/0" (anywhere), we use the backend_api security group
#   This means: "Allow traffic ONLY to instances that have backend_api security group"
#   If you spin up a new EC2 instance WITHOUT backend_api security group,
#   ALB cannot send traffic to it (prevents accidental misconfiguration)
#
# WHAT HAPPENS WITHOUT THIS RULE:
#   ALB accepts the user request but cannot forward it to backend
#   Users get "503 Service Unavailable" or timeout

resource "aws_vpc_security_group_egress_rule" "alb_to_backend_api" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP to backend API targets"
  # The destination security group that is allowed to receive traffic
  referenced_security_group_id = aws_security_group.backend_api.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-to-backend-api"
    }
  )
}

# ----------------------------------------
# ALB Outbound Rule #2: HTTP to Driver Web
# ----------------------------------------
# WHY THIS RULE:
#   ALB also forwards traffic to driver web app (Next.js)
#   Driver web is separate from backend API (different application)
#   Same concept as backend API rule above
#
# WHICH USERS REACH DRIVER WEB:
#   Not all users - only "drivers" of the ride-booking service
#   ALB has logic: "Users with /driver/* path go to driver web SG"
#                  "Other requests go to backend API SG"
#
# WHAT HAPPENS WITHOUT THIS RULE:
#   Driver app requests fail - drivers can't access their dashboard

resource "aws_vpc_security_group_egress_rule" "alb_to_driver_web" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP to driver web targets"
  # The destination security group that is allowed to receive traffic
  referenced_security_group_id = aws_security_group.driver_web.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-alb-to-driver-web"
    }
  )
}

# ========================================
# SECTION 2: BACKEND API SECURITY GROUP (NestJS Application)
# ========================================
# WHAT IS THE BACKEND API?
#   This is your NestJS application server - the "brain" of the system
#   It handles business logic: matching rides, processing payments, etc.
#
# KEY PRINCIPLE:
#   Backend API should NEVER accept traffic directly from the internet
#   It should ONLY accept traffic from the ALB (load balancer)
#   If ALB is down, backend becomes unreachable from internet (by design - safer)
#
# WHY IS THIS SAFER?
#   - If someone hacks the internet-facing ALB, they still can't reach backend API directly
#   - Backend API's location and port (3000) are hidden from the internet
#   - Attacker would need to: (1) breach ALB, (2) find out backend API SG, (3) check if they're allowed
#     This creates multiple layers of defense

# ----------------------------------------
# Create Backend API Security Group
# ----------------------------------------
# This is where we define the "firewall" rules for our backend API
resource "aws_security_group" "backend_api" {
  name        = "${var.environment}-${var.project_name}-backend-api"
  description = "Security group for backend API (NestJS) - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-backend-api"
      Environment = var.environment
      Service     = "backend-api"
    }
  )
}

# ========================================
# Backend API INBOUND RULES
# ========================================
# PHILOSOPHY: "Backend should be invisible from internet"
# Only one inbound rule: accept from ALB

# ----------------------------------------
# Backend API Inbound Rule: HTTP from ALB only
# ----------------------------------------
# WHY THIS RULE:
#   ALB receives user requests on HTTPS port 443
#   ALB forwards to backend API on HTTP port 3000 (they're in same VPC, so no need for HTTPS)
#   Without this rule, backend API rejects all connections, even from ALB
#
# referenced_security_group_id vs CIDR:
#   BAD: cidr_ipv4 = "0.0.0.0/0" (anyone can reach backend)
#   GOOD: referenced_security_group_id = ALB SG (only ALB can reach backend)
#   We use GOOD approach - tighter security
#
# WHAT HAPPENS IF THIS RULE IS REMOVED:
#   ALB receives request from user
#   ALB tries to forward to backend API
#   Backend API security group says "NO" (ingress rule doesn't allow ALB)
#   ALB gets timeout and returns "503 Service Unavailable" to user
#
# WHAT IF THE RULE ALLOWED 0.0.0.0/0:
#   Anyone on the internet could directly connect to port 3000
#   They could bypass ALB's rate limiting and SSL/TLS handling
#   They could extract API responses without encryption
#   They could attack backend API more easily

resource "aws_vpc_security_group_ingress_rule" "backend_api_from_alb" {
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow HTTP from ALB only"
  # The destination security group that is allowed to receive traffic
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-from-alb"
    }
  )
}

# DEV convenience: when ALB is disabled, allow VPC-local HTTP so engineers can
# reach the backend via SSM port forwarding without opening the internet.
resource "aws_vpc_security_group_ingress_rule" "backend_api_from_vpc" {
  count             = var.enable_alb ? 0 : 1
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow HTTP from VPC CIDR when ALB is off"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-from-vpc"
    }
  )
}

# ========================================
# Backend API OUTBOUND RULES
# ========================================
# PRINCIPLE: Only allow outbound to what backend actually needs
#            Block everything else (default deny outbound)

# ----------------------------------------
# Backend API Outbound Rule #1: HTTPS within VPC
# ----------------------------------------
# WHAT HAPPENS IF THIS RULE IS REMOVED:
#   Backend can't call AWS APIs
#   Secrets Manager calls fail - can't get database password
#   CloudWatch calls fail - logs are lost
#   Application crashes due to missing credentials

resource "aws_vpc_security_group_egress_rule" "backend_api_vpc_https" {
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow HTTPS within VPC (for VPC endpoints)"
  # IPv4 CIDR block that outbound traffic is allowed to reach
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-https-vpc"
    }
  )
}

# When NAT gateway is enabled, allow the backend instance to reach the public
# internet over HTTPS for OS updates and package installs.
resource "aws_vpc_security_group_egress_rule" "backend_api_internet_https" {
  count             = var.enable_nat_gateway ? 1 : 0
  security_group_id = aws_security_group.backend_api.id

  description = "Allow HTTPS to internet via NAT"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-https-internet"
    }
  )
}

# ----------------------------------------
# Backend API Outbound Rule #2: HTTP within VPC
# ----------------------------------------
# WHAT HAPPENS IF THIS RULE IS MISSING:
#   npm install fails if trying to download from HTTP registry
#   Some package downloads timeout
#   Build process hangs during "Installing dependencies"

resource "aws_vpc_security_group_egress_rule" "backend_api_vpc_http" {
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow HTTP within VPC (for internal services)"
  # IPv4 CIDR block that outbound traffic is allowed to reach
  cidr_ipv4   = var.vpc_cidr
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-http-vpc"
    }
  )
}

# ----------------------------------------
# Backend API Outbound Rule #3: MySQL within VPC (to reach RDS)
# ----------------------------------------
# NOTE:
# This module uses explicit (locked-down) egress rules. If we only allow egress
# by referencing the RDS security group, we'd need to pass the RDS SG ID into
# this module. In this stack, that would create a dependency cycle.
#
# So we allow MySQL (3306) to the VPC CIDR. RDS itself is still protected by its
# own security group ingress rules (SG reference), so this is safe for DEV.
resource "aws_vpc_security_group_egress_rule" "backend_api_mysql_vpc" {
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow MySQL within VPC (for RDS)"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 3306
  to_port           = 3306
  ip_protocol       = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-mysql-vpc"
    }
  )
}

# ----------------------------------------
# Backend API Outbound Rule #3: MySQL to RDS
# ----------------------------------------
# WHAT HAPPENS IF THIS RULE IS REMOVED:
#   SELECT queries timeout
#   INSERT/UPDATE queries timeout  
#   Database connection pool errors in logs
#   Application crashes: "Cannot connect to database"

resource "aws_vpc_security_group_egress_rule" "backend_api_to_rds" {
  count             = var.rds_security_group_id != "" ? 1 : 0
  security_group_id = aws_security_group.backend_api.id
  description       = "Allow MySQL to RDS"
  # The destination security group that is allowed to receive traffic
  referenced_security_group_id = var.rds_security_group_id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-backend-api-to-rds"
    }
  )
}

# ========================================
# SECTION 3: DRIVER WEB SECURITY GROUP (Next.js Application)
# ========================================
# WHY SEPARATE FROM BACKEND?
#   - Backend API is REST/GraphQL interface used by mobile apps and other clients
#   - Driver Web is Server-Side Rendered (SSR) web application - serves HTML to browser
#   - They can scale independently (backend might need more power than web app)
#   - Different teams might manage them separately
#
# SECURITY:
#   Like backend API, driver web should NOT be accessible directly from internet
#   Must go through ALB for SSL/TLS termination and rate limiting

# ----------------------------------------
# Create Driver Web Security Group
# ----------------------------------------
resource "aws_security_group" "driver_web" {
  name        = "${var.environment}-${var.project_name}-driver-web"
  description = "Security group for driver web app (Next.js) - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-driver-web"
      Environment = var.environment
      Service     = "driver-web"
    }
  )
}

# ========================================
# Driver Web INBOUND RULES
# ========================================
# Only one inbound rule: accept from ALB (same as backend API)

# ----------------------------------------
# Driver Web Inbound Rule: HTTP from ALB only
# ----------------------------------------
# SECURITY BENEFIT:
#   Driver web endpoint and port are not exposed to internet
#   Only ALB knows about driver web (internal detail)
#   If attacker tries to reach port 3000 from internet, connection is blocked
#
# WHAT HAPPENS IF THIS RULE IS MISSING:
#   Users can't access /driver/* pages
#   ALB returns "503 Service Unavailable"

resource "aws_vpc_security_group_ingress_rule" "driver_web_from_alb" {
  security_group_id = aws_security_group.driver_web.id

  description = "Allow HTTP from ALB only"
  # The destination security group that is allowed to receive traffic
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-from-alb"
    }
  )
}

# ========================================
# Driver Web OUTBOUND RULES
# ========================================
# Driver web needs to reach internal services (AWS APIs) but not internet

# ----------------------------------------
# Driver Web Outbound Rule #1: HTTPS within VPC
# ----------------------------------------
# SAME LOGIC AS BACKEND:
#   Restricted to VPC CIDR (not 0.0.0.0/0)
#   Driver web can't reach internet directly, only internal services
#   If you need external API calls, route through backend API instead
#
# WHAT HAPPENS IF MISSING:
#   CloudWatch logging might fail
#   Configuration fetch from Secrets Manager fails
#   Some features requiring AWS API calls won't work

resource "aws_vpc_security_group_egress_rule" "driver_web_vpc_https" {
  security_group_id = aws_security_group.driver_web.id

  description = "Allow HTTPS within VPC (for VPC endpoints)"
  # IPv4 CIDR block that outbound traffic is allowed to reach
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-https-vpc"
    }
  )
}

# ----------------------------------------
# Driver Web Outbound Rule #2: HTTP within VPC
# ----------------------------------------
# SAME PRINCIPLE AS BACKEND:
#   Restricted to VPC CIDR only
#   Cannot reach internet via HTTP
#   For production, use HTTPS for all external communication
#
# WHAT HAPPENS IF MISSING:
#   npm install might fail during deployment
#   Build process hangs waiting for HTTP dependencies

resource "aws_vpc_security_group_egress_rule" "driver_web_vpc_http" {
  security_group_id = aws_security_group.driver_web.id

  description = "Allow HTTP within VPC (for internal services)"
  # IPv4 CIDR block that outbound traffic is allowed to reach
  cidr_ipv4   = var.vpc_cidr
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project_name}-driver-web-http-vpc"
    }
  )
}

# ========================================
# SECTION 4: RDS DATABASE SECURITY GROUP
# ========================================
# NOTE: RDS security group is managed by the RDS module
# The RDS module creates its own security group with ingress/egress rules
# This security-groups module only needs to reference it for backend_api egress
#
# WHY THIS APPROACH:
#   - RDS module is self-contained and manages its own security
#   - Avoids duplication between modules
#   - RDS security group lifecycle is tied to RDS instance
#   - Backend API egress rule references the RDS SG via variable
#
# SEE: modules/rds/main.tf for RDS security group definition
