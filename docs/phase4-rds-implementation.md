# Phase 4: RDS MySQL with IAM Database Authentication - Implementation Summary

## Overview

Phase 4 implements the data layer for the ride-booking application using Amazon RDS MySQL with IAM Database Authentication. This phase focuses on secure, cost-optimized database infrastructure for the DEV environment.

---

## What Was Implemented

### 1. RDS Module (`infra/terraform/modules/rds/`)

**Files Created**:
- `main.tf` - RDS instance, subnet group, security group
- `variables.tf` - Module input variables
- `outputs.tf` - Module outputs for integration

**Key Features**:
- ✅ **IAM Database Authentication ENABLED** (mandatory requirement)
- ✅ Single-AZ deployment (DEV cost optimization)
- ✅ Small instance class: `db.t3.micro`
- ✅ Private subnet only (no public access)
- ✅ Storage autoscaling (20 GB → 100 GB max)
- ✅ Minimal backup retention (1 day)
- ✅ No deletion protection (DEV flexibility)
- ✅ Security group restricts access to backend API only

**Database User Model**:
```
Master User (admin)
├─ Stored in Secrets Manager
├─ Used for: Initial setup, migrations, admin tasks
└─ NOT used by application

Application User (app_user)
├─ Created with: IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'
├─ Authenticates via: IAM tokens (15-minute validity)
├─ Requires: TLS/SSL connection
└─ No password in application config
```

---

### 2. IAM Permissions Update (`infra/terraform/modules/iam/`)

**Modified Files**:
- `variables.tf` - Added RDS IAM auth variables
- `policies.tf` - Added `rds-db:connect` permission

**New IAM Policy Statement**:
```hcl
{
  "Effect": "Allow",
  "Action": ["rds-db:connect"],
  "Resource": [
    "arn:aws:rds-db:region:account:dbuser:db-XXXXX/app_user"
  ]
}
```

**Security**:
- ✅ Least privilege (scoped to specific DB resource and username)
- ✅ No wildcard resources
- ✅ Conditional inclusion (only added if RDS exists)

---

### 3. DEV Environment Integration (`infra/terraform/envs/dev/`)

**Modified Files**:
- `main.tf` - Added RDS module call, data sources
- `variables.tf` - Added RDS configuration variables
- `terraform.tfvars` - Added RDS values
- `outputs.tf` - Added RDS outputs

**Key Changes**:
```terraform
# Data sources for IAM policy
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# RDS module with IAM auth
module "rds" {
  source = "../../modules/rds"
  
  # IAM Database Authentication (REQUIRED)
  iam_database_authentication_enabled = true
  
  # DEV cost optimization
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}
```

---

### 4. Lifecycle Control Scripts (`infra/scripts/`)

**Files Created**:

#### Bash Scripts (Linux/macOS)
- `dev-start.sh` - Start RDS and EC2 instances
- `dev-stop.sh` - Stop RDS and EC2 instances
- `dev-status.sh` - Display resource status

#### PowerShell Scripts (Windows)
- `dev-start.ps1` - Start RDS and EC2 instances
- `dev-stop.ps1` - Stop RDS and EC2 instances
- `dev-status.ps1` - Display resource status

#### Documentation
- `README.md` - Comprehensive usage guide

**Cost Impact**:
```
Daily Savings (8-hour workday):
├─ RDS stopped 16 hours:  ~$0.27/day
├─ EC2 stopped 16 hours:  ~$0.33/day
└─ Total:                 ~$0.60/day → ~$18/month
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.20.0.0/16)                  │
│                                                             │
│  ┌─────────────────────┐        ┌─────────────────────┐   │
│  │  Public Subnet      │        │  Private Subnet     │   │
│  │  (10.20.1.0/24)    │        │  (10.20.11.0/24)    │   │
│  │                     │        │                     │   │
│  │  ┌───────────────┐ │        │  ┌───────────────┐ │   │
│  │  │   NAT GW      │ │        │  │  Backend API  │ │   │
│  │  │  (optional)   │ │        │  │   EC2         │ │   │
│  │  └───────────────┘ │        │  └───────┬───────┘ │   │
│  │                     │        │          │         │   │
│  └─────────────────────┘        │          │         │   │
│                                 │    IAM Auth Token  │   │
│                                 │          │         │   │
│                                 │          ▼         │   │
│                                 │  ┌───────────────┐ │   │
│                                 │  │  RDS MySQL    │ │   │
│                                 │  │  db.t3.micro  │ │   │
│                                 │  │               │ │   │
│                                 │  │ IAM Auth:     │ │   │
│                                 │  │ ✓ Enabled     │ │   │
│                                 │  │ ✓ TLS Req'd   │ │   │
│                                 │  └───────────────┘ │   │
│                                 └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

Security Groups:
├─ Backend API SG → allows egress to RDS (port 3306)
└─ RDS SG → allows ingress from Backend API SG only
```

