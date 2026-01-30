# ----------------------------------------------------------------------------
# LOCAL VALUES
# ----------------------------------------------------------------------------
# "locals" are like variables that you calculate INSIDE this file.
# Think of them as shortcuts to avoid repeating the same logic multiple times.
locals {
  # The lookup() function searches for a key in a map:
  # - lookup(map, key, default)
  # - If "Project" exists in var.tags, use its value
  # - If "Project" doesn't exist, use "project" as fallback
  name_prefix = lookup(var.tags, "Project", "project")
  env         = lookup(var.tags, "Environment", "env")

  # DB subnets are optional (PROD uses them; DEV typically does not).
  enable_private_db_tier    = length(var.private_db_subnet_cidrs) > 0
  private_db_cidr           = try(var.private_db_subnet_cidrs[0], null)
  private_db_cidr_secondary = try(var.private_db_subnet_cidrs[1], null)
}

# ----------------------------------------------------------------------------
# INPUT VALIDATION (CROSS-VARIABLE)
# ----------------------------------------------------------------------------
# Terraform variable `validation {}` blocks may only reference the variable
# being validated. For module-wide checks (e.g., enable_multi_az implies other
# inputs are required), use resource preconditions instead.
resource "terraform_data" "input_validation" {
  input = {
    enable_multi_az             = var.enable_multi_az
    az_count                    = var.az_count
    public_subnet_cidr_secondary  = var.public_subnet_cidr_secondary
    private_subnet_cidr_secondary = var.private_subnet_cidr_secondary
    availability_zone_secondary   = var.availability_zone_secondary
  }

  lifecycle {
    precondition {
      condition = !var.enable_multi_az || (
        var.az_count >= 2 &&
        var.public_subnet_cidr_secondary != null &&
        var.private_subnet_cidr_secondary != null &&
        var.availability_zone_secondary != null
      )
      error_message = "When enable_multi_az is true, set az_count to 2 and provide public_subnet_cidr_secondary, private_subnet_cidr_secondary, and availability_zone_secondary."
    }
  }
}

# ----------------------------------------------------------------------------
# VPC (Virtual Private Cloud)
# ----------------------------------------------------------------------------
# *** WHAT IS A VPC? ***
# A VPC is like your own private section of AWS's massive data center.
# It's a virtual network that you completely control.
#
# *** WHY DO WE NEED IT? ***
# - AWS requires a VPC to launch most resources (EC2, RDS, Lambda, etc.)
# - It provides network isolation for security
# - You control IP addresses, subnets, and routing
#
# *** WHAT HAPPENS IF YOU DON'T CREATE ONE? ***
# - You can't launch databases, servers, or most AWS services
# - AWS might use a default VPC, but you have no control over it
resource "aws_vpc" "this" {
  # cidr_block: The IP address range for your entire VPC
  # Example: "10.0.0.0/16" means you get 65,536 possible IP addresses
  #
  # CIDR notation explained:
  # - 10.0.0.0/16 means: "10.0.0.0 to 10.0.255.255"
  # - The "/16" means the first 16 bits are fixed, rest are flexible
  #
  # WHY THIS MATTERS:
  # - This range must be large enough for all your resources
  # - It must not overlap with other networks you might connect to
  # - Common mistake: choosing too small a range and running out of IPs
  cidr_block = var.vpc_cidr

  # enable_dns_support: Enables AWS's DNS server inside the VPC
  # Set to "true" means: AWS will provide a DNS server at 10.0.0.2
  #
  # WHAT IS DNS?
  # DNS translates human-readable names (like "google.com") to IP addresses.
  #
  # WHY ENABLE THIS?
  # - Your EC2 instances need DNS to access AWS services by name
  # - Example: "s3.amazonaws.com" instead of an IP address
  # - If you set this to "false", your instances can't resolve domain names
  enable_dns_support = true

  # enable_dns_hostnames: Gives your EC2 instances automatic DNS names
  # Set to "true" means: EC2 instances get names like "ec2-54-12-34-56.compute.amazonaws.com"
  #
  # WHY ENABLE THIS?
  # - Makes it easier to identify and connect to instances
  # - Required if you want to use AWS services with friendly names
  # - If "false", you'd have to use raw IP addresses (hard to remember)
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-vpc"
  })
}

