# DEV Environment - Infrastructure Management Guide

## Overview

This directory contains Terraform configuration for the **development environment** of the D2 Ride Booking platform. This guide covers how to manage, verify, and cost-optimize your DEV infrastructure.

**Quick Links:**
- [Connect to EC2](#1-connect-to-ec2-via-aws-session-manager)
- [Verify Installation](#2-verify-user_data-installation)
- [Connect to RDS via Bastion](#3-connect-to-rds-from-local-machine-via-bastion)
- [Test Database Connectivity](#4-check-rds-connectivity-from-ec2)
- [Check Backend API Status](#5-check-backend-api-status-and-logs)
- [Cost Management](#6-cost-management-enabledisable-resources)
- [Management Scripts](#7-dev-environment-management-scripts)

---

## 📋 Prerequisites

Before using this guide, ensure you have:

1. **AWS CLI** installed and configured
   ```powershell
   aws --version
   aws configure list
   ```

2. **Session Manager Plugin** installed
   ```powershell
   # Download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   session-manager-plugin --version
   ```

3. **Terraform** installed
   ```powershell
   terraform version
   ```

4. **Infrastructure deployed**
   ```powershell
   cd infra\terraform\envs\dev
   terraform apply
   ```

---

## 1. Connect to EC2 via AWS Session Manager

### 1.1 Find Your EC2 Instance ID

**Option A: Using AWS CLI**
```powershell
aws ec2 describe-instances `
    --region ap-southeast-1 `
    --filters "Name=tag:Environment,Values=dev" "Name=tag:Project,Values=d2-ride-booking" `
    --query "Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key=='Name'].Value|[0]]" `
    --output table
```

**Option B: Using Management Script**
```powershell
# Check if script exists, otherwise use AWS CLI
Get-ChildItem .\infra\scripts\*status*.ps1
```

### 1.2 Connect via SSM Session Manager

Replace `i-XXXXXXXXXXXXX` with your actual instance ID:

```powershell
aws ssm start-session --target i-XXXXXXXXXXXXX
```

**Example:**
```powershell
aws ssm start-session --target i-080c218b1eb3925ee
```

---

## 2. Verify user_data Installation

Once connected to the EC2 instance via SSM, verify that the user_data script executed successfully.

### 2.1 Check Cloud-Init Logs

```bash
# View full cloud-init output
sudo cat /var/log/cloud-init-output.log

# Check for errors
sudo grep -i error /var/log/cloud-init-output.log
```

### 2.2 Verify Node.js Installation

```bash
# Check Node.js version
node --version
# Expected: v20.x.x

# Check npm version
npm --version
# Expected: v10.x.x
```

### 2.3 Verify MySQL Client Installation

```bash
# Check mysql client
mysql --version
# Expected: mysql  Ver 8.0.x for Linux

# Verify mysql is in PATH
which mysql
# Expected: /usr/bin/mysql
```

### 2.4 Verify AWS CLI Installation

```bash
# Check AWS CLI version
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x Linux/x86_64

# Verify instance IAM role
aws sts get-caller-identity
```

### 2.5 Check System Services

```bash
# Verify SSM agent is running
sudo systemctl status amazon-ssm-agent

# Check system logs
sudo journalctl -xe
```

### 2.6 Review user_data Script

To see what the user_data script does, check the EC2 module:

```powershell
# From your local machine
cat infra\terraform\modules\ec2\main.tf
```

Look for the `user_data` block to understand what's installed during instance launch.

---

## 3. Connect to RDS from Local Machine via Bastion

### 3.1 Overview

The **recommended approach** for accessing RDS from your local machine is through the bastion host using **SSM port forwarding**. This method:
- ✅ **No SSH keys required** - Uses AWS IAM authentication
- ✅ **No inbound ports** - Bastion doesn't need SSH port 22 open
- ✅ **Secure** - All traffic encrypted via AWS Systems Manager
- ✅ **Auditable** - All sessions logged in CloudWatch
- ✅ **Local tools** - Use your favorite MySQL client (MySQL Workbench, DBeaver, etc.)

### 3.2 Prerequisites

Ensure you have:

1. **Session Manager Plugin** installed:
   ```powershell
   # Download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   session-manager-plugin --version
   ```

2. **MySQL Client** installed locally:
   ```powershell
   # Windows (via Chocolatey)
   choco install mysql-cli
   
   # Or download MySQL installer from mysql.com
   mysql --version
   ```

3. **Bastion enabled** in [terraform.tfvars](terraform.tfvars):
   ```hcl
   enable_bastion = true
   enable_rds = true
   ```

4. **Infrastructure deployed**:
   ```powershell
   cd infra\terraform\envs\dev
   terraform apply
   ```

### 3.3 Get Bastion and RDS Details

**Get Bastion Instance ID:**
```powershell
# Find bastion instance
aws ec2 describe-instances `
    --region ap-southeast-1 `
    --filters "Name=tag:Service,Values=bastion" "Name=tag:Environment,Values=dev" "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0]]" `
    --output table

# Or use Terraform output
cd infra\terraform\envs\dev
terraform output
```

**Get RDS Endpoint:**
```powershell
# Get RDS hostname
aws rds describe-db-instances `
    --region ap-southeast-1 `
    --query "DBInstances[?starts_with(DBInstanceIdentifier,'d2-ride-booking-dev')].Endpoint.Address" `
    --output text

# Or use Terraform output
cd infra\terraform\envs\dev
terraform output -json | Select-String -Pattern "rds"
```

### 3.4 Method 1: Direct Port Forwarding to RDS

**Start SSM Port Forwarding Session:**
```powershell
# Replace with your actual values
$BASTION_INSTANCE_ID = "i-0123456789abcdef0"
$RDS_ENDPOINT = "d2-ride-booking-dev-rds-mysql.xxxxx.ap-southeast-1.rds.amazonaws.com"

# Forward local port 3306 to RDS via bastion
aws ssm start-session `
    --target $BASTION_INSTANCE_ID `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters host=$RDS_ENDPOINT,portNumber=3306,localPortNumber=3306
```

**What this does:**
- Opens a tunnel: `localhost:3306` → `bastion` → `RDS:3306`
- Keeps the session open (leave this terminal running)
- All MySQL traffic flows through this encrypted tunnel

**In a NEW terminal, connect to MySQL:**
```powershell
# Connect using master credentials (for initial setup)
mysql -h 127.0.0.1 -P 3306 -u admin -p
# Enter password when prompted (retrieve from Secrets Manager)

# Or connect using IAM authentication
$TOKEN = aws rds generate-db-auth-token `
    --hostname $RDS_ENDPOINT `
    --port 3306 `
    --region ap-southeast-1 `
    --username app_user

# Note: Connect to 127.0.0.1 (tunnel endpoint), but token is for RDS_ENDPOINT
mysql -h 127.0.0.1 -P 3306 -u app_user -p"$TOKEN" -D ridebooking
```

### 3.5 Method 2: Using MySQL Workbench or DBeaver

**Step 1: Start Port Forwarding** (same as Method 1)
```powershell
aws ssm start-session `
    --target $BASTION_INSTANCE_ID `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters host=$RDS_ENDPOINT,portNumber=3306,localPortNumber=3306
```

**Step 2: Configure MySQL Workbench:**
1. Open MySQL Workbench
2. Click "New Connection"
3. Configure:
   - **Connection Name**: `D2 RDS DEV (via Bastion)`
   - **Hostname**: `127.0.0.1`
   - **Port**: `3306`
   - **Username**: `admin` (or `app_user` for IAM auth)
   - **Password**: Click "Store in Keychain" and enter master password
4. Click "Test Connection"
5. Click "OK" to save

**Step 3: Connect**
- Double-click the connection
- Start querying!

### 3.6 Get Master Password from Secrets Manager

```powershell
# Get secret ARN
$SECRET_ARN = aws secretsmanager list-secrets `
    --region ap-southeast-1 `
    --query "SecretList[?contains(Name,'rds-master')].ARN" `
    --output text

# Get password
aws secretsmanager get-secret-value `
    --region ap-southeast-1 `
    --secret-id $SECRET_ARN `
    --query SecretString `
    --output text
```

### 3.7 Useful SQL Commands

Once connected:

```sql
-- Check connection
SELECT VERSION(), DATABASE(), USER();

-- List all databases
SHOW DATABASES;

-- Use your database
USE ridebooking;

-- Show tables
SHOW TABLES;

-- Check profiles table
DESCRIBE profiles;
SELECT * FROM profiles LIMIT 10;

-- Create IAM-authenticated user (run as admin)
CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT SELECT, INSERT, UPDATE, DELETE ON ridebooking.* TO 'app_user'@'%';
FLUSH PRIVILEGES;

-- Verify IAM user exists
SELECT User, Host, plugin FROM mysql.user WHERE User = 'app_user';
```
---

## 4. Check RDS Connectivity from EC2

### 4.1 Get RDS Endpoint

**From Local Machine:**
```powershell
# Get RDS endpoint
aws rds describe-db-instances `
    --region ap-southeast-1 `
    --query "DBInstances[?starts_with(DBInstanceIdentifier,'d2-ride-booking-dev')].Endpoint.Address" `
    --output text

# Or use the status script
.\infra\scripts\dev-status.ps1
```

**From EC2 Instance (via SSM):**
```bash
# Get RDS endpoint using AWS CLI
aws rds describe-db-instances \
    --region ap-southeast-1 \
    --query "DBInstances[?starts_with(DBInstanceIdentifier,'d2-ride-booking-dev')].Endpoint.Address" \
    --output text
```

### 3.2 Test Network Connectivity

```bash
# Test DNS resolution and port connectivity
RDS_ENDPOINT="d2-ride-booking-dev-XXXXXX.xxxxx.ap-southeast-1.rds.amazonaws.com"

# Check DNS resolution
nslookup $RDS_ENDPOINT

# Test TCP connection to MySQL port
nc -zv $RDS_ENDPOINT 3306

# Alternative: Use telnet
telnet $RDS_ENDPOINT 3306
```

### 3.3 Test MySQL Connection (IAM Authentication)

**Method 1: Using Generated IAM Token**
```bash
# Set variables
export AWS_REGION="ap-southeast-1"
export RDS_ENDPOINT="d2-ride-booking-dev-rds-mysql.*.ap-southeast-1.rds.amazonaws.com"
export DB_USER="app_user"
export DB_NAME="ridebooking"

# Generate IAM authentication token
TOKEN=$(aws rds generate-db-auth-token \
    --hostname $RDS_ENDPOINT \
    --port 3306 \
    --region $AWS_REGION \
    --username $DB_USER)

# Connect using IAM token as password (requires SSL/TLS)
# Note: Using --ssl (compatible with MariaDB/older MySQL clients on AL2023)
mysql -h $RDS_ENDPOINT \
      -P 3306 \
      -u $DB_USER \
      -p"$TOKEN" \
      --ssl \
      -D $DB_NAME
```

**Method 2: Using Master Credentials (Admin Only)**
```bash
# Get master password from Secrets Manager
SECRET_ARN=$(aws secretsmanager list-secrets \
    --region ap-southeast-1 \
    --query "SecretList[?contains(Name,'rds-master')].ARN" \
    --output text)

MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
    --region ap-southeast-1 \
    --secret-id $SECRET_ARN \
    --query SecretString \
    --output text | jq -r .password)

# Connect using master credentials
mysql -h $RDS_ENDPOINT \
      -u admin \
      -p"$MASTER_PASSWORD" \
      -D ridebooking
```

### 3.4 Execute Test Queries

Once connected to MySQL:

```sql
-- Check database version
SELECT VERSION();

-- List databases
SHOW DATABASES;

-- Use your database
USE ridebooking;

-- Show tables
SHOW TABLES;

-- Check if profiles table exists (from migration)
DESCRIBE profiles;

-- Test query
SELECT COUNT(*) FROM profiles;

-- Check current user and authentication method
SELECT USER(), CURRENT_USER();

-- Verify IAM authentication is enabled
SHOW VARIABLES LIKE 'authentication_plugin';
```

### 4.5 Test IAM Database User Setup

```sql
-- Check if app_user exists
SELECT User, Host, plugin FROM mysql.user WHERE User = 'app_user';

-- Expected result: plugin should be 'AWSAuthenticationPlugin'

-- Grant additional permissions if needed (as admin)
GRANT SELECT, INSERT, UPDATE, DELETE ON ridebooking.* TO 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
FLUSH PRIVILEGES;
```

---

## 5. Check Backend API Status and Logs

### 5.1 Connect to Backend EC2 Instance

```powershell
# From local machine - get backend instance ID
aws ec2 describe-instances `
    --region ap-southeast-1 `
    --filters "Name=tag:Service,Values=backend-api" "Name=tag:Environment,Values=dev" "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0]]" `
    --output table

# Connect via SSM
aws ssm start-session --target i-XXXXXXXXXXXXX
```

### 5.2 Check PM2 Process Status

The backend API runs as a PM2-managed process. Check its status:

```bash
# If the app was deployed via SSM (GitHub Actions), PM2 runs under root.
# Use sudo if `pm2 list` shows nothing.

# List all PM2 processes
pm2 list

# If needed:
sudo pm2 list

# Detailed status for backend-api
pm2 show backend-api

# If needed:
sudo pm2 show backend-api

# Check if process is online
pm2 status
```

**Expected Output:**
```
┌────┬────────────────┬─────────────┬─────────┬─────────┬──────────┬────────┬──────┬───────────┬──────────┐
│ id │ name           │ namespace   │ version │ mode    │ pid      │ uptime │ ↺    │ status    │ cpu      │
├────┼────────────────┼─────────────┼─────────┼─────────┼──────────┼────────┼──────┼───────────┼──────────┤
│ 0  │ backend-api    │ default     │ 1.0.0   │ fork    │ 12345    │ 2h     │ 0    │ online    │ 0%       │
└────┴────────────────┴─────────────┴─────────┴─────────┴──────────┴────────┴──────┴───────────┴──────────┘
```

### 5.3 View Real-Time Logs

**View live logs:**
```bash
# View all logs (streaming)
pm2 logs

# View backend-api logs only
pm2 logs backend-api

# View last 100 lines
pm2 logs backend-api --lines 100

# View error logs only
pm2 logs backend-api --err

# View output logs only
pm2 logs backend-api --out
```

**Exit logs:** Press `Ctrl+C`

### 5.4 View Historical Logs

```bash
# View PM2 log files directly
ls -lh ~/.pm2/logs/

# View error log
cat ~/.pm2/logs/backend-api-error.log

# View output log
cat ~/.pm2/logs/backend-api-out.log

# Tail last 50 lines
tail -n 50 ~/.pm2/logs/backend-api-out.log

# Search for errors
grep -i error ~/.pm2/logs/backend-api-error.log

# Search for specific patterns
grep "Database pool initialized" ~/.pm2/logs/backend-api-out.log
```

### 5.5 Check Application Health

**Test health endpoint from EC2:**
```bash
# Check if backend is responding
curl http://localhost:3000/health

# Expected response:
# {"status":"ok","timestamp":"2026-01-21T..."}

# Test with verbose output
curl -v http://localhost:3000/health

# Check API documentation
curl http://localhost:3000/api/docs
```

**Test from local machine (if ALB is enabled):**
```powershell
# Get ALB DNS name
$ALB_DNS = aws elbv2 describe-load-balancers `
    --region ap-southeast-1 `
    --query "LoadBalancers[?contains(LoadBalancerName,'d2-ride-booking-dev')].DNSName" `
    --output text

# Test health endpoint
curl "http://$ALB_DNS/health"
```

### 5.6 View CloudWatch Logs

**From local machine:**
```powershell
# Get log group name
$LOG_GROUP = "/aws/ec2/dev-d2-ride-booking-backend"

# View recent logs
aws logs tail $LOG_GROUP --region ap-southeast-1 --follow

# View logs from last hour
aws logs tail $LOG_GROUP --region ap-southeast-1 --since 1h

# Filter logs for errors
aws logs filter-log-events `
    --region ap-southeast-1 `
    --log-group-name $LOG_GROUP `
    --filter-pattern "ERROR" `
    --max-items 50

# Search for specific patterns
aws logs filter-log-events `
    --region ap-southeast-1 `
    --log-group-name $LOG_GROUP `
    --filter-pattern "Database pool initialized"
```

### 5.7 Common PM2 Management Commands

```bash
# Restart backend-api
pm2 restart backend-api

# Stop backend-api
pm2 stop backend-api

# Start backend-api
pm2 start backend-api

# Reload backend-api (zero-downtime restart)
pm2 reload backend-api

# Delete process from PM2
pm2 delete backend-api

# Save PM2 process list (survives reboot)
pm2 save

# Monitor CPU/Memory in real-time
pm2 monit

# View detailed process info
pm2 info backend-api

# Flush logs (clear old logs)
pm2 flush
```

### 5.8 Check Backend Configuration

```bash
# View current environment variables
pm2 env 0  # Replace 0 with your process id

# Check .env file (if deployed)
cat /opt/apps/backend-api/current/.env

# Verify Node.js version
node --version

# Check npm version
npm --version

# View ecosystem config
cat /opt/apps/backend-api/current/ecosystem.config.js
```

### 5.9 Troubleshooting Common Issues

**Backend won't start:**
```bash
# Check error logs
pm2 logs backend-api --err --lines 100

# Try starting manually to see errors
cd /opt/apps/backend-api/current
node dist/main.js

# Check if port 3000 is already in use
sudo netstat -tlnp | grep 3000
# Or
sudo lsof -i :3000
```

**Database connection issues:**
```bash
# Test RDS connectivity
nc -zv <RDS_ENDPOINT> 3306

# Check IAM auth token generation
aws rds generate-db-auth-token \
    --hostname <RDS_ENDPOINT> \
    --port 3306 \
    --region ap-southeast-1 \
    --username app_user

# Verify DB environment variables
grep DB_ /opt/apps/backend-api/current/.env
```

**High CPU/Memory usage:**
```bash
# Monitor resources in real-time
pm2 monit

# View detailed metrics
pm2 show backend-api

# Check system resources
htop
# Or
top
```

**View crash/restart history:**
```bash
# View PM2 restart count
pm2 list

# If restart count is high, check error logs
pm2 logs backend-api --err --lines 200
```

---

---

## 6. Cost Management: Enable/Disable Resources

### 6.1 Cost Control via terraform.tfvars

The DEV environment supports cost optimization by enabling/disabling resources:

```hcl
# Cost toggles in terraform.tfvars
enable_ec2_backend       = false  # Backend EC2 instance
enable_rds               = false  # RDS MySQL database
enable_nat_gateway       = false  # NAT Gateway ($32/month)
enable_alb               = false  # Application Load Balancer
enable_ssm_vpc_endpoints = false  # VPC Endpoints for SSM
enable_bastion           = false  # Bastion host for RDS access

# Static sites (not typically used in DEV)
enable_web_admin         = false
enable_web_passenger     = false
enable_web_driver        = false
```

**To enable resources:**
1. Edit `terraform.tfvars` and set toggles to `true`
2. Run `terraform plan` to review changes
3. Run `terraform apply` to create resources

**To disable resources:**
1. Set toggles to `false` in `terraform.tfvars`
2. Run `terraform destroy` to remove resources (or `terraform apply` to update)

### 6.2 Alternative: Stop/Start Instances

For temporary cost savings without destroying infrastructure:

**Stop instances manually:**
```powershell
# Stop backend EC2 instance
aws ec2 stop-instances --region ap-southeast-1 --instance-ids i-XXXXXXXXXXXXX

# Stop RDS database
aws rds stop-db-instance --region ap-southeast-1 --db-instance-identifier d2-ride-booking-dev-rds-mysql
```

**Start instances:**
```powershell
# Start backend EC2 instance
aws ec2 start-instances --region ap-southeast-1 --instance-ids i-XXXXXXXXXXXXX

# Start RDS database (restarts automatically after 7 days)
aws rds start-db-instance --region ap-southeast-1 --db-instance-identifier d2-ride-booking-dev-rds-mysql
```

**Note:** Check `infra/scripts/` for lifecycle management scripts if available.

---

## 7. Cognito User Management

### 7.1 Get Cognito Configuration

```powershell
cd infra\terraform\envs\dev
terraform output
```

Look for outputs containing:
- `cognito_user_pool_id`
- `cognito_app_client_id`
- `cognito_issuer`

### 7.2 Create Admin User

```powershell
# Set variables
$USER_POOL_ID = "ap-southeast-1_XXXXXXXXX"
$USERNAME = "admin@demo.fikri.dev"
$TEMP_PASSWORD = "TempPassword123!"

# Create user
aws cognito-idp admin-create-user `
    --region ap-southeast-1 `
    --user-pool-id $USER_POOL_ID `
    --username $USERNAME `
    --temporary-password $TEMP_PASSWORD `
    --user-attributes Name=email,Value=$USERNAME Name=email_verified,Value=true

# Set permanent password (skip password change requirement)
aws cognito-idp admin-set-user-password `
    --region ap-southeast-1 `
    --user-pool-id $USER_POOL_ID `
    --username $USERNAME `
    --password "Password123!" `
    --permanent
```

### 7.3 Test Authentication

```powershell
$CLIENT_ID = "1ak3tj1bn3neor7hgsjr1ml5h3"

# Authenticate and get tokens
aws cognito-idp initiate-auth `
    --region ap-southeast-1 `
    --auth-flow USER_PASSWORD_AUTH `
    --client-id $CLIENT_ID `
    --auth-parameters USERNAME="admin@demo.fikri.dev",PASSWORD="Password123!"
```

Successful response includes:
- `IdToken` - Use for API authentication
- `AccessToken` - Use for Cognito API calls
- `RefreshToken` - Use to get new tokens

---

## 8. Understanding the Architecture

### 8.1 DEV vs PROD Differences

**DEV Environment (Single EC2):**
- Single EC2 instance running backend-api (port 3000)
- Direct EC2 access via Session Manager
- Optional bastion for RDS access
- Cost-optimized: can be stopped when not in use
- Simple deployment via SSM commands

**PROD Environment (ASG + ALB):**
- Auto Scaling Groups (ASGs) for both backend-api and web-driver
- Application Load Balancer (ALB) with HTTPS
- CloudFront + S3 for static sites (web-admin, web-passenger)
- Rolling deployments with zero downtime
- Always-on with high availability

### 8.2 Backend API Service

The project uses a **single backend API service** (`backend-api`) that handles all API requests:
- Runs on port 3000
- Managed by PM2 (process manager)
- Located in `apps/backend-api/`
- Uses ecosystem.config.js for PM2 configuration

**Note:** There is no separate `backend-api-v2` service in production. The `apps/backend-api-v2/` directory is for development/testing purposes only.

### 8.3 Service Ports

```
Port 3000: backend-api (NestJS REST API)
Port 3001: web-driver (Next.js SSR) [PROD only with ALB]
```

---

**Last Updated:** 2026-02-04
