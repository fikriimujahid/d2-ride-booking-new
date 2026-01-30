# ================================================================================
# ALB TARGET HEALTH ALARMS (PROD-GRADE)
# ================================================================================
# Rationale:
# - PROD must fail fast when targets go unhealthy.
# - This is intentionally stricter than DEV because production impact is higher.
# - Alarm signals: "ALB cannot route traffic to healthy instances".

resource "aws_cloudwatch_metric_alarm" "alb_backend_unhealthy_hosts" {
  # NOTE: The ALB/TG ARN suffixes are not known until apply. Do not use them
  # to decide count, otherwise `terraform plan` fails with "Invalid count argument".
  count = (var.enable_alarms && var.enable_alb_monitoring) ? 1 : 0

  alarm_name        = "${var.environment}-${var.project_name}-alb-backend-unhealthy-hosts"
  alarm_description = "ALB backend target group has unhealthy hosts (PROD signal)."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Average"
  period      = var.alb_alarm_period_seconds

  evaluation_periods  = var.alb_alarm_evaluation_periods
  threshold           = var.alb_unhealthy_host_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.backend_target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-alb-backend-unhealthy"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_cloudwatch_metric_alarm" "alb_driver_unhealthy_hosts" {
  # See note above.
  count = (var.enable_alarms && var.enable_alb_monitoring) ? 1 : 0

  alarm_name        = "${var.environment}-${var.project_name}-alb-driver-unhealthy-hosts"
  alarm_description = "ALB driver target group has unhealthy hosts (PROD signal)."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Average"
  period      = var.alb_alarm_period_seconds

  evaluation_periods  = var.alb_alarm_evaluation_periods
  threshold           = var.alb_unhealthy_host_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.driver_target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-alb-driver-unhealthy"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
