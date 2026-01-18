# DEV Lifecycle Control Scripts

## Overview

These scripts provide runtime cost control for the DEV environment by stopping and starting AWS resources **without modifying Terraform state**. This is crucial for minimizing AWS costs during non-working hours.

## Key Concept

- **Terraform**: Creates/destroys infrastructure (modifies state)
- **Lifecycle Scripts**: Start/stop existing infrastructure (no state changes)

## Scripts

### 1. `generate-diagram.sh` / `generate-diagram.ps1`
**Purpose**: Generate human-readable architecture diagrams for the DEV environment from Terraform code.

**Usage**:
```bash
# Linux/macOS
./infra/scripts/generate-diagram.sh

# Windows PowerShell
.\infra\scripts\generate-diagram.ps1
```

**What it does**:
- ✅ Runs `terraform init` (safe, no apply)
- ✅ Runs `terraform graph` and pipes to Inframap
- ✅ Falls back to `terraform.tfstate` if needed
- ✅ Generates DOT, SVG, and PNG diagrams
- ⏱️  Takes 10-30 seconds to complete

**Output files** (in `docs/diagrams/`):
- `dev-infra.dot` - DOT file for future editing
- `dev-infra.svg` - SVG format (recommended for web)
- `dev-infra.png` - PNG format (for presentations)

**What it visualizes**:
- 📊 VPC and subnet architecture
- 🔐 Security groups and IAM roles
- 💾 RDS database instances
- 🔗 Resource relationships and dependencies

**Requirements**:
- `terraform` - Already installed
- `inframap` - Install with: `go install github.com/cycloidio/inframap@latest`
- `graphviz` - Install from: https://graphviz.org/download/

**Important Notes**:
- Does NOT apply infrastructure changes
- Does NOT require AWS credentials
- Safe to run locally anytime
- DEV environment only
- Ideal for documentation and onboarding

**Use cases**:
- 📚 Update architecture documentation
- 🎓 Onboard new team members
- 👀 Review infrastructure changes in PRs
- 📝 Create presentation materials

---

### 2. `dev-start.sh` / `dev-start.ps1`
**Purpose**: Start stopped RDS and EC2 instances to resume development work.

**Usage**:
```bash
# Linux/macOS
./infra/scripts/dev-start.sh

# Windows PowerShell
.\infra\scripts\dev-start.ps1
```

**What it does**:
- ✅ Starts stopped RDS MySQL instance
- ✅ Starts stopped EC2 instances (backend API, driver web)
- ⏱️  Takes 2-5 minutes for resources to become available

**Cost Impact**: Resumes hourly compute charges

---

### 3. `dev-stop.sh` / `dev-stop.ps1`
**Purpose**: Stop running RDS and EC2 instances to minimize costs when not in use.

**Usage**:
```bash
# Linux/macOS
./infra/scripts/dev-stop.sh

# Windows PowerShell
.\infra\scripts\dev-stop.ps1
```

**What it does**:
- ⏸️  Stops running RDS MySQL instance
- ⏸️  Stops running EC2 instances
- ⏱️  Takes 1-2 minutes to complete

**Cost Impact**: 
- ✅ **Eliminates** compute charges (~$0.017/hour for RDS + $0.0104/hour per EC2)
- ⚠️  **Continues** storage charges (~$0.10/GB/month for RDS + $0.08/GB/month for EBS)

**Important Notes**:
- Does NOT destroy infrastructure
- Does NOT modify Terraform state
- Resources can be restarted with `dev-start.sh`
- For full cleanup, use `terraform destroy`

---

### 4. `dev-status.sh` / `dev-status.ps1`
**Purpose**: Display current status of all DEV resources.

**Usage**:
```bash
# Linux/macOS
./infra/scripts/dev-status.sh

# Windows PowerShell
.\infra\scripts\dev-status.ps1
```

**What it shows**:
- 📊 RDS instance status (running/stopped)
- 🖥️  EC2 instance status (running/stopped)
- 💰 Current cost estimation
- ⚡ Quick action commands

---

## Cost Optimization Strategy

### Daily Workflow
```bash
# Morning: Start DEV environment
./infra/scripts/dev-start.sh

# ... work on development ...

# Evening: Stop DEV environment
./infra/scripts/dev-stop.sh
```

