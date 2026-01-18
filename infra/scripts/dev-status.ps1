# ========================================
# DEV Environment - Status Script (PowerShell)
# ========================================
# Purpose: Show current status of RDS and EC2 instances
# Usage: .\infra\scripts\dev-status.ps1

$ErrorActionPreference = "Stop"

# Configuration
$ENVIRONMENT = "dev"
$PROJECT_NAME = "d2-ride-booking"
$AWS_REGION = "ap-southeast-1"

Write-Host "========================================"
Write-Host "📊 DEV Environment Status" -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""
Write-Host "Environment: $ENVIRONMENT"
Write-Host "Region: $AWS_REGION"
Write-Host "Timestamp: $(Get-Date)"
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
# RDS Status
# ----------------------------------------
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "📊 RDS MySQL Status" -ForegroundColor Blue
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

$RDS_INSTANCE = Get-RDSInstance

if (-not $RDS_INSTANCE) {
    Write-Host "✗ No RDS instance found" -ForegroundColor Red
    Write-Host "  Run 'terraform apply' to create infrastructure"
} else {
    $RDS_INFO = aws rds describe-db-instances `
        --region $AWS_REGION `
        --db-instance-identifier $RDS_INSTANCE `
        --query "DBInstances[0]" `
        --output json | ConvertFrom-Json
    
    $RDS_STATUS = $RDS_INFO.DBInstanceStatus
    $RDS_ENDPOINT = if ($RDS_INFO.Endpoint.Address) { $RDS_INFO.Endpoint.Address } else { "N/A" }
    $RDS_PORT = if ($RDS_INFO.Endpoint.Port) { $RDS_INFO.Endpoint.Port } else { "N/A" }
    $RDS_ENGINE = $RDS_INFO.Engine
    $RDS_ENGINE_VERSION = $RDS_INFO.EngineVersion
    $RDS_INSTANCE_CLASS = $RDS_INFO.DBInstanceClass
    $RDS_STORAGE = $RDS_INFO.AllocatedStorage
    $RDS_IAM_AUTH = $RDS_INFO.IAMDatabaseAuthenticationEnabled
    $RDS_DB_NAME = if ($RDS_INFO.DBName) { $RDS_INFO.DBName } else { "N/A" }
    
    # Status display
    $statusIcon = switch ($RDS_STATUS) {
        "available" { "✓"; break }
        "stopped" { "⏸"; break }
        default { "⚙"; break }
    }
    
    $statusColor = switch ($RDS_STATUS) {
        "available" { "Green"; break }
        "stopped" { "Yellow"; break }
        default { "Cyan"; break }
    }
    
    Write-Host "  Instance ID:      $RDS_INSTANCE"
    Write-Host "  Status:           " -NoNewline
    Write-Host "$statusIcon $RDS_STATUS" -ForegroundColor $statusColor
    Write-Host "  Endpoint:         ${RDS_ENDPOINT}:${RDS_PORT}"
    Write-Host "  Database:         $RDS_DB_NAME"
    Write-Host "  Engine:           $RDS_ENGINE $RDS_ENGINE_VERSION"
    Write-Host "  Instance Class:   $RDS_INSTANCE_CLASS"
    Write-Host "  Storage:          $RDS_STORAGE GB"
    Write-Host "  IAM Auth:         $RDS_IAM_AUTH"
    
    # Cost information
    Write-Host ""
    if ($RDS_STATUS -eq "available") {
        Write-Host "  💰 Running - Incurring hourly charges" -ForegroundColor Green
        Write-Host "     Compute: ~`$0.017/hour (db.t3.micro)"
        Write-Host "     Storage: ~`$0.10/GB/month"
    } elseif ($RDS_STATUS -eq "stopped") {
        Write-Host "  💰 Stopped - No compute charges" -ForegroundColor Green
        Write-Host "     Storage: ~`$0.10/GB/month (continues)"
    }
}

Write-Host ""

# ----------------------------------------
# EC2 Status
# ----------------------------------------
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "🖥️  EC2 Instances Status" -ForegroundColor Blue
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