---

## IAM Database Authentication Flow

### Setup (One-time)
```bash
# 1. Connect to RDS using master user
mysql -h <rds-endpoint> -u admin -p

# 2. Create application user with IAM plugin
CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT ALL PRIVILEGES ON ridebooking.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
```

### Application Runtime (Every Connection)
```javascript
// Backend API (NestJS/Node.js)
const AWS = require('aws-sdk');
const mysql = require('mysql2');

// 1. Generate temporary IAM auth token (valid 15 minutes)
const rds = new AWS.RDS();
const token = rds.Signer.getAuthToken({
  region: 'ap-southeast-1',
  hostname: process.env.DB_HOST,
  port: 3306,
  username: 'app_user'
});

// 2. Connect to RDS using token as password
const connection = mysql.createConnection({
  host: process.env.DB_HOST,
  port: 3306,
  user: 'app_user',
  password: token,  // ← IAM token (NOT static password)
  database: 'ridebooking',
  ssl: 'Amazon RDS'  // ← TLS required
});
```

**Key Points**:
- ✅ No password in application config
- ✅ No password in environment variables
- ✅ Token auto-rotates every 15 minutes
- ✅ TLS/SSL connection mandatory
- ✅ IAM role must have `rds-db:connect` permission

---

## Validation Checklist

### Infrastructure
- [x] RDS instance has IAM DB Auth enabled
- [x] RDS is in private subnet (no public access)
- [x] Security group restricts access to backend API only
- [x] Single-AZ deployment (DEV cost optimization)
- [x] Storage autoscaling enabled
- [x] Backup retention minimal (1 day)
- [x] No deletion protection (DEV flexibility)
- [x] Master password stored in Secrets Manager (admin use only)

### IAM Permissions
- [x] Backend IAM role has `rds-db:connect` permission
- [x] Permission scoped to specific DB resource and username
- [x] No wildcard resources in policy
- [x] Policy is conditionally included (only when RDS exists)

### Cost Control
- [x] Lifecycle scripts created (start/stop/status)
- [x] Scripts work on Linux/macOS (Bash)
- [x] Scripts work on Windows (PowerShell)
- [x] Documentation explains cost savings
- [x] Scripts do NOT modify Terraform state

### Documentation
- [x] Inline comments explain WHY decisions were made
- [x] Database user model documented
- [x] IAM auth flow documented
- [x] Application integration guide provided
- [x] Cost control strategy documented

---

## Usage

### 1. Deploy Infrastructure

```bash
cd infra/terraform/envs/dev
terraform init
terraform plan
terraform apply
```

**Expected Outputs**:
```
rds_endpoint = "d2-ride-booking-dev-abc123.xyz.ap-southeast-1.rds.amazonaws.com:3306"
db_name = "ridebooking"
iam_database_authentication_enabled = true
rds_resource_id = "db-ABC123DEF456"
```

### 2. Setup Application Database User

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)

# Get master password from Secrets Manager
SECRET_ARN=$(terraform output -raw master_password_secret_arn)
MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_ARN \
  --query SecretString \
  --output text)

