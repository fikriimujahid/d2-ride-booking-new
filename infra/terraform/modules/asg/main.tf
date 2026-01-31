locals {
  name_prefix = "${var.environment}-${var.project_name}-${var.service_name}"
  image_id    = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ================================================================================
# LAUNCH TEMPLATE - THE BLUEPRINT FOR EC2 INSTANCES
# ================================================================================
# WHAT: A launch template is like a cookie cutter - it defines the shape of every instance
# WHY: ASG needs to know "what kind of instances should I create?"
# KEY DIFFERENCE FROM LAUNCH CONFIG: Templates are versioned and can be updated
resource "aws_launch_template" "this" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = local.image_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  # ================================================================================
  # METADATA OPTIONS - SECURITY HARDENING FOR IMDS
  # ================================================================================
  # WHAT: IMDS = Instance Metadata Service - a special IP (169.254.169.254) that provides
  #       instance information (IAM credentials, instance ID, region, etc.)
  # WHY: Apps running on EC2 use IMDS to get temporary AWS credentials
  # SECURITY CONCERN: Old IMDS (v1) was vulnerable to SSRF attacks
  # WHAT IS SSRF: Server-Side Request Forgery - attacker tricks your app into
  #               making requests to unintended destinations (like IMDS)
  # EXAMPLE ATTACK: Attacker sends URL "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
  #                 Your app fetches it, attacker steals IAM credentials
  metadata_options {
    # WHAT: "enabled" means IMDS is turned on
    # WHY: AWS SDKs need IMDS to get temporary credentials for the IAM role
    # IF DISABLED: Your app can't authenticate to AWS services
    http_endpoint = "enabled"

    # WHAT: "required" means IMDSv2 is enforced (session-based authentication)
    # WHY: IMDSv2 requires a PUT request to get a session token first
    # SECURITY: SSRF attacks typically use GET requests - they can't do PUT
    # BEST PRACTICE: Always set this to "required" in production
    # COMPLIANCE: Many security frameworks (SOC2, PCI-DSS) require IMDSv2
    # IF SET TO "optional": Instance is vulnerable to SSRF attacks
    http_tokens = "required" # IMDSv2 (hardening)
  }

  # ================================================================================
  # BLOCK DEVICE MAPPINGS - DISK CONFIGURATION
  # ================================================================================
  # WHAT: Defines the storage volumes attached to the instance
  # WHY: You need to specify disk size, type, encryption
  block_device_mappings {
    # WHAT: "/dev/xvda" is the device name for the root volume (primary disk)
    # WHY: Linux AMIs typically use /dev/xvda for the boot disk
    device_name = "/dev/xvda"

    # ================================================================================
    # EBS (Elastic Block Store) - AWS MANAGED DISK SERVICE
    # ================================================================================
    # WHAT: EBS is AWS's network-attached storage (like a SAN in traditional datacenters)
    # WHY: EC2 instances are ephemeral - if terminated, data is lost unless using EBS
    # TYPES: gp3 (general purpose SSD), io2 (high IOPS SSD), st1 (HDD)
    ebs {
      # WHAT: "gp3" is the latest general-purpose SSD (3rd generation)
      # WHY: Better performance and 20% cheaper than gp2
      # PERFORMANCE: 3000 IOPS baseline (suitable for most apps)
      # WHEN TO UPGRADE: If your app needs >16000 IOPS, use io2
      volume_type = "gp3"

      # TYPICAL SIZES: 20 GB (minimal), 50 GB (dev), 100 GB (prod)
      volume_size = var.root_volume_size_gb
      encrypted   = true

      # WHAT: "delete_on_termination = true" means disk is deleted when instance dies
      delete_on_termination = true
    }
  }

  # ================================================================================
  # USER DATA - BOOTSTRAP SCRIPT THAT RUNS ON FIRST BOOT
  # ================================================================================
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    # WHAT: "base64encode" converts the script to base64
    # WHY: AWS API requires user_data in base64 format
    # IF YOU FORGET: Terraform automatically encodes it anyway

    # WHAT: "templatefile" reads a file and replaces ${variables} with values
    environment  = var.environment
    service_name = var.service_name
    app_port     = tostring(var.app_port)
  }))

  # ================================================================================
  # TAG SPECIFICATIONS - TAGGING INSTANCES WHEN THEY LAUNCH
  # ================================================================================
  # WHAT: "tag_specifications" applies tags to resources created from this template
  tag_specifications {
    # WHAT: "resource_type = instance" means "tag the EC2 instance itself"
    resource_type = "instance"

    tags = merge(var.tags, {
      Name        = "${local.name_prefix}"
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "terraform"
    })
  }

  # ================================================================================
  # TAG SPECIFICATIONS FOR VOLUMES - DISK TAGGING
  # ================================================================================
  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name        = "${local.name_prefix}-root"
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "terraform"
    })
  }

  # ================================================================================
  # LIFECYCLE RULES - HOW TERRAFORM HANDLES UPDATES
  # ================================================================================
  # WHAT: "lifecycle" controls Terraform's resource creation/destruction order
  # WHY: Without this, updates would cause downtime
  # HOW IT WORKS:
  #   1. Terraform creates NEW launch template
  #   2. ASG switches to new template
  #   3. Terraform deletes OLD launch template
  # BENEFIT: Zero-downtime deployments (blue/green pattern)
  lifecycle {
    # WHAT: "create_before_destroy = true" means create new before deleting old
    # WHY: ASG references the launch template - can't delete while in use
    # IF FALSE: Terraform would delete template first, breaking the ASG
    # DOWNSIDE: Requires unique naming (hence "name_prefix" not "name")
    create_before_destroy = true
  }

}