$EC2_INSTANCES = aws ec2 describe-instances `
    --region $AWS_REGION `
    --filters `
        "Name=tag:Environment,Values=$ENVIRONMENT" `
        "Name=tag:Project,Values=$PROJECT_NAME" `
    --query "Reservations[].Instances[]" `
    --output json | ConvertFrom-Json

if (-not $EC2_INSTANCES -or $EC2_INSTANCES.Count -eq 0) {
    Write-Host "✗ No EC2 instances found" -ForegroundColor Red
    Write-Host "  Run 'terraform apply' to create infrastructure"
} else {
    $runningCount = 0
    foreach ($instance in $EC2_INSTANCES) {
        $INSTANCE_ID = $instance.InstanceId
        $INSTANCE_TYPE = $instance.InstanceType
        $STATE = $instance.State.Name
        $NAME = ($instance.Tags | Where-Object { $_.Key -eq "Name" }).Value
        $PRIVATE_IP = $instance.PrivateIpAddress
        
        if ($STATE -eq "running") { $runningCount++ }
        
        # Status display
        $statusIcon = switch ($STATE) {
            "running" { "✓"; break }
            "stopped" { "⏸"; break }
            default { "⚙"; break }
        }
        
        $statusColor = switch ($STATE) {
            "running" { "Green"; break }
            "stopped" { "Yellow"; break }
            default { "Cyan"; break }
        }
        
        Write-Host "  Instance ID:      $INSTANCE_ID"
        Write-Host "  Name:             $NAME"
        Write-Host "  Status:           " -NoNewline
        Write-Host "$statusIcon $STATE" -ForegroundColor $statusColor
        Write-Host "  Type:             $INSTANCE_TYPE"
        Write-Host "  Private IP:       $PRIVATE_IP"
        
        if ($STATE -eq "running") {
            Write-Host "  💰 Running - ~`$0.0104/hour" -ForegroundColor Green
        } elseif ($STATE -eq "stopped") {
            Write-Host "  💰 Stopped - No compute charges" -ForegroundColor Green
        }
        
        Write-Host ""
    }
}

# ----------------------------------------
# Cost Summary
# ----------------------------------------
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "💰 Cost Summary" -ForegroundColor Blue
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

# Count running resources
$RUNNING_EC2 = ($EC2_INSTANCES | Where-Object { $_.State.Name -eq "running" }).Count
$RDS_RUNNING = if ($RDS_STATUS -eq "available") { 1 } else { 0 }

if ($RUNNING_EC2 -gt 0 -or $RDS_RUNNING -gt 0) {
    Write-Host "⚠️  Resources are running and incurring charges" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Estimated hourly cost:"
    if ($RDS_RUNNING -gt 0) {
        Write-Host "    • RDS db.t3.micro:  ~`$0.017/hour"
    }
    if ($RUNNING_EC2 -gt 0) {
        $ec2Cost = [math]::Round($RUNNING_EC2 * 0.0104, 4)
        Write-Host "    • EC2 t3.micro x${RUNNING_EC2}: ~`$$ec2Cost/hour"
    }
    Write-Host ""
    Write-Host "  To stop resources and save costs:" -ForegroundColor Yellow
    Write-Host "    .\infra\scripts\dev-stop.ps1"
} else {
    Write-Host "✓ All compute resources are stopped" -ForegroundColor Green
    Write-Host ""
    Write-Host "  No hourly charges (storage charges continue)"
    Write-Host ""
    Write-Host "  To resume work:"
    Write-Host "    .\infra\scripts\dev-start.ps1"
}

Write-Host ""

# ----------------------------------------
# Quick Actions
# ----------------------------------------
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "⚡ Quick Actions" -ForegroundColor Blue
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  Start DEV:        .\infra\scripts\dev-start.ps1"
Write-Host "  Stop DEV:         .\infra\scripts\dev-stop.ps1"
Write-Host "  Check Status:     .\infra\scripts\dev-status.ps1"
Write-Host ""
Write-Host "  Apply Changes:    cd infra\terraform\envs\dev; terraform apply"
Write-Host "  Destroy All:      cd infra\terraform\envs\dev; terraform destroy"
Write-Host ""
Write-Host "========================================"
