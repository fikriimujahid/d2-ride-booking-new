# ========================================
# DEV Environment - Stop Script (PowerShell)
# ========================================
# Purpose: Stop RDS and EC2 instances to minimize costs when not in use
# Cost Impact: Eliminates hourly compute charges (storage charges continue)
# Usage: .\infra\scripts\dev-stop.ps1
#
# IMPORTANT:
# - This does NOT destroy infrastructure (Terraform state unchanged)
# - This ONLY stops running instances
# - Use dev-start.ps1 to resume work
# - For full cleanup, use 'terraform destroy'

$ErrorActionPreference = "Stop"

# Configuration
$ENVIRONMENT = "dev"
$PROJECT_NAME = "d2-ride-booking"
$AWS_REGION = "ap-southeast-1"

Write-Host "========================================"
Write-Host "⏸️  Stopping DEV Environment" -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""
Write-Host "Environment: $ENVIRONMENT"
Write-Host "Region: $AWS_REGION"
Write-Host ""

# ----------------------------------------
# Function: Get RDS Instance Identifier
# ----------------------------------------
function Get-RDSInstance {
    $instances = aws rds describe-db-instances `
        --region $AWS_REGION `
        --query "DBInstances[?starts_with(DBInstanceIdentifier, '$PROJECT_NAME-$ENVIRONMENT')].DBInstanceIdentifier" `
        --output text
    
    if ($instances) {
        return $instances.Split()[0]
    }
    return $null
}

# ----------------------------------------
# Function: Get EC2 Instance IDs
# ----------------------------------------
function Get-EC2Instances {
    $instances = aws ec2 describe-instances `
        --region $AWS_REGION `
        --filters `
            "Name=tag:Environment,Values=$ENVIRONMENT" `
            "Name=tag:Project,Values=$PROJECT_NAME" `
            "Name=instance-state-name,Values=running" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text
    
    return $instances
}

# ----------------------------------------
# Stop RDS Instance
# ----------------------------------------
Write-Host "📊 Checking RDS instances..." -ForegroundColor Blue
$RDS_INSTANCE = Get-RDSInstance

if (-not $RDS_INSTANCE) {
    Write-Host "⚠️  No RDS instance found" -ForegroundColor Yellow
    Write-Host "   Run 'terraform apply' to create infrastructure first"
} else {
    $RDS_STATUS = aws rds describe-db-instances `
        --region $AWS_REGION `
        --db-instance-identifier $RDS_INSTANCE `
        --query "DBInstances[0].DBInstanceStatus" `
        --output text
    
    Write-Host "   RDS Instance: $RDS_INSTANCE"
    Write-Host "   Current Status: $RDS_STATUS"
    
    if ($RDS_STATUS -eq "available") {
        Write-Host "⏸️  Stopping RDS instance..." -ForegroundColor Green
        aws rds stop-db-instance `
            --region $AWS_REGION `
            --db-instance-identifier $RDS_INSTANCE | Out-Null
        Write-Host "   Stopped (will take 1-2 minutes to complete)"
        Write-Host ""
        Write-Host "   💰 Cost savings: ~`$0.017/hour (db.t3.micro)" -ForegroundColor Green
        Write-Host "      Storage charges continue: ~`$0.10/GB/month"
    } elseif ($RDS_STATUS -eq "stopped") {
        Write-Host "✓ RDS instance is already stopped" -ForegroundColor Green
    } else {
        Write-Host "⚠️  RDS instance is in '$RDS_STATUS' state" -ForegroundColor Yellow
        Write-Host "   Wait for current operation to complete"
    }
}

Write-Host ""

# ----------------------------------------
# Stop EC2 Instances
# ----------------------------------------
Write-Host "🖥️  Checking EC2 instances..." -ForegroundColor Blue
$EC2_INSTANCES = Get-EC2Instances

if (-not $EC2_INSTANCES) {
    Write-Host "⚠️  No running EC2 instances found" -ForegroundColor Yellow
    Write-Host "   Either instances are already stopped or not created yet"
} else {
    Write-Host "   Found running instances: $EC2_INSTANCES"
    Write-Host "⏸️  Stopping EC2 instances..." -ForegroundColor Green
    $instanceIds = $EC2_INSTANCES -split '\s+'
    aws ec2 stop-instances `
        --region $AWS_REGION `
        --instance-ids $instanceIds | Out-Null
    Write-Host "   Stopped (will take 1-2 minutes to complete)"
    Write-Host ""
    Write-Host "   💰 Cost savings: ~`$0.0104/hour per t3.micro" -ForegroundColor Green
    Write-Host "      EBS storage charges continue: ~`$0.08/GB/month"
}

Write-Host ""

# ----------------------------------------
# Summary
# ----------------------------------------
Write-Host "========================================"
Write-Host "✓ DEV Environment Stop Initiated" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
Write-Host "What was stopped:"
Write-Host "  • RDS MySQL instance (compute charges eliminated)"
Write-Host "  • EC2 instances (compute charges eliminated)"
Write-Host ""
Write-Host "What continues to incur charges:"
Write-Host "  • RDS storage (~`$0.10/GB/month)"
Write-Host "  • EBS volumes (~`$0.08/GB/month)"
Write-Host "  • VPC components (NAT Gateway if enabled)"
Write-Host ""
Write-Host "To resume work:"
Write-Host "  Run: .\infra\scripts\dev-start.ps1"
Write-Host ""
Write-Host "To fully destroy infrastructure:"
Write-Host "  cd infra\terraform\envs\dev"
Write-Host "  terraform destroy"
Write-Host ""
