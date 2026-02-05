# Ride Booking Platform — Cloud Platform Engineering & DevSecOps Portfolio

A production-grade, cost-optimized multi-tenant ride booking platform demonstrating **Cloud Platform Engineering**, **DevSecOps Architecture**, and **Infrastructure as Code** best practices on AWS.

This project showcases enterprise-ready patterns for secure authentication, immutable deployments, environment separation, and cost-conscious infrastructure design—built as a portfolio artifact for Cloud Platform Engineer and DevSecOps Architect roles.

---

## 🎯 Project Goals

### Business Domain
Uber-style ride booking platform with three user personas:
- **Passengers** — Book rides via static web app
- **Drivers** — Accept rides via SSR-enabled web app (WebSocket-ready)
- **Admins** — Manage platform via internal dashboard

### Engineering Goals
| Goal | Implementation |
|------|----------------|
| **Cloud-native architecture** | Multi-tier AWS infrastructure with VPC isolation, ALB, RDS, CloudFront |
| **DevSecOps from day one** | Security scanning in CI (Semgrep, Gitleaks, Trivy), OIDC-based deployments |
| **Cost optimization** | DEV/PROD parity with infrastructure toggles, consolidated EC2 in DEV |
| **Zero-trust auth** | AWS Cognito JWT-based auth with IAM database authentication |
| **Immutable deployments** | Artifact-based releases via S3, no SSH, SSM-only access |
| **Platform engineering** | Reusable Terraform modules, standardized CI/CD, developer experience focus |

---

## 🏗 Architecture Overview

### Monorepo Structure
```
apps/
  backend-api/        # NestJS REST API (TypeScript)
  web-admin/          # React + Vite SPA (static, CloudFront)
  web-passenger/      # Next.js static export (CloudFront)
  web-driver/         # Next.js SSR (EC2, WebSocket-ready)
infra/
  terraform/
    modules/          # 17 reusable infrastructure modules
    envs/
      dev/            # Cost-optimized single-AZ environment
      prod/           # Production-ready multi-AZ environment
docs/                 # Architecture decision records
.github/workflows/    # 16 CI/CD pipelines (CI + Deploy × Environment)
```

### Component Responsibilities

| Component | Technology | Deployment | Purpose |
|-----------|------------|------------|---------|
| `backend-api` | NestJS 11, TypeScript 5.9 | EC2 via ASG | REST API, JWT validation, DB access |
| `web-admin` | React 19, Vite 7 | CloudFront + S3 | Admin dashboard (static) |
| `web-passenger` | Next.js 16 | CloudFront + S3 | Passenger booking (static export) |
| `web-driver` | Next.js 16 | EC2 (PM2) | Driver app (SSR, realtime-ready) |

### Request Flow
```
Internet → Route53 → CloudFront (static) → S3 (web-admin, web-passenger)
                   → ALB (HTTPS) → EC2 (backend-api:3000, web-driver:3001)
                                 ↓
                              RDS MySQL (IAM auth, private subnet)
```

### Environment Separation Strategy

| Aspect | DEV | PROD |
|--------|-----|------|
| **Availability** | Single-AZ | Multi-AZ |
| **Compute** | Single consolidated EC2 | ASG with launch templates |
| **NAT Gateway** | Disabled (cost) | Enabled |
| **RDS** | Single-AZ, no deletion protection | Multi-AZ, deletion protection |
| **Log retention** | 7 days | 30-90 days |
| **CloudWatch alarms** | Toggle-able | Always on |

---

## ☁️ Cloud Architecture

### AWS Services Used

| Category | Service | Purpose |
|----------|---------|---------|
| **Compute** | EC2, ASG, Launch Templates | Application hosting with auto-scaling |
| **Networking** | VPC, Subnets, NAT Gateway, ALB | Network isolation and load balancing |
| **Database** | RDS MySQL 8.0 | Relational data with IAM authentication |
| **Auth** | Cognito User Pools | JWT-based authentication |
| **CDN** | CloudFront | Static site delivery with edge caching |
| **Storage** | S3 | Static assets, deployment artifacts |
| **DNS** | Route53 | Domain management and health checks |
| **Security** | IAM, Security Groups, ACM | Identity, network isolation, TLS |
| **Observability** | CloudWatch Logs, Alarms, SNS | Centralized logging and alerting |
| **Operations** | SSM Session Manager, Parameter Store | Secure access, runtime configuration |
| **Secrets** | Secrets Manager | RDS master credentials |

### Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                          VPC (10.0.0.0/16)                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │   Public Subnet A    │    │   Public Subnet B    │            │
│  │   (10.0.1.0/24)      │    │   (10.0.2.0/24)      │            │
│  │   • ALB              │    │   • ALB (multi-AZ)   │            │
│  │   • NAT Gateway*     │    │                      │            │
│  └─────────────────────┘    └─────────────────────┘             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │   Private App A      │    │   Private App B      │            │
│  │   (10.0.10.0/24)     │    │   (10.0.11.0/24)     │            │
│  │   • EC2 (API)        │    │   • EC2 (ASG)        │            │
│  │   • EC2 (Driver)     │    │                      │            │
│  └─────────────────────┘    └─────────────────────┘             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │   Private DB A       │    │   Private DB B       │  (PROD)   │
│  │   (10.0.20.0/24)     │    │   (10.0.21.0/24)     │            │
│  │   • RDS Primary      │    │   • RDS Standby      │            │
│  └─────────────────────┘    └─────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
  * NAT Gateway enabled in PROD only (cost optimization)
```

### Domain & Routing Design

| Domain | Target | TLS |
|--------|--------|-----|
| `admin.d2.fikri.dev` | CloudFront → S3 | ACM (us-east-1) |
| `passenger.d2.fikri.dev` | CloudFront → S3 | ACM (us-east-1) |
| `api.d2.fikri.dev` | ALB → EC2:3000 | ACM (ap-southeast-1) |
| `driver.d2.fikri.dev` | ALB → EC2:3001 | ACM (ap-southeast-1) |

---

## 🔐 Security Architecture

### Authentication Model

**Technology:** AWS Cognito User Pools with custom JWT claims

```
User → Frontend → Cognito (USER_PASSWORD_AUTH) → JWT tokens
                                                    ↓
Frontend → Backend API (Authorization: Bearer <token>)
                ↓
         JWT verification via JWKS (jose library)
                ↓
         Role extraction (custom:role claim)
                ↓
         RBAC enforcement (ADMIN | DRIVER | PASSENGER)
```

**Key Design Decisions:**
- No Cognito Hosted UI — custom login forms in each frontend
- Email as username (no separate username field)
- Role stored as Cognito custom attribute (`custom:role`)
- Short-lived access tokens (1 hour), long-lived refresh tokens (30 days)
- JWT validation using Cognito JWKS endpoint with caching

### Authorization Model

| Role | Capabilities |
|------|--------------|
| `ADMIN` | Full platform management, user CRUD, analytics |
| `DRIVER` | Own profile, ride acceptance, status updates |
| `PASSENGER` | Own profile, ride booking, history |

**Implementation:**
```typescript
// Global JWT guard (NestJS)
@Module({
  providers: [{
    provide: APP_GUARD,
    useClass: JwtAuthGuard  // Enforces JWT on all routes except @Public()
  }]
})
```

### Database Authentication

**IAM Database Authentication** — No static database passwords in application code

```
EC2 (IAM Role) → RDS Signer → Short-lived auth token (15 min)
                                    ↓
                              MySQL connection (TLS required)