# ----------------------------------------------------------------------------
# INTERNET GATEWAY
# ----------------------------------------------------------------------------
# *** WHAT IS AN INTERNET GATEWAY? ***
# An Internet Gateway (IGW) is like the front door to the internet.
# It allows resources inside your VPC to communicate with the internet.
#
# *** WHY DO WE NEED IT? ***
# - Without it, nothing in your VPC can access the internet
# - It's required for public-facing resources (web servers, APIs)
# - It handles translation between private IPs (inside VPC) and public IPs (internet)
#
# *** WHAT HAPPENS IF YOU DON'T CREATE ONE? ***
# - Your web applications can't serve traffic from the internet
# - Users can't access your website or API
# - Your servers can't download updates from the internet
resource "aws_internet_gateway" "this" {
  # vpc_id: Which VPC this Internet Gateway belongs to
  #
  # WHY THIS MATTERS:
  # - An Internet Gateway must be attached to exactly one VPC
  # - We reference the VPC we created above using "aws_vpc.this.id"
  # - This creates a dependency: Terraform will create the VPC first
  #
  # TERRAFORM CONCEPT: Resource References
  # - "aws_vpc.this.id" means: "the ID of the VPC resource named 'this'"
  # - Terraform automatically knows to create the VPC before the IGW
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-igw"
  })
}

# ----------------------------------------------------------------------------
# PUBLIC SUBNET
# ----------------------------------------------------------------------------
# *** WHAT IS A SUBNET? ***
# A subnet is a subdivision of your VPC. Think of it like a department
# within your office building - each department is on a different floor.
#
# *** WHAT IS A PUBLIC SUBNET? ***
# A "public" subnet is one that has a route to the Internet Gateway.
# Resources here can be accessed from the internet (if you allow it).
#
# *** COMMON USE CASES ***
# - Load balancers (receive traffic from users)
# - Bastion hosts (jump servers for SSH access)
# - NAT Gateways (allow private resources to reach internet)
#
# *** WHAT HAPPENS IF YOU DON'T CREATE IT? ***
# - You can't deploy internet-facing resources
# - Users can't reach your application
resource "aws_subnet" "public" {
  # vpc_id: Which VPC this subnet belongs to
  # A subnet must live inside a VPC
  vpc_id = aws_vpc.this.id

  # cidr_block: The IP address range for this subnet
  #
  # MUST BE SMALLER than the VPC CIDR block
  # Example:
  # - VPC: 10.0.0.0/16 (65,536 IPs)
  # - Public Subnet: 10.0.1.0/24 (256 IPs)
  # - Private Subnet: 10.0.2.0/24 (256 IPs)
  #
  # WHY THIS MATTERS:
  # - Determines how many resources you can launch in this subnet
  # - Must not overlap with other subnets
  cidr_block = var.public_subnet_cidr

  # availability_zone: Which AWS data center this subnet lives in
  #
  # WHAT IS AN AVAILABILITY ZONE?
  # AWS has multiple data centers in each region (us-east-1a, us-east-1b, etc.)
  # Each data center is called an "Availability Zone" (AZ).
  #
  # WHY SPECIFY THIS?
  # - For single-AZ deployments (dev/test) to save costs
  # - In production, you'd create subnets in multiple AZs for high availability
  availability_zone = var.availability_zone

  # map_public_ip_on_launch: Should instances automatically get public IPs?
  # Set to "false" means: Instances in this subnet do NOT get public IPs automatically
  #
  # WHY SET TO FALSE?
  # - More secure: You explicitly decide which resources are public
  # - Common mistake: Leaving this "true" and accidentally exposing databases
  # - Best practice: Use a load balancer with a public IP, keep instances private
  #
  # WHAT IF YOU SET IT TO TRUE?
  # - Every EC2 instance launched here would get a public IP
  # - Security risk if you forget to configure security groups properly
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-public-${var.availability_zone}"
    Tier = "public"
  })
}

