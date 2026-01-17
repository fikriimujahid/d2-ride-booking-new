# Phase 3: IAM, Cognito, and Security Baseline

## Quick Start

### Deploy Phase 3 Infrastructure

```bash
# Navigate to DEV environment
cd infra/terraform/envs/dev

# Initialize Terraform (download providers and modules)
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Capture outputs
terraform output > phase3-outputs.txt
```

### Expected Resources (14 total)
- ✅ 2 IAM Roles
- ✅ 2 IAM Instance Profiles
- ✅ 4 IAM Role Policies
- ✅ 1 Cognito User Pool
- ✅ 1 Cognito App Client
- ✅ 4 Security Groups
- ✅ ~12 Security Group Rules

### Estimated Deployment Time
- Initial: ~3 minutes
- Updates: ~1-2 minutes

---

## What This Phase Includes

### 1. IAM Foundation
**Location:** `infra/terraform/modules/iam/`

Least-privilege IAM roles for:
- **Backend API** - Secrets Manager (DB only) + CloudWatch Logs + SSM core
- **Driver Web** - CloudWatch Logs + SSM core
- **CI/CD** - Placeholder for GitHub OIDC (Phase 4)

**Key Features:**
- No inline JSON policies (all use data sources)
- Scoped to project-specific resources
- Clear "WHY" comments for each permission

### 2. Cognito User Pool
**Location:** `infra/terraform/modules/cognito/`

JWT-based authentication with:
- Email as username (auto-verify)
- Custom attribute: `custom:role` (ADMIN, DRIVER, PASSENGER)
- No Hosted UI (frontend handles auth)
- 1-hour access tokens, 30-day refresh tokens

**Key Features:**
- Strong password policy
- Token refresh enabled
- Clear JWT validation endpoints

### 3. Security Groups
**Location:** `infra/terraform/modules/security-groups/`

Network isolation for:
- **ALB** - HTTPS/HTTP from internet
- **Backend API** - HTTP from ALB only
- **Driver Web** - HTTP from ALB only
- **RDS** - MySQL from Backend API only

**Key Features:**
- Least-privilege rules
- Security group references (not IPs)
- Clear SSM-only access posture (no SSH)

---

## Directory Structure

```
infra/terraform/
├── modules/
│   ├── iam/
│   │   ├── main.tf          # IAM roles + instance profiles
│   │   ├── policies.tf      # Policy documents (WHY comments)
│   │   ├── variables.tf     # Inputs (environment, secrets ARNs)
│   │   └── outputs.tf       # Role ARNs + instance profile names
│   ├── cognito/
│   │   ├── main.tf          # User Pool + App Client
│   │   ├── variables.tf     # Inputs (domain, password policy)
│   │   └── outputs.tf       # Pool ID, Client ID, JWKS URI
│   └── security-groups/
│       ├── main.tf          # All security groups + rules
│       ├── variables.tf     # VPC ID, CIDRs
│       └── outputs.tf       # Security group IDs
└── envs/dev/
    ├── main.tf              # Wires all modules together
    ├── variables.tf         # DEV-specific variable definitions
    ├── outputs.tf           # Aggregated outputs
    └── terraform.tfvars     # DEV values
```

---

## Configuration

### Key Variables (terraform.tfvars)

```hcl
# Core
environment  = "dev"
project_name = "ridebooking"
domain_name  = "d2.fikri.dev"

# Network
vpc_cidr            = "10.20.0.0/16"

# Cognito
cognito_password_min_length = 8    # ⚠️ DEV only - use 12+ in PROD

# IAM
secrets_manager_arns = []          # Will be populated in Phase 4
```

### Important Outputs

After `terraform apply`, capture these outputs:

```bash
# Cognito (for frontend)
cognito_user_pool_id     # ap-southeast-1_XXXXX
cognito_app_client_id    # abc123xyz (sensitive)

# Cognito (for backend)
cognito_jwks_uri         # For JWT signature verification
cognito_issuer           # For JWT issuer validation

# IAM (for Phase 4 EC2)
backend_api_instance_profile_name
driver_web_instance_profile_name

# Security Groups (for Phase 4 EC2/RDS/ALB)
alb_security_group_id
backend_api_security_group_id
driver_web_security_group_id
rds_security_group_id
```

---

## Validation Checklist

Run these checks after deployment:

### ✅ IAM Roles
```bash
# List all ridebooking roles
aws iam list-roles --query "Roles[?contains(RoleName, 'ridebooking')].RoleName"

# Expected output:
# - dev-ridebooking-backend-api
# - dev-ridebooking-driver-web
```

### ✅ Cognito User Pool
```bash
# Get User Pool details
aws cognito-idp describe-user-pool --user-pool-id $(terraform output -raw cognito_user_pool_id)

# Verify:
# - UsernameAttributes: ["email"]
# - AutoVerifiedAttributes: ["email"]
# - Schema contains custom:role attribute
```

### ✅ Security Groups
```bash
# List all ridebooking security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=ride-booking-demo" \
  --query "SecurityGroups[].{Name:GroupName,ID:GroupId}"

# Expected: 4 security groups (alb, backend-api, driver-web, rds)
```

---

## Testing

### 1. Create Test User

```bash
# Set variables
USER_POOL_ID=$(cd infra/terraform/envs/dev && terraform output -raw cognito_user_pool_id)

# Create DRIVER user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username driver@fikri.dev \
  --user-attributes Name=email,Value=driver@fikri.dev Name=custom:role,Value=DRIVER \
  --temporary-password TempPass123!

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username driver@fikri.dev \
  --password YourSecurePass123! \
  --permanent
```

