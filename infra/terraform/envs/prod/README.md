# PROD Environment - Infrastructure Management Guide

## Overview

This directory contains Terraform configuration for the **production environment** of the D2 Ride Booking platform. This guide covers production-grade infrastructure management, including Auto Scaling Groups (ASGs), Application Load Balancers (ALBs), CloudFront distributions, and operational best practices.

**Quick Links:**
- [Architecture Overview](#1-architecture-overview)
- [Connect to Bastion](#2-connect-to-bastion-via-aws-session-manager)
- [Connect to RDS via Bastion](#3-connect-to-rds-from-local-machine-via-bastion)
- [Manage Auto Scaling Groups](#4-auto-scaling-group-asg-management)
- [Rolling Deployments](#5-rolling-deployments)
- [CloudFront & Static Sites](#6-cloudfront--static-sites-management)
- [Application Load Balancer](#7-application-load-balancer-alb)
- [Cognito User Management](#8-cognito-user-management)
- [Monitoring & Logs](#9-monitoring--logs)
- [Production Best Practices](#10-production-best-practices)
- [Non-Negotiable Principles](#11-non-negotiable-principles)

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

4. **Production infrastructure deployed**
   ```powershell
   cd infra\terraform\envs\prod
   terraform apply
   ```

5. **Appropriate AWS IAM permissions** for production access

---

## 1. Architecture Overview

### 1.1 Production Architecture Components

**Compute Layer:**
- ✅ **Auto Scaling Groups (ASGs)** - Automatic scaling for backend-api
- ✅ **Application Load Balancer (ALB)** - HTTPS traffic distribution with host-based routing
- ✅ **Bastion Host** - Secure access to RDS via SSM Session Manager

**Database Layer:**
- ✅ **Amazon RDS MySQL 8.0** - Multi-AZ deployment with automated backups
- ✅ **IAM Database Authentication** - Passwordless authentication for applications
- ✅ **Private subnets** - Database isolated from public internet

**Static Content:**
- ✅ **Amazon CloudFront** - Global CDN for web-admin and web-passenger
- ✅ **Amazon S3** - Private origin buckets for static sites
- ✅ **ACM Certificates** - SSL/TLS for all domains

**Identity & Access:**
- ✅ **Amazon Cognito** - User authentication and authorization
- ✅ **IAM Roles** - Secure access for EC2 instances and GitHub Actions

**Networking:**
- ✅ **VPC** - Isolated network (10.30.0.0/16)
- ✅ **Multi-AZ** - Resources distributed across ap-southeast-1a and ap-southeast-1b
- ✅ **Public Subnets** - ALB, Bastion, NAT Gateway
- ✅ **Private App Subnets** - EC2 instances in ASGs
- ✅ **Private DB Subnets** - RDS database

### 1.2 Service Endpoints

**Production Domains:**
- **Backend API**: `https://api.d2.fikri.dev`
- **Web Driver**: `https://driver.d2.fikri.dev` (future)
- **Web Admin**: `https://admin.d2.fikri.dev`
- **Web Passenger**: `https://passenger.d2.fikri.dev`

**Service Ports:**
```
Port 3000: backend-api (NestJS REST API)
Port 3001: web-driver (Next.js SSR) - future
Port 3306: RDS MySQL (private access only)
```

### 1.3 High Availability

- **ALB**: Distributes traffic across multiple AZs
- **ASG**: Automatically replaces unhealthy instances
- **RDS**: Multi-AZ with automatic failover (if enabled)
- **CloudFront**: Global edge locations for static content

### 1.4 PROD vs DEV Differences

| Feature | DEV | PROD |
|---------|-----|------|
| **Compute** | Single EC2 instance | Auto Scaling Groups (ASGs) |
| **Load Balancer** | Optional | Required (ALB with HTTPS) |
| **Static Sites** | Disabled | CloudFront + S3 |
| **Database** | Can be stopped | Always-on with backups |
| **Deployment** | Direct SSM commands | Rolling deployments via GitHub Actions |
| **Availability** | Single AZ | Multi-AZ |
| **Cost Optimization** | Can be stopped | Always-on, production-grade |
| **Cognito Password** | 8 characters | 12+ characters |

---

## 2. Connect to Bastion via AWS Session Manager

### 2.1 Find Bastion Instance ID

**Option A: Using AWS CLI**
```powershell
aws ec2 describe-instances `
    --region ap-southeast-1 `
    --filters "Name=tag:Service,Values=bastion" "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key=='Name'].Value|[0]]" `
    --output table
```

**Option B: Using Terraform Output**
```powershell
cd infra\terraform\envs\prod
terraform output prod_summary
```

### 2.2 Connect via SSM Session Manager

```powershell
# Replace with your actual bastion instance ID
aws ssm start-session --target i-XXXXXXXXXXXXX
```

**Benefits of SSM over SSH:**
- ✅ No SSH keys required
- ✅ No inbound ports needed (port 22 closed by default)
- ✅ All sessions logged to CloudWatch
- ✅ IAM-based access control
- ✅ Session recordings available

---

## 3. Connect to RDS from Local Machine via Bastion

### 3.1 Prerequisites

Ensure you have:

1. **Session Manager Plugin** installed
2. **MySQL Client** installed locally
3. **Bastion enabled** in terraform.tfvars

### 3.2 Get RDS Endpoint and Bastion Details

**Get Bastion Instance ID:**
```powershell
cd infra\terraform\envs\prod
terraform output prod_summary | Select-String -Pattern "bastion" -Context 5
```

**Get RDS Endpoint:**
```powershell
# From Terraform output
terraform output prod_summary | Select-String -Pattern "rds" -Context 3

# Or use AWS CLI
aws rds describe-db-instances `
    --region ap-southeast-1 `
    --query "DBInstances[?starts_with(DBInstanceIdentifier,'d2-ride-booking-prod')].Endpoint.Address" `
    --output text
```

### 3.3 Start Port Forwarding Session

```powershell
# Set your values
$BASTION_INSTANCE_ID = "i-0123456789abcdef0"
$RDS_ENDPOINT = "d2-ride-booking-prod-rds-mysql.xxxxx.ap-southeast-1.rds.amazonaws.com"

# Forward local port 3306 to RDS via bastion
aws ssm start-session `
    --target $BASTION_INSTANCE_ID `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters host=$RDS_ENDPOINT,portNumber=3306,localPortNumber=3306
```

**Keep this terminal open** - it maintains the tunnel.

### 3.4 Connect to MySQL

**In a NEW terminal:**

```powershell
# Connect using master credentials
mysql -h 127.0.0.1 -P 3306 -u admin -p

# Or connect using IAM authentication
$TOKEN = aws rds generate-db-auth-token `
    --hostname $RDS_ENDPOINT `
    --port 3306 `
    --region ap-southeast-1 `
    --username app_user

mysql -h 127.0.0.1 -P 3306 -u app_user -p"$TOKEN" -D ridebooking
```

### 3.5 Get Master Password from Secrets Manager

```powershell
# List secrets
aws secretsmanager list-secrets `
    --region ap-southeast-1 `
    --query "SecretList[?contains(Name,'prod') && contains(Name,'rds-master')].[Name,ARN]" `
    --output table

# Get password
$SECRET_ARN = aws secretsmanager list-secrets `
    --region ap-southeast-1 `
    --query "SecretList[?contains(Name,'prod') && contains(Name,'rds-master')].ARN" `
    --output text

aws secretsmanager get-secret-value `
    --region ap-southeast-1 `
    --secret-id $SECRET_ARN `
    --query SecretString `
    --output text
```

---

## 4. Auto Scaling Group (ASG) Management

### 4.1 Get ASG Information

```powershell
# Get ASG details
aws autoscaling describe-auto-scaling-groups `
    --region ap-southeast-1 `
    --query "AutoScalingGroups[?contains(AutoScalingGroupName,'prod-backend-api')].[AutoScalingGroupName,MinSize,DesiredCapacity,MaxSize]" `
    --output table

# Get current instances
aws autoscaling describe-auto-scaling-groups `
    --region ap-southeast-1 `
    --query "AutoScalingGroups[?contains(AutoScalingGroupName,'prod-backend-api')].Instances[].[InstanceId,HealthStatus,LifecycleState]" `
    --output table
```

### 4.2 Scale ASG Manually

```powershell
$ASG_NAME = "d2-ride-booking-prod-backend-api-asg"

# Increase capacity
aws autoscaling set-desired-capacity `
    --region ap-southeast-1 `
    --auto-scaling-group-name $ASG_NAME `
    --desired-capacity 3

# Scale down
aws autoscaling set-desired-capacity `
    --region ap-southeast-1 `
    --auto-scaling-group-name $ASG_NAME `
    --desired-capacity 1
```

### 4.3 Connect to ASG Instance

```powershell
# Get running instance ID
$INSTANCE_ID = aws autoscaling describe-auto-scaling-groups `
    --region ap-southeast-1 `
    --query "AutoScalingGroups[?contains(AutoScalingGroupName,'prod-backend-api')].Instances[?HealthStatus=='Healthy'].InstanceId | [0]" `
    --output text

# Connect via SSM
aws ssm start-session --target $INSTANCE_ID
```

---

## 5. Rolling Deployments

### 5.1 Deployment Overview

Production uses **rolling deployments** for zero-downtime updates:

1. New code uploaded to S3
2. ASG launches new instances with new code
3. New instances register with ALB
4. ALB performs health checks
5. Old instances terminated after new ones healthy

### 5.2 Deploy via GitHub Actions

```bash
# Tag a new release
git tag v1.0.1
git push origin v1.0.1

# GitHub Actions automatically deploys to PROD (with approval)
```

### 5.3 Manual Deployment

```bash
# From repository root
cd infra/scripts
./deploy-backend-api-prod.sh
```

### 5.4 Monitor Deployment

```powershell
$ASG_NAME = "d2-ride-booking-prod-backend-api-asg"

# Check instance refresh status
aws autoscaling describe-instance-refreshes `
    --region ap-southeast-1 `
    --auto-scaling-group-name $ASG_NAME `
    --query "InstanceRefreshes[0].[Status,PercentageComplete]" `
    --output table
```

### 5.5 Rollback Deployment

```powershell
# Cancel instance refresh
aws autoscaling cancel-instance-refresh `
    --region ap-southeast-1 `
    --auto-scaling-group-name $ASG_NAME

# Revert to previous version
$PREV_VERSION = "v1.0.0"
aws ssm put-parameter `
    --region ap-southeast-1 `
    --name "/d2-ride-booking/prod/backend-api/version" `
    --value $PREV_VERSION `
    --type String `
    --overwrite

# Trigger new deployment
aws autoscaling start-instance-refresh `
    --region ap-southeast-1 `
    --auto-scaling-group-name $ASG_NAME
```

---

## 6. CloudFront & Static Sites Management

### 6.1 Get CloudFront Distribution IDs

```powershell
cd infra\terraform\envs\prod
terraform output prod_summary | Select-String -Pattern "distribution_id"
```

### 6.2 Deploy Static Sites

**Deploy web-admin:**
```powershell
cd apps\web-admin

# Build
npm run build

# Get bucket name from Terraform
$BUCKET = terraform output -raw prod_summary | Select-String -Pattern "web_admin.*bucket_name"

# Upload to S3
aws s3 sync dist/ s3://$BUCKET/ --delete

# Invalidate CloudFront
$DIST_ID = "E1234567890ABC"
aws cloudfront create-invalidation `
    --distribution-id $DIST_ID `
    --paths "/*"
```

### 6.3 Test Static Sites

```powershell
# Test web-admin
curl https://admin.d2.fikri.dev

# Check CloudFront cache
curl -I https://admin.d2.fikri.dev
# Look for: X-Cache: Hit from cloudfront
```

---

## 7. Application Load Balancer (ALB)

### 7.1 Get ALB Information

```powershell
# Get ALB DNS
aws elbv2 describe-load-balancers `
    --region ap-southeast-1 `
    --query "LoadBalancers[?contains(LoadBalancerName,'prod')].{Name:LoadBalancerName,DNS:DNSName}" `
    --output table
```

### 7.2 View Target Health

```powershell
# Get target group ARN
$TG_ARN = aws elbv2 describe-target-groups `
    --region ap-southeast-1 `
    --query "TargetGroups[?contains(TargetGroupName,'backend-api')].TargetGroupArn" `
    --output text

# Check health
aws elbv2 describe-target-health `
    --region ap-southeast-1 `
    --target-group-arn $TG_ARN
```

### 7.3 Test ALB Endpoints

```powershell
# Test backend API
curl https://api.d2.fikri.dev/health

# Test with verbose output
curl -v https://api.d2.fikri.dev/api/docs
```

---

## 8. Cognito User Management

### 8.1 Get Cognito Configuration

```powershell
cd infra\terraform\envs\prod
terraform output prod_summary | Select-String -Pattern "cognito" -Context 5
```

### 8.2 Create Production Admin User

```powershell
$USER_POOL_ID = "ap-southeast-1_XXXXXXXXX"
$USERNAME = "admin@fikri.dev"

# Create user
aws cognito-idp admin-create-user `
    --region ap-southeast-1 `
    --user-pool-id $USER_POOL_ID `
    --username $USERNAME `
    --user-attributes Name=email,Value=$USERNAME Name=email_verified,Value=true

# Set permanent password (12+ characters for production)
aws cognito-idp admin-set-user-password `
    --region ap-southeast-1 `
    --user-pool-id $USER_POOL_ID `
    --username $USERNAME `
    --password "SecurePassword123!" `
    --permanent
```

### 8.3 Test Authentication

```powershell
$CLIENT_ID = "1ak3tj1bn3neor7hgsjr1ml5h3"

# Authenticate
aws cognito-idp initiate-auth `
    --region ap-southeast-1 `
    --auth-flow USER_PASSWORD_AUTH `
    --client-id $CLIENT_ID `
    --auth-parameters USERNAME="admin@fikri.dev",PASSWORD="SecurePassword123!"
```

---

## 9. Monitoring & Logs

### 9.1 View Backend API Logs

```powershell
# Tail logs in real-time
aws logs tail /aws/ec2/prod-d2-ride-booking-backend-api `
    --region ap-southeast-1 `
    --follow

# Filter for errors
aws logs filter-log-events `
    --region ap-southeast-1 `
    --log-group-name "/aws/ec2/prod-d2-ride-booking-backend-api" `
    --filter-pattern "ERROR" `
    --max-items 50
```

### 9.2 CloudWatch Metrics

```powershell
# View ASG CPU utilization
aws cloudwatch get-metric-statistics `
    --region ap-southeast-1 `
    --namespace AWS/EC2 `
    --metric-name CPUUtilization `
    --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME `
    --start-time (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss") `
    --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
    --period 300 `
    --statistics Average
```

---

## 10. Production Best Practices

### 10.1 Security

✅ **Access Control:**
- Use IAM roles for all AWS service access
- Enable MFA for production AWS console access
- Use SSM Session Manager instead of SSH
- Rotate credentials regularly

✅ **Network Security:**
- Database in private subnets only
- ALB security groups restrict to HTTPS (443)
- No public IPs for ASG instances
- Use security groups for defense in depth

✅ **Data Protection:**
- Enable RDS encryption at rest
- Enable RDS automated backups (7+ days retention)
- Use SSL/TLS for all connections

### 10.2 High Availability

✅ **Redundancy:**
- Deploy across multiple Availability Zones
- Use ALB with multiple target instances
- Enable RDS Multi-AZ for database failover
- Use CloudFront for static content

✅ **Health Checks:**
- Configure ALB health checks properly
- Set appropriate health check grace periods
- Monitor target health status

### 10.3 Deployment Safety

✅ **Rolling Deployment Best Practices:**
- Always test in DEV first
- Monitor logs during deployment
- Have rollback plan ready
- Use GitHub Actions with approval gates

✅ **Rollback Strategy:**
- Keep previous artifacts in S3
- Document rollback procedure
- Test rollback in DEV

### 10.4 Cost Optimization

✅ **Right-Sizing:**
- Monitor instance utilization
- Use t3.micro for low-traffic production
- Scale based on actual load

✅ **Cost Monitoring:**
- Enable AWS Cost Explorer
- Set up billing alerts
- Tag all resources properly

### 10.5 Disaster Recovery

✅ **Backup Strategy:**
- RDS automated backups (7 days minimum)
- RDS manual snapshots before major changes
- S3 versioning for static site buckets
- Export infrastructure as code

---

## 11. Non-Negotiable Principles

### 11.1 Environment Isolation

**DEV and PROD are fully isolated:**
- ❌ No shared VPC/subnets/security groups
- ❌ No shared databases
- ❌ No shared Cognito user pools
- ❌ No shared IAM roles/instance profiles
- ❌ No shared S3 buckets

**Why:** Sharing resources between environments collapses blast radius and makes auditing ambiguous.

### 11.2 Production Stability

**Production requirements:**
- ✅ Multi-AZ VPC with redundancy
- ✅ ALB with host-based routing
- ✅ RDS with backups enabled
- ✅ IAM DB authentication enabled
- ✅ No stopping RDS (breaks HA expectations)

### 11.3 Deployment Process

**Deployment guidelines:**
- ✅ Deployments via S3 + SSM (no SSH)
- ✅ Repeatable and reversible deployments
- ✅ Rollbacks via previous immutable artifacts
- ✅ GitHub Actions with approval gates

---

## 12. GitHub Actions Integration

### 12.1 Required GitHub Secrets

**PROD environment secrets:**
- `AWS_ROLE_ARN` - OIDC role for deployments
- `COGNITO_USER_POOL_ID` - PROD Cognito pool
- `COGNITO_CLIENT_ID` - PROD app client

### 12.2 Required GitHub Variables

**PROD environment variables:**
- `AWS_REGION` - ap-southeast-1
- `S3_BUCKET_ARTIFACT` - PROD artifacts bucket
- `PUBLIC_API_BASE_URL` - https://api.d2.fikri.dev

### 12.3 Deployment Workflows

**Available workflows:**
- `.github/workflows/backend-api-deploy-prod.yml`
- `.github/workflows/web-driver-deploy-prod.yml` (future)

**Enable PROD deploy role:**
```hcl
# In terraform.tfvars
enable_github_actions_deploy_role = true
github_oidc_provider_arn = "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
github_repo = "owner/repo-name"
```

---

## 13. Troubleshooting

### 13.1 ASG Instances Not Healthy

```powershell
# Check target health
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Common issues:
# - Application not responding on health check path
# - Security group blocking ALB → instance traffic
# - Health check grace period too short
```

### 13.2 Deployment Stuck

```powershell
# Cancel instance refresh
aws autoscaling cancel-instance-refresh --auto-scaling-group-name $ASG_NAME

# Check recent activity
aws autoscaling describe-scaling-activities --auto-scaling-group-name $ASG_NAME
```

### 13.3 Database Connection Issues

```bash
# From ASG instance
nc -zv <RDS_ENDPOINT> 3306

# Check IAM auth
aws rds generate-db-auth-token --hostname <RDS_ENDPOINT> --port 3306 --username app_user
```

---

**Last Updated:** 2026-02-04
**Environment:** Production
**Region:** ap-southeast-1
**Terraform Version:** ~> 1.5