# ----------------------------------------------------------------------------
# SECONDARY PUBLIC SUBNET (OPTIONAL)
# ----------------------------------------------------------------------------
# Provides the second AZ required for internet-facing ALB while keeping costs low.
resource "aws_subnet" "public_secondary" {
  count = var.public_subnet_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidr_secondary
  availability_zone = var.availability_zone_secondary

  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-public-${var.availability_zone_secondary}"
    Tier = "public"
  })
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET
# ----------------------------------------------------------------------------
# *** WHAT IS A PRIVATE SUBNET? ***
# A "private" subnet is one that does NOT have a direct route to the Internet Gateway.
# Resources here cannot be directly accessed from the internet.
#
# *** WHY DO WE NEED IT? ***
# - Security: Keep databases and application servers away from public internet
# - Defense in depth: Even if one security layer fails, these resources are protected
#
# *** COMMON USE CASES ***
# - Databases (RDS, Aurora)
# - Application servers (EC2 running your backend)
# - Internal services (caching, queuing)
#
# *** HOW DO PRIVATE RESOURCES ACCESS THE INTERNET? ***
# - Through a NAT Gateway (explained later)
# - Example: To download software updates or call external APIs
resource "aws_subnet" "private" {
  # vpc_id: Which VPC this subnet belongs to
  vpc_id = aws_vpc.this.id

  # cidr_block: IP range for private subnet
  # Must be different from the public subnet CIDR
  cidr_block = var.private_subnet_cidr

  # availability_zone: Same AZ as public subnet for simplicity
  availability_zone = var.availability_zone

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-${var.availability_zone}"
    Tier = "private"
  })
}

# ----------------------------------------------------------------------------
# SECONDARY PRIVATE SUBNET (OPTIONAL)
# ----------------------------------------------------------------------------
# Created only when a secondary CIDR and AZ are provided.
resource "aws_subnet" "private_secondary" {
  count = var.private_subnet_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  vpc_id     = aws_vpc.this.id
  cidr_block = var.private_subnet_cidr_secondary

  availability_zone = var.availability_zone_secondary

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-${var.availability_zone_secondary}"
    Tier = "private"
  })
}

# ----------------------------------------------------------------------------
# PRIVATE DB SUBNET (OPTIONAL)
# ----------------------------------------------------------------------------
# Separate DB subnet tier for PROD (e.g., RDS). Kept optional with safe defaults
# so DEV behavior remains unchanged.
resource "aws_subnet" "private_db" {
  count = local.enable_private_db_tier && local.private_db_cidr != null ? 1 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_db_cidr
  availability_zone = var.availability_zone

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-db-${var.availability_zone}"
    Tier = "private-db"
  })
}

# ----------------------------------------------------------------------------
# SECONDARY PRIVATE DB SUBNET (OPTIONAL)
# ----------------------------------------------------------------------------
resource "aws_subnet" "private_db_secondary" {
  count = local.enable_private_db_tier && local.private_db_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_db_cidr_secondary
  availability_zone = var.availability_zone_secondary

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-db-${var.availability_zone_secondary}"
    Tier = "private-db"
  })
}

# ----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE
# ----------------------------------------------------------------------------
# *** WHAT IS A ROUTE TABLE? ***
# A route table is like a GPS for network traffic. It tells traffic
# where to go based on the destination IP address.
#
# *** WHY DO WE NEED IT? ***
# - By default, subnets can't communicate with anything
# - Route tables define what networks are reachable
# - Every subnet must be associated with exactly one route table
#
# *** WHAT HAPPENS WITHOUT A ROUTE TABLE? ***
# - Network traffic doesn't know where to go
# - Your application can't access the internet or other subnets
resource "aws_route_table" "public" {
  # vpc_id: Which VPC this route table belongs to
  # Route tables are scoped to a single VPC
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-public-rt"
  })
}

# ----------------------------------------------------------------------------
# PUBLIC INTERNET ROUTE
# ----------------------------------------------------------------------------
# *** WHAT IS A ROUTE? ***
# A route is a single rule in a route table that says:
# "If traffic is going to X, send it through Y"
#
# *** WHAT DOES THIS SPECIFIC ROUTE DO? ***
# This route says: "All internet traffic (0.0.0.0/0) should go through
# the Internet Gateway"
#
# *** WHY IS THIS CRITICAL? ***
# - This is what makes the public subnet actually "public"
# - Without this route, resources in the public subnet can't reach the internet
# - The "0.0.0.0/0" means "any IP address" (the entire internet)
resource "aws_route" "public_internet" {
  # route_table_id: Which route table we're adding this route to
  # We're adding it to the public route table created above
  route_table_id = aws_route_table.public.id

  # destination_cidr_block: Where is the traffic going?
  # "0.0.0.0/0" is a special CIDR that means "everywhere" / "the entire internet"
  # WHY USE "0.0.0.0/0"?
  # - It's a catch-all for any traffic not destined for the VPC itself
  # - Think of it as the "default" route
  destination_cidr_block = "0.0.0.0/0"

  # gateway_id: Where should the traffic go?
  # Send it to the Internet Gateway we created earlier
  #
  # WHY THE INTERNET GATEWAY?
  # - It's the only way for VPC resources to reach the public internet
  # - It handles the translation between private VPC IPs and public IPs
  gateway_id = aws_internet_gateway.this.id
}

