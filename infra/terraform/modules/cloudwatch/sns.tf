# ================================================================================
# SNS TOPIC - ALARM NOTIFICATIONS
# ================================================================================
#
# PURPOSE:
# --------
# CloudWatch alarms need somewhere to send notifications when they trigger.
# This SNS topic acts as a central hub for all DEV environment alarms.
#
# NOTIFICATION FLOW:
# ------------------
# 1. CloudWatch alarm triggers (e.g., EC2 CPU > 80%)
# 2. Alarm publishes message to SNS topic
# 3. SNS forwards message to all subscribers (email, SMS, Lambda, etc.)
# 4. Engineer receives notification and investigates
#
# DEV PHILOSOPHY:
# ---------------
# - ONE topic for all alarms (keep it simple)
# - Email is enough (no PagerDuty, no Slack yet)
# - Optional subscription (don't force spam on engineers)
#
# PROD DIFFERENCES:
# -----------------
# - Multiple topics (critical vs warning)
# - Integration with PagerDuty / Opsgenie
# - Slack webhooks for team visibility
# - Lambda functions for auto-remediation
# - SMS for critical alerts
#
# COST:
# -----
# - SNS is free for first 1,000 email notifications/month
# - After that: $2 per 100,000 notifications
# - DEV will never hit the limit
#
# ================================================================================

# --------------------------------------------------------------------------------
# SNS TOPIC
# --------------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name              = "${var.environment}-${var.project_name}-alarms"
  display_name      = "${upper(var.environment)} ${var.project_name} Alarms"
  kms_master_key_id = aws_kms_key.sns.arn

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-alarms"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cloudwatch-alarms"
  })
}

# --------------------------------------------------------------------------------
# EMAIL SUBSCRIPTION (OPTIONAL)
# --------------------------------------------------------------------------------
# Only creates subscription if alarm_email is provided
#
# IMPORTANT - MANUAL CONFIRMATION REQUIRED:
# ------------------------------------------
# After terraform apply, AWS will send a confirmation email to the address.
# The subscription won't be active until the recipient clicks "Confirm subscription".
#
# WHY THIS IS GOOD IN DEV:
# ------------------------
# - Prevents accidental spam
# - Engineers opt-in to notifications
# - Can unsubscribe later without touching Terraform
#
# ALTERNATIVE APPROACHES:
# -----------------------
# 1. Use a team distribution list instead of personal email
# 2. Skip email entirely and check CloudWatch Alarms in console
# 3. Use AWS Chatbot for Slack integration (requires manual setup)
#
resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ================================================================================
# HOW TO EXTEND THIS IN PROD
# ================================================================================
#
# 1. ADD SLACK INTEGRATION:
#    - Use AWS Chatbot (manual console setup)
#    - Or Lambda function with Slack webhook
#
# 2. ADD PAGERDUTY:
#    resource "aws_sns_topic_subscription" "pagerduty" {
#      topic_arn = aws_sns_topic.alarms.arn
#      protocol  = "https"
#      endpoint  = "https://events.pagerduty.com/integration/..."
#    }
#
# 3. ADD AUTO-REMEDIATION:
#    resource "aws_sns_topic_subscription" "lambda_remediation" {
#      topic_arn = aws_sns_topic.alarms.arn
#      protocol  = "lambda"
#      endpoint  = aws_lambda_function.auto_remediate.arn
#    }
#
# 4. ADD MULTIPLE TOPICS (CRITICAL vs WARNING):
#    resource "aws_sns_topic" "critical_alarms" { ... }
#    resource "aws_sns_topic" "warning_alarms" { ... }
#
# ================================================================================
