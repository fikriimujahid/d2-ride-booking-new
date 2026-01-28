# ================================================================================
# RDS CLOUDWATCH ALARMS - DATABASE MONITORING
# ================================================================================
#
# WHAT ARE WE MONITORING?
# ------------------------
# 1. CPU Utilization - Is the database overloaded?
# 2. Free Storage Space - Is the database running out of disk?
# 3. Database Connections - Is the connection pool exhausted?
#
# WHY THESE THREE METRICS?
# -------------------------
# These are the CRITICAL failure modes for a database:
#
# - HIGH CPU = Slow queries, high load, possible downtime
# - LOW STORAGE = Write failures, database corruption, crash
# - TOO MANY CONNECTIONS = Connection pool exhausted, app can't connect
#
# WHAT WE'RE NOT MONITORING (IN DEV):
# ------------------------------------
# - Read/Write latency (requires baseline, not meaningful in DEV)
# - IOPS utilization (DEV doesn't have IOPS constraints)
# - Replication lag (DEV is single-AZ, no replicas)
# - Query performance (requires Performance Insights = $$$)
# - Deadlocks (requires enhanced monitoring = $$$)
#
# WHY NO ENHANCED MONITORING IN DEV?
# -----------------------------------
# Enhanced Monitoring costs $0.01/instance/hour = $7.20/month
# For a DEV database, that's a 30% cost increase (db.t3.micro = $24/month)
# 
# What you get:
# - OS-level metrics (memory, processes, network)
# - 60+ additional metrics
# - Granularity down to 1 second
#
# What you DON'T need in DEV:
# - OS-level metrics (CloudWatch Logs is enough)
# - 1-second granularity (DEV issues don't need sub-minute precision)
#
# PROD DIFFERENCES:
# -----------------
# - Performance Insights enabled (query-level analysis)
# - Enhanced Monitoring enabled (OS-level metrics)
# - Lower thresholds (e.g., 70% CPU instead of 80%)
# - Replication lag alarms (if using read replicas)
# - Automated backups monitoring
#
# ================================================================================

# --------------------------------------------------------------------------------
# RDS CPU UTILIZATION ALARM
# --------------------------------------------------------------------------------
# Triggers when database CPU exceeds 80% for 5 consecutive minutes
#
# THRESHOLD CHOICE: 80%
# ---------------------
# - Below 80%: Normal operation (including periodic spikes)
# - 80-90%: Concerning (investigate slow queries)
# - Above 90%: Critical (database likely slow for all users)
#
# WHY CPU MATTERS:
# ----------------
# High CPU on RDS usually means:
# 1. Inefficient queries (missing indexes, full table scans)
# 2. Too many concurrent connections
# 3. Insufficient instance size for workload
#
# WHAT TO DO WHEN THIS ALARMS:
# -----------------------------
# 1. Check RDS console performance tab
# 2. Query slow query log (if enabled)
# 3. Check connection count (pm2 logs, app logs)
# 4. Consider:
#    - Adding indexes
#    - Optimizing N+1 queries
#    - Scaling up instance class
#    - Adding read replicas (PROD only)
#
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.enable_alarms && var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60 # 1 minute
  statistic           = "Average"
  threshold           = 80 # 80%
  treat_missing_data  = "notBreaching"

  alarm_description = "RDS instance ${var.rds_instance_name} CPU utilization is above 80% for 5 minutes. This may indicate inefficient queries or insufficient capacity."
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-rds-cpu-high"
    Environment = var.environment
    ManagedBy   = "terraform"
    AlarmType   = "rds-cpu"
  })
}