# ----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE ASSOCIATION
# ----------------------------------------------------------------------------
# *** WHAT IS A ROUTE TABLE ASSOCIATION? ***
# This connects a subnet to a route table.
# Think of it like assigning a department to follow a specific mail delivery policy.
#
# *** WHY IS THIS NEEDED? ***
# - Creating a route table and a subnet is not enough
# - You must explicitly connect them
# - This association says: "Public subnet, use the public route table"
#
# *** WHAT HAPPENS WITHOUT THIS? ***
# - The subnet would use the VPC's default route table
# - The default route table might not have a route to the internet
# - Your public subnet wouldn't actually be public
resource "aws_route_table_association" "public" {
  # subnet_id: Which subnet we're configuring
  subnet_id = aws_subnet.public.id

  # route_table_id: Which route table to use for this subnet
  # We're connecting the public subnet to the public route table
  # This gives the public subnet access to the internet
  route_table_id = aws_route_table.public.id
}

# Optional association for the secondary public subnet (required when ALB is enabled).
resource "aws_route_table_association" "public_secondary" {
  count = var.public_subnet_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  subnet_id      = aws_subnet.public_secondary[0].id
  route_table_id = aws_route_table.public.id
}

# ----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE
# ----------------------------------------------------------------------------
# *** WHY DO WE NEED A SEPARATE ROUTE TABLE FOR PRIVATE SUBNET? ***
# - Private subnet should NOT have a direct route to the Internet Gateway
# - It might have a route to a NAT Gateway (for outbound-only internet access)
# - Separating route tables gives us fine-grained control
#
# *** WHAT MAKES IT "PRIVATE"? ***
# - It doesn't have a route to the Internet Gateway
# - Traffic from the internet cannot reach resources in this subnet
# - Resources here can only be accessed from within the VPC (or via VPN)
resource "aws_route_table" "private" {
  # vpc_id: Which VPC this route table belongs to
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-rt"
  })
}

# ----------------------------------------------------------------------------
# PRIVATE DB ROUTE TABLE (OPTIONAL)
# ----------------------------------------------------------------------------
# Separate route table for the DB tier.
# Security default: no 0.0.0.0/0 route is added here.
# - RDS (managed) typically doesn't require NAT for patching.
# - If a future workload requires outbound internet from DB subnets, add an
#   explicit variable and route in a backward-compatible way.
resource "aws_route_table" "private_db" {
  count  = local.enable_private_db_tier ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-db-rt"
  })
}

# ----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE ASSOCIATION
# ----------------------------------------------------------------------------
# *** WHAT DOES THIS DO? ***
# Connects the private subnet to the private route table.
#
# *** WHY IS THIS CRITICAL? ***
# - This ensures the private subnet uses the PRIVATE route table
# - If we connected it to the public route table by mistake, it would be public
# - This association enforces the network security boundary
resource "aws_route_table_association" "private" {
  # subnet_id: Which subnet we're configuring (the private one)
  subnet_id = aws_subnet.private.id

  # route_table_id: Which route table to use (the private one)
  route_table_id = aws_route_table.private.id
}

# ----------------------------------------------------------------------------
# SECONDARY PRIVATE ROUTE TABLE ASSOCIATION (OPTIONAL)
# ----------------------------------------------------------------------------
resource "aws_route_table_association" "private_secondary" {
  count = var.private_subnet_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  subnet_id      = aws_subnet.private_secondary[0].id
  route_table_id = aws_route_table.private.id
}

# ----------------------------------------------------------------------------
# PRIVATE DB ROUTE TABLE ASSOCIATIONS (OPTIONAL)
# ----------------------------------------------------------------------------
resource "aws_route_table_association" "private_db" {
  count = local.enable_private_db_tier && local.private_db_cidr != null ? 1 : 0

  subnet_id      = aws_subnet.private_db[0].id
  route_table_id = aws_route_table.private_db[0].id
}