# Connect and create app user
mysql -h $RDS_ENDPOINT -u admin -p"$MASTER_PASSWORD" <<EOF
CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT ALL PRIVILEGES ON ridebooking.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
EOF
```

### 3. Configure Backend Application

```bash
# Environment variables for backend API
export DB_HOST="<rds-endpoint>"
export DB_PORT="3306"
export DB_NAME="ridebooking"
export DB_USER="app_user"
export AWS_REGION="ap-southeast-1"

# Note: No DB_PASSWORD needed - app generates IAM tokens
```

### 4. Daily Cost Control

```bash
# Evening: Stop DEV environment
./infra/scripts/dev-stop.sh

# Morning: Start DEV environment
./infra/scripts/dev-start.sh

# Anytime: Check status
./infra/scripts/dev-status.sh
```

---

## Cost Breakdown

### Running Costs (24/7)
| Resource | Unit Cost | Quantity | Monthly Cost |
|----------|-----------|----------|--------------|
| RDS db.t3.micro | $0.017/hour | 1 | ~$12.24 |
| RDS Storage | $0.10/GB/month | 20 GB | ~$2.00 |
| EC2 t3.micro | $0.0104/hour | 2 | ~$14.98 |
| EBS Storage | $0.08/GB/month | 16 GB | ~$1.28 |
| **Total** | | | **~$30.50/month** |

### Optimized Costs (8-hour workdays, stop when idle)
| Resource | Monthly Cost |
|----------|--------------|
| RDS (compute 40h/week) | ~$3.40 |
| RDS (storage always) | ~$2.00 |
| EC2 (compute 40h/week) | ~$4.16 |
| EBS (storage always) | ~$1.28 |
| **Total** | **~$10.84/month** |

**Monthly Savings**: ~$19.66 (65% reduction)

---

## Next Steps

### Phase 5: EC2 Compute Instances
- [ ] Create EC2 launch templates
- [ ] Deploy backend API (NestJS)
- [ ] Deploy driver web (Next.js)
- [ ] Configure SSM Session Manager access
- [ ] Implement application logging

### Phase 6: Application Load Balancer
- [ ] Create ALB with HTTPS listener
- [ ] Configure target groups
- [ ] Setup health checks
- [ ] Enable access logs

### Phase 7: CI/CD Pipeline
- [ ] Setup GitHub OIDC provider
- [ ] Create deployment workflows
- [ ] Implement automated testing
- [ ] Configure deployment strategies

---

## Troubleshooting

### Issue: RDS connection fails with "Access denied"

**Possible Causes**:
1. Application user not created with IAM plugin
2. IAM role missing `rds-db:connect` permission
3. TLS/SSL not enabled in connection

**Solution**:
```bash
# Verify IAM auth is enabled
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].IAMDatabaseAuthenticationEnabled'

# Verify IAM role has permission
aws iam get-role-policy \
  --role-name dev-d2-ride-booking-backend-api \
  --policy-name backend-api-policy
```

### Issue: Lifecycle scripts report "No instances found"

**Solution**:
```bash
# Verify infrastructure is created
cd infra/terraform/envs/dev
terraform show

# Check AWS region
aws configure get region

# Verify AWS credentials
aws sts get-caller-identity
```

---

## References

- [AWS RDS IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [Terraform AWS RDS Module](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)
- [AWS SDK - Generate Auth Token](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/RDS/Signer.html)

---

## Validation Commands

```bash
# Verify RDS is created
terraform output rds_endpoint

# Verify IAM auth is enabled
terraform output iam_database_authentication_enabled

# Test lifecycle scripts
./infra/scripts/dev-status.sh
./infra/scripts/dev-stop.sh
sleep 60
./infra/scripts/dev-status.sh
./infra/scripts/dev-start.sh

# Check Terraform state consistency
terraform plan  # Should show no changes
```

---

## Success Criteria

✅ RDS MySQL instance deployed with IAM DB Auth  
✅ Backend IAM role can connect using `rds-db:connect`  
✅ No DB password exists in application config  
✅ RDS is private and security-group-restricted  
✅ Lifecycle scripts work without modifying Terraform state  
✅ Stopping DEV reduces cost by ~65%  
✅ All validation commands pass successfully  

---

**Phase 4 Status**: ✅ **COMPLETE**