```

**Benefits:**
- Credentials rotate automatically
- Audit trail via CloudTrail
- No secrets in environment variables
- Instance profile tied to EC2 instance

### IAM Design (Least Privilege)

| Role | Permissions | Purpose |
|------|-------------|---------|
| `backend-api` | SSM params, CloudWatch logs, RDS IAM auth, Secrets Manager | API runtime |
| `driver-web` | CloudWatch logs only | Frontend SSR (no DB access) |
| `github-actions-deploy` | S3 artifacts, SSM Run Command, EC2 describe | CI/CD deployments |

### Network Isolation

- **RDS** — Private subnets only, no public accessibility
- **EC2** — Private subnets, no public IPs
- **ALB** — Public subnets, HTTPS only (HTTP redirects to HTTPS)
- **Security Groups** — Explicit allow rules, deny-all default
- **VPC Endpoints** — SSM access without NAT Gateway (DEV cost optimization)

---

## 🔄 DevSecOps & CI/CD

### Pipeline Design

**16 GitHub Actions workflows** covering:
- CI validation (lint, typecheck, test, build)
- Security scanning (Semgrep SAST, Gitleaks secrets, npm audit, Trivy IaC)
- Deployment automation (artifact packaging, S3 upload, SSM deployment)
- Infrastructure validation (terraform fmt, validate, plan)

### Workflow Matrix

| App/Infra | CI (Dev) | CI (Prod) | Deploy (Dev) | Deploy (Prod) |
|-----------|----------|-----------|--------------|---------------|
| backend-api | ✓ | — | ✓ | ✓ |
| web-admin | ✓ | ✓ | ✓ | ✓ |
| web-passenger | ✓ | ✓ | ✓ | ✓ |
| web-driver | ✓ | — | ✓ | ✓ |
| terraform | ✓ | ✓ | — | — |

### Security Scanning Strategy

| Tool | Target | Stage | Severity Gate |
|------|--------|-------|---------------|
| **ESLint** | TypeScript/JS | CI | Error = fail |
| **Semgrep** | Application code | CI | p/default, p/nodejs, p/typescript |
| **Gitleaks** | Git history | CI | Any secret = fail |
| **npm audit** | Dependencies | CI | HIGH/CRITICAL = fail |
| **Trivy** | Terraform IaC | CI | CRITICAL/HIGH = fail |

### Deployment Strategy

**Immutable Artifact-Based Deployments:**

```
1. CI builds → dist/ + node_modules (pruned) + ecosystem.config.js
2. Package → backend-api-YYYYMMDD-HHMMSS.tar.gz
3. SHA256 checksum generated
4. Upload to S3 (versioned bucket)
5. SSM Run Command triggers EC2 deployment
6. EC2 downloads artifact, verifies checksum
7. Atomic symlink swap (/opt/apps/service/current → releases/TIMESTAMP)
8. PM2 restart with SSM Parameter Store env vars
9. Health check verification
```

**Zero SSH Access:**
- All deployments via SSM Run Command
- All operator access via SSM Session Manager
- No SSH keys, no bastion host required
- Full audit trail in CloudTrail

### Branching Model

```
feature/* → dev (CI runs) → main (production-ready)
              ↓                    ↓
         Deploy to DEV        Deploy to PROD (manual approval)
```

- `dev` — Active development, CI on all PRs
- `main` — Production-ready, protected branch
- Path-filtered workflows — Only relevant pipelines run

### Rolling Deployments (PROD)

```bash
# ASG rolling deployment via SSM
aws ssm send-command \
  --targets "Key=tag:Service,Values=backend-api" \
  --max-concurrency 1 \  # One instance at a time
  --document-name "AWS-RunShellScript"
```

---

## 💰 Cost Optimization Strategy

### DEV Environment Philosophy

> "DEV is for learning and iteration; over-provisioning hides performance and cost issues."

| Resource | DEV | PROD | Monthly Savings |
|----------|-----|------|-----------------|
| NAT Gateway | Disabled | Enabled | ~$32/month |
| RDS | db.t3.micro, Single-AZ | db.t3.small+, Multi-AZ | ~$15/month |
| EC2 | Single consolidated t3.micro | ASG (min 2) | ~$8/month |
| CloudWatch logs | 7-day retention | 30-90 days | ~$5/month |
| ALB | Toggle-able | Always on | ~$16/month |

### Infrastructure Toggles

```hcl
# DEV terraform.tfvars
enable_nat_gateway = false      # Use VPC Endpoints for SSM
enable_alb = true               # Toggle-able for debugging
enable_rds = true               # Toggle-able for stateless testing
enable_alarms = true            # Disable during load tests
enable_bastion = false          # SSM Session Manager preferred
```

### Consolidated Instance Strategy (DEV)

Both `backend-api` and `web-driver` run on a single EC2 instance:
- Separate PM2 processes (port 3000 and 3001)
- Separate CloudWatch log groups
- Shared IAM instance profile
- Single ALB routes to both via path-based routing

### Infracost Integration

```bash
# Estimate infrastructure cost from Terraform
./infra/scripts/infracost-estimate.ps1 -EnvName dev -Mode hcl
```

CI pipelines include `infracost breakdown` for PR cost visibility.

---

## 📊 Observability & Reliability

### Logging Design

**Structured JSON Logging:**
```typescript
// JsonLogger outputs CloudWatch-friendly format
{"level":"log","msg":"JWT verified","role":"DRIVER","timestamp":"2026-02-05T..."}
```

**Log Groups:**
| Service | Log Group | Retention |
|---------|-----------|-----------|
| backend-api | `/dev/backend-api` | 7 days (DEV) |
| web-driver | `/dev/web-driver` | 7 days (DEV) |

### CloudWatch Alarms

| Alarm | Metric | Threshold | Rationale |
|-------|--------|-----------|-----------|
| EC2 CPU High | CPUUtilization | >80% for 5 min | Detect sustained load |
| EC2 Status Check | StatusCheckFailed | Any | Hardware/network failure |
| RDS CPU High | CPUUtilization | >80% for 5 min | Database overload |
| RDS Storage Low | FreeStorageSpace | <2GB | Prevent disk exhaustion |
| RDS Connections High | DatabaseConnections | >80% max | Connection pool issues |

### Alerting

- SNS topic for alarm notifications
- Email subscription (team distribution list recommended)
- Alarms toggle-able for demos/load testing

### Deployment Safety

1. **Health check verification** — Deployment script polls `/health` endpoint
2. **Rollback capability** — Previous releases preserved on disk
3. **Atomic symlink swap** — Zero-downtime deployments
4. **Checksum verification** — SHA256 integrity check before deployment

---

## 🧩 Platform Engineering Practices

### Developer Experience

| Practice | Implementation |
|----------|----------------|
| **Local development** | Docker Compose for MySQL, matches RDS config |
| **Environment parity** | Same Terraform modules for DEV and PROD |
| **Self-service infra** | Toggle variables for optional resources |
| **Documentation** | Inline comments explaining every Terraform resource |

### Standardized Workflows

- **CI template pattern** — Consistent steps across all app pipelines
- **Deployment scripts** — Reusable `deploy-service-rolling.sh` for any service
- **PM2 ecosystem** — Standard process management across services

### Reusable Infrastructure Modules

```
infra/terraform/modules/
├── alb/                    # Application Load Balancer
├── asg/                    # Auto Scaling Groups with Launch Templates
├── bastion/                # Optional bastion host
├── cloudfront-static-site/ # S3 + CloudFront with OAC
├── cloudwatch/             # Log groups, alarms, SNS
├── cognito/                # User Pools with custom attributes
├── deployments-bucket/     # Versioned S3 for artifacts
├── ec2/                    # Single instance (DEV)
├── iam/                    # Roles and policies
├── rds/                    # MySQL with IAM auth
├── route53/                # DNS records
├── security-groups/        # Network ACLs
├── vpc/                    # Multi-tier network
└── vpc-endpoints/          # SSM without NAT
```

### Automation Highlights

- **Infracost** — Cost estimation in CI
- **Inframap** — Auto-generated architecture diagrams
- **Path-filtered CI** — Only affected services rebuild
- **OIDC authentication** — No static AWS credentials in CI

---

## 🚀 Getting Started

### Prerequisites

- Node.js 20 LTS
- Docker Desktop (for local MySQL)
- Terraform 1.6+
- AWS CLI v2 (configured with SSO or credentials)

### Local Development Setup

```bash
# 1. Start local MySQL
docker-compose up -d

# 2. Configure backend environment
cd apps/backend-api
cp .env.example .env
# Edit .env with Cognito values from Terraform output

# 3. Install and run backend
npm install
npm run start:dev

# 4. Test health endpoint
curl http://localhost:3000/health
```

### Environment Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `COGNITO_USER_POOL_ID` | Cognito pool ID | `terraform output -raw cognito_user_pool_id` |
| `COGNITO_CLIENT_ID` | Cognito app client | `terraform output -raw cognito_user_pool_client_id` |
| `DB_HOST` | MySQL host | `localhost` (local) or RDS endpoint |
| `DB_IAM_AUTH` | Enable IAM auth | `true` (AWS) or unset (local) |

---

## 📦 Deployment

### Infrastructure Deployment

```bash
# Initialize and apply DEV environment
cd infra/terraform/envs/dev
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan

# Get outputs for application configuration
terraform output
```

### Application Deployment

Deployments are triggered automatically on push to `dev` branch, or manually:

```bash
# Manual deployment (requires AWS credentials)
export AWS_REGION=ap-southeast-1
export S3_BUCKET_ARTIFACT=ridebooking-deployments-dev-ACCOUNT_ID
export RELEASE_ID=$(date +%Y%m%d-%H%M%S)
export ENVIRONMENT=dev
export PROJECT_NAME=ridebooking

./infra/scripts/deploy-backend-api.sh
```

### Environment Promotion

```
dev → Manual PR to main → Approval → PROD deploy
```

PROD deployments use rolling strategy with `max-concurrency=1` for zero-downtime.

---

## 🧪 Testing Strategy

### Unit Tests

```bash
cd apps/backend-api
npm run test          # Jest unit tests
npm run test:cov      # Coverage report
```

### Type Checking

```bash
npm run typecheck     # TypeScript strict mode validation
```

### Security Testing

| Test | Command | CI Stage |
|------|---------|----------|
| SAST | `semgrep --config p/default` | CI |
| Secrets | `gitleaks detect` | CI |
| Dependencies | `npm audit --production` | CI |
| IaC | `trivy config infra/terraform` | CI |

### Infrastructure Validation

```bash
cd infra/terraform/envs/dev
terraform fmt -check -recursive   # Format check
terraform validate                 # Syntax validation
terraform plan                     # Change preview
```

---

## 📌 Engineering Trade-offs & Lessons Learned

### What Would Be Different at Scale

| Current State | Production Scale Improvement |
|---------------|------------------------------|
| Single RDS instance | Aurora Serverless v2 for auto-scaling |
| PM2 process manager | Container orchestration (ECS Fargate or EKS) |
| ALB health checks | Application-level health (DB connectivity, dependencies) |
| Manual PROD approval | Canary deployments with automatic rollback |
| CloudWatch alarms | APM integration (Datadog, New Relic) |

### Known Limitations

1. **No auto-scaling in DEV** — Single instance, manual scaling
2. **No blue-green deployments** — Rolling only, brief connection drops possible
3. **No database migrations automation** — Manual SQL execution
4. **No WebSocket implementation** — web-driver is SSR-ready but no realtime features yet
5. **No rate limiting** — API Gateway or WAF would add this in production

### Future Roadmap Ideas

- [ ] Container migration (Dockerfile + ECS/Fargate)
- [ ] API Gateway + Lambda authorizer for edge auth
- [ ] EventBridge for async workflows (ride matching)
- [ ] ElastiCache for session/rate limiting
- [ ] WAF rules for OWASP protection
- [ ] Automated database migrations (Flyway/Liquibase)
- [ ] OpenTelemetry instrumentation

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [architecture.md](docs/architecture.md) | System design rationale |
| [auth-cognito.md](docs/auth-cognito.md) | Authentication flow details |
| [auth-rbac.md](docs/auth-rbac.md) | Authorization model |
| [cost-strategy.md](docs/cost-strategy.md) | Cost optimization principles |
| [local-dev-setup.md](docs/local-dev-setup.md) | Developer onboarding |
| [infracost.md](docs/infracost.md) | Cost estimation tooling |

---

## 📄 License

This project is unlicensed and intended as a portfolio demonstration.