resource "aws_route_table_association" "private_db_secondary" {
  count = local.enable_private_db_tier && local.private_db_cidr_secondary != null && var.availability_zone_secondary != null ? 1 : 0

  subnet_id      = aws_subnet.private_db_secondary[0].id
  route_table_id = aws_route_table.private_db[0].id
}

# ----------------------------------------------------------------------------
# ELASTIC IP FOR NAT GATEWAY (OPTIONAL)
# ----------------------------------------------------------------------------
# *** WHAT IS AN ELASTIC IP? ***
# An Elastic IP (EIP) is a static, public IP address that you can allocate in AWS.
# Unlike normal public IPs that change when you restart resources, an EIP stays the same.
#
# *** WHY DO WE NEED IT? ***
# - The NAT Gateway requires a public IP to send traffic to the internet
# - Using an EIP ensures the IP doesn't change
# - If the NAT Gateway is replaced, we can reuse the same IP
#
# This is a conditional resource creation pattern in Terraform.
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  # domain: Where this EIP is used
  # "vpc" means this EIP is for use within a VPC (not EC2-Classic)
  #
  # HISTORICAL NOTE:
  # AWS used to have "EC2-Classic" (legacy) and "VPC" (modern)
  # Always use "vpc" for new infrastructure
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-nat-eip"
  })
}

# ----------------------------------------------------------------------------
# NAT GATEWAY (OPTIONAL)
# ----------------------------------------------------------------------------
# *** WHAT IS A NAT GATEWAY? ***
# NAT stands for "Network Address Translation".
# A NAT Gateway allows resources in a private subnet to access the internet,
# but prevents the internet from initiating connections to those resources.
#
# *** WHY DO WE NEED IT? ***
# - Private resources (like databases) need to download updates
# - Application servers in private subnets might need to call external APIs
# - Example: Your backend server needs to call the Stripe payment API
#
# *** WHY IS IT EXPENSIVE? ***
# - AWS charges ~$0.045 per hour (~$32/month) just to have it running
# - Plus data transfer charges (~$0.045 per GB)
# - In dev, you might disable it to save costs
#
# *** WHAT HAPPENS WITHOUT A NAT GATEWAY? ***
# - Private resources can't access the internet at all
# - No software updates, no external API calls
# - But also saves ~$32/month in dev environments
resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  # allocation_id: Which Elastic IP to use for this NAT Gateway
  # We reference the EIP created above using [0] because it's a count resource
  #
  # WHY [0]?
  # When you use "count", Terraform creates a list of resources.
  # Even though we only create 1 EIP, we must access it as a list: [0] = first item
  allocation_id = aws_eip.nat[0].id

  # subnet_id: Which subnet to place the NAT Gateway in
  # MUST be a public subnet because NAT Gateway needs internet access
  #
  # WHY PUBLIC SUBNET?
  # - NAT Gateway itself needs to reach the internet
  # - It acts as a middleman between private subnet and internet
  # - Placing it in private subnet would defeat its purpose
  subnet_id = aws_subnet.public.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-natgw"
  })

  depends_on = [aws_internet_gateway.this]
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET ROUTE TO NAT GATEWAY (OPTIONAL)
# ----------------------------------------------------------------------------
# *** WHAT DOES THIS ROUTE DO? ***
# This route says: "All internet traffic from the private subnet should
# go through the NAT Gateway"
#
# *** WHY IS THIS NEEDED? ***
# - Without this route, private subnet can't reach the internet
# - This enables private resources to download updates, call APIs, etc.
# - But incoming connections from internet are still blocked (NAT is one-way)
resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  # route_table_id: Which route table to add this route to
  # We're adding it to the PRIVATE route table
  route_table_id = aws_route_table.private.id

  # NOTE THE DIFFERENCE:
  # - Public subnet: 0.0.0.0/0 -> Internet Gateway (two-way)
  # - Private subnet: 0.0.0.0/0 -> NAT Gateway (outbound-only)
  destination_cidr_block = "0.0.0.0/0"

  # nat_gateway_id: Where should the traffic go?
  # Send it to the NAT Gateway we created above
  # We use [0] because nat_gateway is a count resource
  nat_gateway_id = aws_nat_gateway.this[0].id
}