### 2. Test JWT Generation

```bash
# Get App Client ID
CLIENT_ID=$(cd infra/terraform/envs/dev && terraform output -raw cognito_app_client_id)

# Login (requires AWS CLI v2 or curl)
aws cognito-idp initiate-auth \
  --client-id $CLIENT_ID \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=driver@fikri.dev,PASSWORD=YourSecurePass123!

# Response includes:
# - AccessToken (for API authorization)
# - IdToken (contains custom:role claim)
# - RefreshToken (for token refresh)
```

### 3. Decode JWT Token

Copy the `IdToken` from above and decode at [jwt.io](https://jwt.io)

Verify claims:
```json
{
  "sub": "user-uuid",
  "email": "driver@fikri.dev",
  "custom:role": "DRIVER",
  "iss": "https://cognito-idp.ap-southeast-1.amazonaws.com/...",
  "exp": 1234567890
}
```

---

## Cost Breakdown

### Phase 3 Resources (Monthly)

| Resource             | Quantity | Cost      | Notes                          |
|---------------------|----------|-----------|--------------------------------|
| IAM Roles           | 2        | $0.00     | No charge                      |
| Cognito User Pool   | 1        | $0.00     | Free tier: 50,000 MAUs         |
| Security Groups     | 4        | $0.00     | No charge                      |
| **Total**           | -        | **$0.00** | Within AWS free tier           |

**Note:** Costs will increase in Phase 4 when EC2, RDS, and ALB are deployed.

---

## Security Notes

### ⚠️ DEV-Only Components (Remove in PROD)

1. **Session Manager Only (No SSH)**
   - SSH/SCP removed; use AWS Systems Manager Session Manager with IAM + CloudTrail logging
   - Configure VPC endpoints for SSM/EC2Messages/SSMMessages in Phase 4

2. **Weak Password Policy**
   - Current: 8 characters minimum
   - PROD: 12+ characters recommended

### 🔒 Security Best Practices

✅ **DO:**
- Validate JWT signatures using JWKS
- Validate issuer and audience claims
- Check token expiration on every request
- Use HTTPS for all API requests
- Store tokens in HTTP-only cookies (not localStorage)
- Enable CloudTrail for IAM activity logging

❌ **DON'T:**
- Trust role claim without validating JWT
- Use long-lived access tokens
- Store tokens in browser localStorage (XSS risk)
- Allow role changes without admin approval
- Open SSH; use Session Manager instead

---

## Troubleshooting

### Issue: `terraform init` fails
**Cause:** Missing Terraform or AWS provider

**Solution:**
```bash
# Verify Terraform version (requires >= 1.6.0)
terraform version

# Re-initialize with upgrade
terraform init -upgrade
```

### Issue: `terraform apply` fails with "VPC not found"
**Cause:** Phase 2 VPC not deployed

**Solution:**
```bash
# Verify Phase 2 is deployed
cd infra/terraform/envs/dev
terraform output vpc_id

# If empty, deploy Phase 2 first
terraform apply
```

### Issue: Cognito User Pool creation fails
**Cause:** Duplicate User Pool name

**Solution:**
```bash
# List existing User Pools
aws cognito-idp list-user-pools --max-results 10

# Delete old pool (⚠️ DEV only - destroys user data)
aws cognito-idp delete-user-pool --user-pool-id <OLD_POOL_ID>

# Re-run terraform
terraform apply
```

### Issue: Security Group rule limit exceeded
**Cause:** AWS limits security groups to 60 rules per group

**Solution:**
- Phase 3 uses ~3-4 rules per group (well within limits)
- If you hit limits in future phases, consolidate rules or use prefix lists

---

## Next Steps (Phase 4)

With Phase 3 complete, you now have:
- ✅ IAM roles ready for EC2 attachment
- ✅ Cognito ready for frontend integration
- ✅ Security groups ready for resource assignment

**Phase 4 will add:**
1. **Application Load Balancer (ALB)**
   - HTTPS listener with ACM certificate
   - Target groups for backend-api and driver-web
   - Security group: `alb_security_group_id`

2. **EC2 Instances**
   - Backend API (NestJS) - `backend_api_instance_profile_name`
   - Driver Web (Next.js) - `driver_web_instance_profile_name`

3. **RDS (MySQL)**
   - Single AZ (DEV)
   - Security group: `rds_security_group_id`
   - Secrets Manager for credentials

4. **Route 53**
   - DNS records for `d2.fikri.dev`
   - ALB alias records

---

## Documentation

- **[Phase 3 Summary](../../docs/phase-3-summary.md)** - Detailed implementation summary
- **[Authorization & RBAC](../../docs/auth-rbac.md)** - JWT and role-based access control
- **[Architecture Overview](../../docs/architecture.md)** - System architecture
- **[Cost Strategy](../../docs/cost-strategy.md)** - Cost optimization guide

---

## Commands Reference

```bash
# Initialize Terraform
terraform init

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply infrastructure
terraform apply

# Show outputs
terraform output

# Show specific output
terraform output -raw cognito_user_pool_id

# Destroy infrastructure (⚠️ DEV only)
terraform destroy
```

---

**Phase Status:** ✅ READY TO DEPLOY  
**Prerequisites:** Phase 2 (VPC) must be deployed  
**Next Phase:** Phase 4 - Application Infrastructure (ALB, EC2, RDS)
