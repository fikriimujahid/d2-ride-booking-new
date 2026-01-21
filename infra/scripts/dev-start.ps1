# ========================================
# DEV Environment - Start Script (PowerShell)
# ========================================
# Purpose: Start RDS and EC2 instances to resume DEV work
# Cost Impact: Resumes hourly charges for compute resources
# Usage: .\infra\scripts\dev-start.ps1

$ErrorActionPreference = "Stop"

# Configuration
$ENVIRONMENT = "dev"
$PROJECT_NAME = "d2-ride-booking"
$AWS_REGION = "ap-southeast-1"

Write-Host "========================================"
Write-Host "🚀 Starting DEV Environment" -ForegroundColor Cyan
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
            "Name=instance-state-name,Values=stopped" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text
    
    return $instances
}

# ----------------------------------------
# Start RDS Instance
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
    
    if ($RDS_STATUS -eq "stopped") {
        Write-Host "▶️  Starting RDS instance..." -ForegroundColor Green
        aws rds start-db-instance `
            --region $AWS_REGION `
            --db-instance-identifier $RDS_INSTANCE | Out-Null
        Write-Host "   Started (will take 2-5 minutes to become available)"
    } elseif ($RDS_STATUS -eq "available") {
        Write-Host "✓ RDS instance is already running" -ForegroundColor Green
    } else {
        Write-Host "⚠️  RDS instance is in '$RDS_STATUS' state" -ForegroundColor Yellow
        Write-Host "   Wait for current operation to complete"
    }
}

Write-Host ""

# ----------------------------------------
# Start EC2 Instances
# ----------------------------------------
Write-Host "🖥️  Checking EC2 instances..." -ForegroundColor Blue
$EC2_INSTANCES = Get-EC2Instances

if (-not $EC2_INSTANCES) {
    Write-Host "⚠️  No stopped EC2 instances found" -ForegroundColor Yellow
    Write-Host "   Either instances are already running or not created yet"
} else {
    Write-Host "   Found stopped instances: $EC2_INSTANCES"
    Write-Host "▶️  Starting EC2 instances..." -ForegroundColor Green
    $instanceIds = $EC2_INSTANCES -split '\s+'
    aws ec2 start-instances `
        --region $AWS_REGION `
        --instance-ids $instanceIds | Out-Null
    Write-Host "   Started (will take 1-2 minutes to become running)"
}

Write-Host ""

# ----------------------------------------
# Summary
# ----------------------------------------
Write-Host "========================================"
Write-Host "✓ DEV Environment Start Initiated" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Wait 2-5 minutes for resources to start"
Write-Host "  2. Run: .\infra\scripts\dev-status.ps1"
Write-Host "  3. Access backend API via SSM Session Manager:"
Write-Host "     aws ssm start-session --target <instance-id>"
Write-Host ""
Write-Host "Cost reminder:"
Write-Host "  💰 RDS and EC2 charges resume while running"
Write-Host "  💰 Additional charges: NAT Gateway, VPC Endpoints, ALB (if enabled)"
Write-Host "  💰 Run '.\infra\scripts\dev-stop.ps1' when done"
Write-Host ""
Write-Host "View full infrastructure status:"
Write-Host "  .\infra\scripts\dev-status.ps1"
Write-Host ""
