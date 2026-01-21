# Phase 4: Quick Start Guide

## 🚀 Deploy RDS Infrastructure

```bash
# Navigate to DEV environment
cd infra/terraform/envs/dev

# Initialize Terraform (if not done already)
terraform init

# Review changes
terraform plan

# Apply infrastructure
terraform apply
```

**Wait**: 5-10 minutes for RDS instance to become available

---

## 🔐 Setup Database User (One-Time)

```bash
# 1. Get RDS endpoint
RDS_ENDPOINT=$(terraform output -raw rds_address)

# 2. Get master password
SECRET_NAME=$(terraform output -raw master_password_secret_arn | xargs -I {} basename {})
MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query SecretString \
  --output text \
  --region ap-southeast-1)

# 3. Connect and create application user
mysql -h $RDS_ENDPOINT -u admin -p"$MASTER_PASSWORD" <<EOF
CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT ALL PRIVILEGES ON ridebooking.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
SELECT User, Host, plugin FROM mysql.user WHERE User='app_user';
EOF
```

**Expected Output**:
```
+----------+------+---------------------+
| User     | Host | plugin              |
+----------+------+---------------------+
| app_user | %    | AWSAuthenticationPlugin |
+----------+------+---------------------+
```

---

## 📊 Verify Configuration

```bash
# Check RDS outputs
terraform output

# Expected outputs:
# - rds_endpoint: <hostname>:3306
# - db_name: ridebooking
# - iam_database_authentication_enabled: true
# - rds_resource_id: db-XXXXX

# Test database connection
RDS_ENDPOINT=$(terraform output -raw rds_address)
mysql -h $RDS_ENDPOINT -u admin -p"$MASTER_PASSWORD" -e "SHOW DATABASES;"
```

---

## 💰 Daily Cost Control

### Stop DEV Environment (End of Day)
```bash
# Linux/macOS
./infra/scripts/dev-stop.sh

# Windows
.\infra\scripts\dev-stop.ps1
```

### Start DEV Environment (Start of Day)
```bash
# Linux/macOS
./infra/scripts/dev-start.sh

# Windows
.\infra\scripts\dev-start.ps1
```

### Check Status
```bash
# Linux/macOS
./infra/scripts/dev-status.sh

# Windows
.\infra\scripts\dev-status.ps1
```

---

## 🔗 Backend Application Integration

### Environment Variables
```bash
export DB_HOST="<rds-endpoint>"
export DB_PORT="3306"
export DB_NAME="ridebooking"
export DB_USER="app_user"
export AWS_REGION="ap-southeast-1"

# Recommended for AWS (IAM DB Authentication)
export DB_IAM_AUTH="true"

# IAM auth requires TLS
export DB_SSL="true"
export DB_SSL_REJECT_UNAUTHORIZED="true"
# Optional: point to the AWS RDS global CA bundle PEM
# export DB_SSL_CA_PATH="/opt/d2/shared/aws-rds-global-bundle.pem"

# Note: No DB_PASSWORD - app generates IAM tokens
```

### Node.js Connection Example
```javascript
const AWS = require('aws-sdk');
const mysql = require('mysql2/promise');

async function connectToDatabase() {
  // Generate IAM auth token (valid 15 minutes)
  const signer = new AWS.RDS.Signer({
    region: process.env.AWS_REGION,
    hostname: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT),
    username: process.env.DB_USER
  });

  const token = await new Promise((resolve, reject) => {
    signer.getAuthToken({}, (err, token) => {
      if (err) reject(err);
      else resolve(token);
    });
  });

  // Connect using token as password
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    user: process.env.DB_USER,
    password: token,
    database: process.env.DB_NAME,
    ssl: {
      rejectUnauthorized: true
    }
  });

  return connection;
}
```

---

## 🔍 Troubleshooting

### RDS Not Creating
```bash
# Check Terraform state
terraform show

# Check AWS RDS service
aws rds describe-db-instances --region ap-southeast-1
```

### Cannot Connect to RDS
```bash
# 1. Verify RDS is available
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# 2. Verify IAM auth is enabled
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].IAMDatabaseAuthenticationEnabled' \
  --output text

# 3. Test security group (from backend EC2)
nc -zv <rds-endpoint> 3306
```

### Application User Creation Failed
```bash
# Connect as master user
mysql -h $(terraform output -raw rds_address) -u admin -p

# Check existing users
SELECT User, Host, plugin FROM mysql.user;

# Drop and recreate if needed
DROP USER IF EXISTS 'app_user'@'%';
CREATE USER 'app_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT ALL PRIVILEGES ON ridebooking.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
```

---

## 📋 Key Outputs Reference

```bash
# RDS Connection Info
terraform output rds_endpoint
terraform output rds_address
terraform output rds_port
terraform output db_name

# IAM Auth Info
terraform output rds_resource_id
terraform output iam_database_authentication_enabled

# Secrets
terraform output master_password_secret_arn

# Instance Info (for scripts)
terraform output rds_instance_id
```

---

## ⚠️ Important Notes

1. **IAM Database Authentication**:
   - Application MUST use IAM tokens (not passwords)
   - Tokens valid for 15 minutes
   - TLS/SSL connection required

2. **Master Password**:
   - Stored in Secrets Manager
   - For admin use only (setup, migrations)
   - NOT for application connections

3. **Cost Control**:
   - Stop RDS when not in use (saves ~$0.017/hour)
   - RDS auto-starts after 7 days if stopped
   - Storage charges continue even when stopped

4. **Security**:
   - RDS in private subnet (no internet access)
   - Security group restricts to backend API only
   - IAM role needs `rds-db:connect` permission

---

## 🎯 Success Checklist

- [ ] RDS instance created and available
- [ ] IAM database authentication enabled
- [ ] Application user created with IAM plugin
- [ ] Backend IAM role has `rds-db:connect` permission
- [ ] Lifecycle scripts work (start/stop/status)
- [ ] No DB password in application config
- [ ] TLS/SSL connection verified

---

## 📚 Related Documentation

- [Full Implementation Guide](phase4-rds-implementation.md)
- [Lifecycle Scripts README](../infra/scripts/README.md)
- [Architecture Overview](architecture.md)
- [Cost Strategy](cost-strategy.md)

---

**Next**: Phase 5 - EC2 Compute Instances