### Cost Savings Example (Single Day)
| Resource | Running (8 hours) | Stopped (16 hours) | Daily Savings |
|----------|------------------|-------------------|---------------|
| RDS db.t3.micro | $0.136 | $0 | **$0.272** |
| EC2 t3.micro x2 | $0.166 | $0 | **$0.332** |
| **Total** | **$0.302** | **$0** | **~$0.60/day** |

**Monthly Savings**: ~$18 (assuming 8-hour workdays, 5 days/week)

---

## Requirements

### Linux/macOS
- AWS CLI v2
- `jq` (for dev-status.sh)
- Bash shell

Install `jq`:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Amazon Linux
sudo yum install jq
```

### Windows
- AWS CLI v2
- PowerShell 5.1 or later

---

## AWS CLI Configuration

Scripts use the following AWS CLI configuration:
- **Region**: `ap-southeast-1` (configured in scripts)
- **Credentials**: Uses default AWS CLI profile

Ensure AWS CLI is configured:
```bash
aws configure
```

Or use environment variables:
```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=ap-southeast-1
```

---

## Terraform vs Lifecycle Scripts

### Use Terraform for:
- ✅ Creating new infrastructure
- ✅ Modifying resource configurations
- ✅ Destroying infrastructure completely

```bash
cd infra/terraform/envs/dev
terraform apply   # Create/modify infrastructure
terraform destroy # Destroy infrastructure
```

### Use Lifecycle Scripts for:
- ✅ Stopping resources at end of day (cost savings)
- ✅ Starting resources at beginning of day
- ✅ Checking resource status

```bash
./infra/scripts/dev-stop.sh    # Stop resources
./infra/scripts/dev-start.sh   # Start resources
./infra/scripts/dev-status.sh  # Check status
```

---

## Important Notes

### RDS Limitations
- **RDS can be stopped for max 7 days**: After 7 days, AWS automatically starts the instance
- **Snapshot before long breaks**: If not working for >7 days, consider:
  1. Creating a manual snapshot
  2. Destroying RDS with `terraform destroy`
  3. Recreating from snapshot when needed

### Storage Charges Continue
Even when stopped, you still pay for:
- RDS storage (~$0.10/GB/month)
- EBS volumes (~$0.08/GB/month)
- VPC components (NAT Gateway if enabled)

### State Consistency
- Scripts do NOT modify Terraform state
- Safe to use without affecting `terraform plan` or `terraform apply`
- Terraform will detect instance state (stopped) but won't attempt to change it

---

## Troubleshooting

### "No instances found"
**Problem**: Scripts report no instances found.

**Solution**: 
1. Ensure infrastructure is created: `cd infra/terraform/envs/dev && terraform apply`
2. Check AWS region matches script configuration
3. Verify AWS CLI credentials are configured

### "Instance is in 'starting' state"
**Problem**: Instance is already being started.

**Solution**: Wait for current operation to complete (2-5 minutes), then check status:
```bash
./infra/scripts/dev-status.sh
```

### PowerShell Execution Policy Error
**Problem**: PowerShell blocks script execution.

**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Best Practices

1. **Daily Routine**: Stop resources every evening, start every morning
2. **Weekend**: Keep resources stopped (saves ~$4-5 per weekend)
3. **Holidays**: Stop resources during extended breaks
4. **Monitoring**: Use `dev-status.sh` to verify resources are stopped
5. **Automation**: Consider using cron jobs (Linux) or Task Scheduler (Windows) for automatic shutdown

### Example Cron Job (Linux/macOS)
```bash
# Stop DEV environment every day at 6 PM
0 18 * * 1-5 /path/to/infra/scripts/dev-stop.sh

# Start DEV environment every weekday at 9 AM
0 9 * * 1-5 /path/to/infra/scripts/dev-start.sh
```

---

## Related Documentation

- [Architecture Documentation](../../docs/architecture.md)
- [Cost Strategy](../../docs/cost-strategy.md)
- [Terraform README](../terraform/envs/dev/README.md)

---

## Support

For issues or questions:
1. Check `dev-status.sh` output for resource state
2. Review AWS Console for resource details
3. Check Terraform state: `terraform show`
