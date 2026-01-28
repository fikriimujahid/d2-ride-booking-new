# ================================================================================
# EC2 CLOUDWATCH ALARMS - SYSTEM-LEVEL MONITORING
# ================================================================================
#
# WHAT ARE WE MONITORING?
# ------------------------
# 1. CPU Utilization - Is the instance overloaded?
# 2. Status Checks - Is the instance healthy?
#
# WHY THESE TWO METRICS?
# ----------------------
# These are the MINIMUM viable alarms for any EC2 instance:
# 
# - CPU tells you about LOAD
#   - Sudden spike? Maybe an attack or runaway process
#   - Sustained high CPU? Maybe you need a bigger instance
#   - In DEV, 80% CPU is concerning but not critical
#
# - Status checks tell you about HARDWARE/NETWORK failures
#   - System status check = AWS infrastructure problem
#   - Instance status check = Guest OS problem
#   - If these fail, your app is DOWN (full stop)
#
# WHAT WE'RE NOT MONITORING (YET):
# ---------------------------------
# - Memory utilization (requires CloudWatch Agent with custom metrics)
# - Disk utilization (requires CloudWatch Agent)
# - Network throughput (usually not a problem in DEV)
# - Application-level metrics (request count, error rate, latency)
#
# WHY NOT MORE METRICS IN DEV?
# -----------------------------
# 1. Cost - Custom metrics cost $0.30/metric/month
# 2. Noise - More alarms = more false positives in DEV
# 3. Actionability - What would you DO with the extra data in DEV?
# 4. Time - Setting up custom metrics takes effort
#
# PROD DIFFERENCES:
# -----------------
# - Lower CPU threshold (e.g., 70% for auto-scaling trigger)
# - Memory and disk monitoring (via CloudWatch Agent)
# - Application-level metrics (via APM tools)
# - Auto-remediation (e.g., auto-reboot on status check failure)
#
# ================================================================================

# --------------------------------------------------------------------------------
# EC2 CPU UTILIZATION ALARM
# --------------------------------------------------------------------------------
# Triggers when CPU usage exceeds 80% for 5 consecutive minutes
#
# THRESHOLD CHOICE: 80%
# ---------------------
# - Below 80%: Normal operation (including spikes)
# - 80-90%: Concerning but manageable
# - Above 90%: Likely impacting user experience
#
# EVALUATION PERIODS: 5 minutes (5 data points, 1-minute periods)
# ----------------------------------------------------------------
# - Ignores brief spikes (e.g., during deployment)
# - Catches sustained load issues
# - Gives you time to investigate before users complain
#
# WHY NOT LOWER IN DEV?
# ---------------------
# - DEV workloads are spiky (load testing, batch jobs)
# - t3.micro can burst to 100% CPU temporarily (T3 burst credits)
# - False alarms are worse than no alarms
#
# WHAT TO DO WHEN THIS ALARMS:
# -----------------------------
# 1. SSH into instance via SSM: aws ssm start-session --target <instance-id>
# 2. Check processes: top or htop
# 3. Check PM2 status: pm2 status && pm2 logs
# 4. Check application logs in CloudWatch
# 5. Consider scaling up instance type if sustained
#
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  count = var.enable_alarms && var.ec2_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60 # 1 minute
  statistic           = "Average"
  threshold           = 80 # 80%
  treat_missing_data  = "notBreaching"

  alarm_description = "EC2 instance ${var.ec2_instance_name} CPU utilization is above 80% for 5 minutes. This may indicate high load or a runaway process."
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  dimensions = {
    InstanceId = var.ec2_instance_id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-ec2-cpu-high"
    Environment = var.environment
    ManagedBy   = "terraform"
    AlarmType   = "ec2-cpu"
  })
}

# --------------------------------------------------------------------------------
# EC2 STATUS CHECK FAILED ALARM
# --------------------------------------------------------------------------------
# Triggers IMMEDIATELY if either system or instance status check fails
#
# WHAT ARE STATUS CHECKS?
# ------------------------
# AWS performs two types of automated checks every minute:
#
# 1. SYSTEM STATUS CHECK (AWS infrastructure)
#    - Loss of network connectivity
#    - Loss of system power
#    - Software issues on the physical host
#    - Hardware issues on the physical host
#    → You can't fix this, but AWS can (or you can stop/start to migrate)
#
# 2. INSTANCE STATUS CHECK (Guest OS)
#    - Failed system status checks
#    - Incorrect networking or startup configuration
#    - Exhausted memory
#    - Corrupted file system
#    - Incompatible kernel
#    → You might be able to fix this (reboot, or investigate via SSM)
#
# THRESHOLD: > 0 (any failure)
# ----------------------------
# - Status checks are binary: 0 = healthy, 1 = failed
# - Even a single failure means your app is likely down
# - No need to wait for multiple failures (unlike CPU)
#
# EVALUATION PERIODS: 2 minutes (2 data points, 1-minute periods)
# ----------------------------------------------------------------
# - Immediate enough to catch real outages
# - Brief enough to avoid transient blips during reboots
#
# WHAT TO DO WHEN THIS ALARMS:
# -----------------------------
# 1. Check AWS Console EC2 dashboard - status checks tab
# 2. If SYSTEM status failed:
#    - AWS infrastructure issue (wait or stop/start instance to migrate)
# 3. If INSTANCE status failed:
#    - Check system logs in EC2 console
#    - Try connecting via SSM (may not work if network is down)
#    - Check CloudWatch logs for crash indicators
#    - Consider rebooting instance
#
resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  count = var.enable_alarms && var.ec2_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-ec2-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60 # 1 minute
  statistic           = "Maximum"
  threshold           = 0 # Any failure
  treat_missing_data  = "notBreaching"

  alarm_description = "EC2 instance ${var.ec2_instance_name} has failed system or instance status checks. This indicates a hardware, network, or OS-level problem."
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  dimensions = {
    InstanceId = var.ec2_instance_id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-ec2-status-check-failed"
    Environment = var.environment
    ManagedBy   = "terraform"
    AlarmType   = "ec2-status"
  })
}

# ================================================================================
# WHY NO APPLICATION-LEVEL ALARMS?
# ================================================================================
#
# You might be wondering: "Why aren't we monitoring request rate, error rate,
# or latency?" Great question. Here's why:
#
# 1. APPLICATION METRICS REQUIRE MORE WORK
#    - Need to instrument your code (add metrics)
#    - Or parse logs with metric filters (brittle)
#    - Or integrate APM tools (DataDog, New Relic) (expensive)
#
# 2. DEV WORKLOADS ARE UNPREDICTABLE
#    - No baseline traffic patterns
#    - Testing generates fake errors
#    - Hard to set meaningful thresholds
#
# 3. HEALTH ENDPOINTS ARE BETTER IN DEV
#    - /health returns 200 = app is working
#    - /health returns 500 = app is broken
#    - Simpler than counting metrics
#
# 4. YOU CAN DEBUG WITH LOGS
#    - When something breaks, you check CloudWatch Logs
#    - You don't need a metric to tell you "error rate = 100%"
#    - You need the actual error message (which is in the logs)
#
# PROD APPROACH:
# --------------
# In PROD, you'd add:
# - ALB target health alarms
# - Custom CloudWatch metric filters (e.g., count ERROR in logs)
# - APM integration (DataDog, New Relic, AWS X-Ray)
# - SLO-based alerting (99.9% uptime, p99 latency < 200ms)
#
# But for DEV? EC2-level alarms are enough.
#
# ================================================================================