# --------------------------------------------------------------------------------
# RDS FREE STORAGE SPACE ALARM
# --------------------------------------------------------------------------------
# Triggers when free storage drops below 2GB
#
# THRESHOLD CHOICE: 2GB (2,000,000,000 bytes)
# --------------------------------------------
# - DEV starts with 20GB storage
# - Storage auto-scaling enabled (can grow to 100GB)
# - 2GB = 10% of initial allocation
# - This gives you warning before auto-scaling kicks in
#
# WHY STORAGE MATTERS:
# --------------------
# Low storage on RDS can cause:
# 1. Write failures (app crashes)
# 2. Database corruption (if writes fail mid-transaction)
# 3. Automatic storage scaling (which takes time)
# 4. Increased costs (auto-scaling charges)
#
# COMMON CAUSES IN DEV:
# ---------------------
# 1. Forgot to clean up test data
# 2. Logging too much data to database
# 3. Binary log files accumulating (check retention)
# 4. Temp tables not being cleaned up
#
# WHAT TO DO WHEN THIS ALARMS:
# -----------------------------
# 1. Check database size:
#    SELECT table_schema, 
#           SUM(data_length + index_length) / 1024 / 1024 AS "Size (MB)" 
#    FROM information_schema.tables 
#    GROUP BY table_schema;
# 2. Check binary log usage: SHOW BINARY LOGS;
# 3. Purge old data or scale storage manually
# 4. Consider reducing binary log retention
#
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  count = var.enable_alarms && var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 2000000000 # 2GB in bytes
  treat_missing_data  = "notBreaching"

  alarm_description = "RDS instance ${var.rds_instance_name} free storage is below 2GB. Storage auto-scaling may trigger, or writes may fail."
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-rds-storage-low"
    Environment = var.environment
    ManagedBy   = "terraform"
    AlarmType   = "rds-storage"
  })
}

# --------------------------------------------------------------------------------
# RDS DATABASE CONNECTIONS ALARM
# --------------------------------------------------------------------------------
# Triggers when connection count exceeds 40 (for db.t3.micro)
#
# THRESHOLD CHOICE: 40 connections
# ---------------------------------
# - db.t3.micro max_connections ≈ 60-80 (depends on RAM)
# - Leaving 20-40 connections as buffer
# - DEV should rarely exceed 10 concurrent connections
#
# WHY CONNECTIONS MATTER:
# -----------------------
# Too many connections means:
# 1. Connection pool misconfigured (pool size too large)
# 2. Connections leaking (not being closed properly)
# 3. Sudden traffic spike
# 4. App can't connect = "Too many connections" error
#
# COMMON CAUSES IN DEV:
# ---------------------
# 1. Hot-reloading creates new connections on every code change
# 2. Multiple developers running local copies against same DB
# 3. Connection pool not configured correctly in backend-api
# 4. Long-running queries holding connections open
#
# WHAT TO DO WHEN THIS ALARMS:
# -----------------------------
# 1. Check active connections:
#    SHOW PROCESSLIST;
# 2. Check connection pool config in backend-api (NestJS TypeORM/Prisma)
# 3. Check for connection leaks (missing .close() calls)
# 4. Consider:
#    - Reducing connection pool size
#    - Adding connection timeouts
#    - Fixing connection leaks in code
#
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  count = var.enable_alarms && var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 40 # Adjust based on instance class
  treat_missing_data  = "notBreaching"

  alarm_description = "RDS instance ${var.rds_instance_name} has more than 40 active connections. This may indicate a connection leak or misconfigured connection pool."
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}-rds-connections-high"
    Environment = var.environment
    ManagedBy   = "terraform"
    AlarmType   = "rds-connections"
  })
}

# ================================================================================
# VALIDATION CHECKLIST (FOR ENGINEERS)
# ================================================================================
#
# After deploying, verify:
# 
# ✅ RDS CPU alarm exists in CloudWatch console
# ✅ RDS storage alarm exists
# ✅ RDS connections alarm exists
# ✅ All alarms are in "OK" state (green)
# ✅ Alarms can be disabled by setting enable_alarms = false
# ✅ SNS topic is subscribed to (check email for confirmation)
#
# To test alarms manually:
# ------------------------
# 1. CPU: Run a heavy query in a loop
#    WHILE true DO SELECT SLEEP(0.1); END WHILE;
# 
# 2. Storage: Generate large data
#    CREATE TABLE test AS SELECT * FROM large_table;
#
# 3. Connections: Open many connections from app
#    for (let i = 0; i < 50; i++) { await createConnection(); }
#
# Expected behavior:
# ------------------
# - Alarm transitions from OK → ALARM
# - SNS notification sent to email
# - Alarm description clearly explains the problem
# - Alarm transitions back to OK when condition resolves
#
# ================================================================================