# ================================================================================
# AUTO SCALING GROUP - THE ORCHESTRATOR FOR SELF-HEALING EC2 INSTANCES
# ================================================================================
# WHAT: ASG automatically maintains a desired number of healthy instances
# WHY: Manual instance management doesn't scale and isn't resilient
# HOW IT WORKS:
#   1. You define min/max/desired instance counts
#   2. ASG monitors instance health
#   3. If instance dies, ASG launches replacement
#   4. If traffic increases, ASG can scale out (add instances)
#   5. If traffic decreases, ASG can scale in (remove instances)
# BENEFIT: High availability without manual intervention
# COST: You only pay for the instances, not the ASG service itself (free)
resource "aws_autoscaling_group" "this" {
  # ================================================================================
  # BASIC CONFIGURATION - NAME AND CAPACITY
  # ================================================================================
  name = "${local.name_prefix}-asg"

  # WHAT: Maximum number of instances ASG can create
  max_size = var.max_size

  # WHAT: Minimum number of instances ASG will maintain
  min_size = var.min_size

  # WHAT: The target number of instances ASG tries to maintain
  desired_capacity = var.desired_capacity

  # ================================================================================
  # NETWORK CONFIGURATION - WHERE TO LAUNCH INSTANCES
  # ================================================================================
  # WHAT: List of subnet IDs where ASG can launch instances
  # EXAMPLE: ["subnet-abc123", "subnet-def456"] launches in 2 AZs
  # IF SINGLE SUBNET: All instances in one AZ (single point of failure)
  # BEST PRACTICE: Always use multiple AZs in production
  vpc_zone_identifier = var.subnet_ids

  # ================================================================================
  # HEALTH CHECK CONFIGURATION - WHEN TO REPLACE INSTANCES
  # ================================================================================
  # WHAT: "grace period" is how long ASG waits after launch before health checks start
  # WHY: Instances need time to boot, install software, start app (user_data script)
  # VALUE: 120 seconds = 2 minutes
  health_check_grace_period = var.health_check_grace_period_seconds

  # WHAT: Type of health check ASG uses to determine instance health
  # WHY: Different health check types catch different failure modes
  # OPTIONS:
  #   - "EC2": AWS checks if instance is running (very basic)
  #   - "ELB": Load balancer checks if app responds to HTTP health checks (better)
  # CONDITIONAL LOGIC: If attached to ALB (target_group_arns not empty), use "ELB"
  # HOW IT WORKS:
  #   - EC2: Checks hypervisor status (is VM running?)
  #   - ELB: Sends HTTP GET to /health endpoint, expects 200 OK
  # BENEFIT: ELB catches app crashes that EC2 misses (instance running but app dead)
  # IF "EC2": Broken app keeps getting traffic (ALB sends requests to dead app)
  # IF "ELB": ASG replaces instances that fail health checks
  # TERNARY SYNTAX: condition ? value_if_true : value_if_false
  health_check_type = var.health_check_type_override != "" ? var.health_check_type_override : (length(var.target_group_arns) > 0 ? "ELB" : "EC2")

  # ================================================================================
  # LAUNCH TEMPLATE CONFIGURATION - WHAT TO LAUNCH
  # ================================================================================
  # WHAT: References the launch template created above
  # WHY: ASG needs to know "when I create an instance, what configuration should I use?"
  launch_template {
    # WHAT: The unique ID of the launch template
    # REFERENCE: "aws_launch_template.this.id" points to the resource defined above
    # TERRAFORM DEPENDENCY: This creates an implicit dependency (template must exist first)
    id = aws_launch_template.this.id

    # WHAT: Which version of the launch template to use
    # WHY: Launch templates are versioned (v1, v2, v3...)
    # NOTE:
    # We pin to the launch template's latest_version so Terraform detects changes
    # and can trigger an instance refresh via the instance_refresh block.
    # Using "$Latest" here prevents Terraform from seeing a diff when the launch
    # template changes, which can leave instances stuck on old user_data.
    version = tostring(aws_launch_template.this.latest_version)
  }

  # ================================================================================
  # LOAD BALANCER INTEGRATION - REGISTERING WITH ALB TARGET GROUPS
  # ================================================================================
  # WHAT: List of ALB target group ARNs that instances should register with
  # WHY: ALB needs to know "which instances can handle requests?"
  # HOW IT WORKS:
  #   1. ASG launches instance
  #   2. ASG automatically registers instance with target group
  #   3. ALB starts health checking instance
  #   4. When healthy, ALB sends traffic to instance
  #   5. When instance terminates, ASG deregisters it (ALB stops sending traffic)
  # IF EMPTY: Instances launch but ALB doesn't know about them (no traffic)
  # DEREGISTRATION: ASG waits for connection draining before terminating instance
  target_group_arns = var.target_group_arns

  # ================================================================================
  # TERMINATION POLICIES - WHICH INSTANCE TO KILL DURING SCALE-IN
  # ================================================================================
  # WHAT: Priority-ordered list of rules for choosing which instance to terminate
  # WHY: During scale-in (desired capacity decreases), ASG must pick a victim
  # ORDER MATTERS: ASG tries first policy, if tied, tries second policy, etc.
  # POLICY 1: "OldestLaunchTemplate"
  #   - WHAT: Terminate instances using older launch template versions first
  #   - WHY: Promotes rolling updates (gradually replace old with new)
  #   - USE CASE: After updating launch template, scale-in removes old instances
  # POLICY 2: "OldestInstance"
  #   - WHAT: Terminate the oldest instance (by launch time)
  #   - WHY: Ensures instances don't run indefinitely (avoids state drift)
  #   - BENEFIT: Regular rotation prevents "pet instances" (manually modified instances)
  # OTHER POLICIES NOT USED:
  #   - "NewestInstance": Kill newest (rarely useful)
  #   - "ClosestToNextInstanceHour": Minimize cost (kill instance about to hit hour boundary)
  #   - "Default": AWS's default logic (OldestLaunchConfiguration)
  # IF REMOVED: ASG uses "Default" policy (less predictable)
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  # ================================================================================
  # INSTANCE REFRESH - AUTOMATED ROLLING UPDATES
  # ================================================================================
  # WHAT: "dynamic" block conditionally creates a block based on a condition
  # WHY: Instance refresh is optional (controlled by var.enable_instance_refresh)
  # SYNTAX: for_each iterates over a list - if list is empty, block is skipped
  # CONDITION: var.enable_instance_refresh ? [1] : []
  #   - IF TRUE: for_each = [1] → block runs once
  #   - IF FALSE: for_each = [] → block skipped entirely
  # TERRAFORM TRICK: [1] is a dummy list - the value doesn't matter, just the count
  dynamic "instance_refresh" {
    for_each = var.enable_instance_refresh ? [1] : []

    # WHAT: Instance Refresh is AWS ASG's built-in rolling update mechanism
    # WHY: When you update launch template, old instances don't auto-update
    # HOW IT WORKS:
    #   1. You update launch template (new AMI, new user_data, etc.)
    #   2. ASG triggers instance refresh
    #   3. ASG gradually replaces old instances with new ones
    #   4. Maintains min_healthy_percentage during replacement
    # ALTERNATIVE: Manual rolling update (slowly decrease desired, increase desired)
    # BENEFIT: Automated, safe, respects availability requirements
    content {
      # WHAT: "Rolling" strategy replaces instances gradually
      # WHY: Avoids downtime (some instances always available)
      # OTHER STRATEGIES: None (only Rolling exists currently)
      # HOW IT WORKS:
      #   1. ASG launches new instance
      #   2. Waits for health check
      #   3. Terminates old instance
      #   4. Repeats until all instances replaced
      strategy = "Rolling"

      # ================================================================================
      # INSTANCE REFRESH PREFERENCES - FINE-TUNING THE ROLLING UPDATE
      # ================================================================================
      preferences {
        # WHAT: Percentage of capacity that must remain healthy during refresh
        # WHY: Ensures availability during updates
        # EXAMPLE: min_healthy_percentage = 50, desired = 4
        #   - ASG maintains at least 2 healthy instances (50% of 4)
        #   - Can replace up to 2 instances at a time
        min_healthy_percentage = var.instance_refresh_min_healthy_percentage

        # WHAT: How long to wait after instance becomes healthy before replacing next
        # WHY: Gives app time to warm up caches, establish connections, etc.
        # VALUE: In seconds (e.g., 300 = 5 minutes)
        instance_warmup = var.instance_warmup_seconds
      }
    }
  }

  # ================================================================================
  # TAGGING - PROPAGATING TAGS TO INSTANCES
  # ================================================================================
  # WHAT: Tags applied to the ASG and optionally to instances it launches
  # WHY: ASG itself needs tags (for tracking), and instances need tags (for identification)
  # SYNTAX DIFFERENCE: ASG uses "tag" blocks (not "tags" map like most resources)
  # REASON: ASG needs "propagate_at_launch" flag for each tag
  tag {
    # WHAT: "key" is the tag name (like a dictionary key)
    key   = "Name"
    value = local.name_prefix

    # WHAT: "propagate_at_launch = true" means "copy this tag to launched instances"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Service"
    value               = var.service_name
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }

  # ================================================================================
  # LIFECYCLE RULES - UPDATE STRATEGY FOR ASG
  # ================================================================================
  # WHAT: Controls how Terraform handles ASG updates
  # WHY: Some ASG changes require replacement (can't update in-place)
  # EXAMPLES OF REPLACEMENT-REQUIRED CHANGES:
  #   - Changing launch template
  #   - Changing VPC zone identifier (subnets)
  #   - Changing name
  lifecycle {
    # WHAT: "create_before_destroy = true" means create new ASG before deleting old
    # WHY: Prevents downtime during ASG replacement
    # HOW IT WORKS:
    #   1. Terraform creates new ASG with new name (name includes random suffix)
    #   2. New ASG launches instances
    #   3. ALB registers new instances
    #   4. Terraform deletes old ASG (old instances terminate)
    create_before_destroy = true
  }

}
