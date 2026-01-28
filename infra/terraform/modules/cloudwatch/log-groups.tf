# ================================================================================
# CLOUDWATCH LOG GROUPS - CENTRALIZED APPLICATION LOGGING
# ================================================================================
# 
# WHY LOGS MATTER MORE THAN DASHBOARDS IN DEV:
# --------------------------------------------
# 1. Engineers debug with LOGS, not graphs
#    - "Why did this request fail?" → Check logs
#    - "What was the exact error?" → Check logs
#    - Metrics tell you WHEN something broke, logs tell you WHY
#
# 2. Dashboards are expensive to maintain
#    - Building useful dashboards takes time
#    - DEV workloads are unpredictable (spiky, irregular)
#    - Dashboards optimize for patterns, DEV has none
#
# 3. Log-first debugging is faster in DEV
#    - SSM into instance → `pm2 logs` (local)
#    - OR CloudWatch Logs Insights (centralized)
#    - No need to context-switch to a dashboard
#
# 4. Logs survive instance terminations
#    - EC2 instance gets replaced? Logs remain in CloudWatch
#    - PM2 process crashes? Stdout/stderr captured
#
# PROD DIFFERENCE:
# ----------------
# - PROD would add structured logging (JSON format)
# - PROD would use CloudWatch Logs Insights queries for KPIs
# - PROD might add metric filters (e.g., count 500 errors)
# - PROD might use OpenSearch or third-party tools
#
# DEV KEEPS IT SIMPLE:
# --------------------
# - Plain text logs
# - Short retention (7-14 days)
# - No metric filters
# - No cross-account aggregation
#
# ================================================================================

# --------------------------------------------------------------------------------
# BACKEND API LOG GROUP
# --------------------------------------------------------------------------------
# Captures all stdout/stderr from the NestJS backend API
# 
# LOG FLOW:
# ---------
# 1. PM2 runs backend-api process
# 2. CloudWatch Agent (or SSM) forwards logs to CloudWatch
# 3. Logs appear in /dev/backend-api
# 4. Retention: 7 days (configurable)
#
# WHAT YOU'LL SEE:
# ----------------
# - HTTP request logs (access logs)
# - Application errors (stack traces)
# - Database query logs (if enabled)
# - PM2 process lifecycle events
#
resource "aws_cloudwatch_log_group" "backend_api" {
  name              = "/${var.environment}/${var.project_name}/backend-api"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-backend-api-logs"
    Service     = "backend-api"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# --------------------------------------------------------------------------------
# WEB DRIVER LOG GROUP
# --------------------------------------------------------------------------------
# Captures all stdout/stderr from the Next.js web-driver SSR app
#
# LOG FLOW:
# ---------
# 1. PM2 runs web-driver process (Next.js server)
# 2. CloudWatch Agent forwards logs to CloudWatch
# 3. Logs appear in /dev/web-driver
# 4. Retention: 7 days (configurable)
#
# WHAT YOU'LL SEE:
# ----------------
# - Next.js SSR rendering logs
# - API route handler logs
# - Client-side errors (if logged server-side)
# - PM2 process lifecycle events
#
resource "aws_cloudwatch_log_group" "web_driver" {
  name              = "/${var.environment}/${var.project_name}/web-driver"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-web-driver-logs"
    Service     = "web-driver"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ================================================================================
# LOG RETENTION PHILOSOPHY (DEV vs PROD)
# ================================================================================
#
# DEV: 7-14 DAYS MAXIMUM
# ----------------------
# WHY SHORT RETENTION IN DEV?
# 1. Cost control
#    - CloudWatch charges $0.50/GB ingested + $0.03/GB stored
#    - DEV logs are noisy (debug-level logging)
#    - Unlimited retention = unlimited cost growth
#
# 2. Debugging is real-time
#    - Engineers debug issues as they happen
#    - Week-old DEV logs are rarely useful
#    - If a bug is that old, it's probably in PROD too
#
# 3. Log quality is lower in DEV
#    - Lots of test requests
#    - Incomplete features generating errors
#    - No need to keep this noise forever
#
# PROD: 30-90 DAYS OR MORE
# ------------------------
# - Compliance requirements
# - Incident investigation (post-mortem analysis)
# - Audit trails
# - Security forensics
#
# COST COMPARISON:
# ----------------
# - DEV (7 days, 1GB/day):  ~$0.20/month
# - PROD (90 days, 10GB/day): ~$72/month
#
# ================================================================================
