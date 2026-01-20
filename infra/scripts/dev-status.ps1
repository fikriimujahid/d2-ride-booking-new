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

function Invoke-AwsText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AwsArgs
    )

    try {
        $output = & aws @AwsArgs 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return $output
    } catch {
        return $null
    }
}

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AwsArgs
    )

    $text = Invoke-AwsText -AwsArgs $AwsArgs
    if (-not $text) {
        return $null
    }

    try {
        return $text | ConvertFrom-Json
    } catch {
        return $null
    }
}

Write-Host "========================================"
Write-Host "DEV Environment Status" -ForegroundColor Cyan
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
    $query = "DBInstances[?starts_with(DBInstanceIdentifier, '{0}-{1}')].DBInstanceIdentifier" -f $PROJECT_NAME, $ENVIRONMENT
    $instances = Invoke-AwsText -AwsArgs @(
        'rds', 'describe-db-instances',
        '--region', $AWS_REGION,
        '--query', $query,
        '--output', 'text'
    )
    
    if ($instances) {
        return $instances.Split()[0]
    }
    return $null
}

# ----------------------------------------
# RDS Status
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "RDS MySQL Status" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

$RDS_INSTANCE = Get-RDSInstance

if (-not $RDS_INSTANCE) {
    Write-Host "X No RDS instance found" -ForegroundColor Red
    Write-Host "  Run 'terraform apply' to create infrastructure"
} else {
    $RDS_INFO = Invoke-AwsJson -AwsArgs @(
        'rds', 'describe-db-instances',
        '--region', $AWS_REGION,
        '--db-instance-identifier', $RDS_INSTANCE,
        '--query', 'DBInstances[0]',
        '--output', 'json'
    )

    if (-not $RDS_INFO) {
        Write-Host "WARN: Unable to query RDS details (AWS credentials/permissions?)" -ForegroundColor Yellow
        Write-Host ""
        $RDS_STATUS = $null
        $RDS_INFO = $null
        return
    }
    
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
        "available" { "OK"; break }
        "stopped" { "STOP"; break }
        default { "..."; break }
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
        Write-Host "  Running - Incurring hourly charges" -ForegroundColor Green
        Write-Host "     Compute: ~`$0.017/hour (db.t3.micro)"
        Write-Host "     Storage: ~`$0.10/GB/month"
    } elseif ($RDS_STATUS -eq "stopped") {
        Write-Host "  Stopped - No compute charges" -ForegroundColor Green
        Write-Host "     Storage: ~`$0.10/GB/month (continues)"
    }
}

Write-Host ""

# ----------------------------------------
# EC2 Status
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "EC2 Instances Status" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

$EC2_INSTANCES = Invoke-AwsJson -AwsArgs @(
    'ec2', 'describe-instances',
    '--region', $AWS_REGION,
    '--filters',
    "Name=tag:Environment,Values=$ENVIRONMENT",
    "Name=tag:Project,Values=$PROJECT_NAME",
    '--query', 'Reservations[].Instances[]',
    '--output', 'json'
)

if (-not $EC2_INSTANCES -or $EC2_INSTANCES.Count -eq 0) {
    Write-Host "X No EC2 instances found" -ForegroundColor Red
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
            "running" { "OK"; break }
            "stopped" { "STOP"; break }
            default { "..."; break }
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
            Write-Host "  Running - ~`$0.0104/hour" -ForegroundColor Green
        } elseif ($STATE -eq "stopped") {
            Write-Host "  Stopped - No compute charges" -ForegroundColor Green
        }
        
        Write-Host ""
    }
}

# ----------------------------------------
# NAT Gateway Status
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "NAT Gateway Status" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

$NAT_GATEWAYS = Invoke-AwsJson -AwsArgs @(
    'ec2', 'describe-nat-gateways',
    '--region', $AWS_REGION,
    '--filter',
    "Name=tag:Environment,Values=$ENVIRONMENT",
    "Name=tag:Project,Values=$PROJECT_NAME",
    '--query', 'NatGateways[]',
    '--output', 'json'
)

if (-not $NAT_GATEWAYS -or $NAT_GATEWAYS.Count -eq 0) {
    Write-Host "  OK No NAT Gateway (saving ~`$0.045/hour)" -ForegroundColor Green
    Write-Host "    Enable in terraform.tfvars: enable_nat_gateway = true"
} else {
    foreach ($nat in $NAT_GATEWAYS) {
        $NAT_ID = $nat.NatGatewayId
        $NAT_STATE = $nat.State
        $NAT_PUBLIC_IP = $nat.NatGatewayAddresses[0].PublicIp
        
        Write-Host "  NAT Gateway ID:   $NAT_ID"
        Write-Host "  Status:           $NAT_STATE"
        Write-Host "  Public IP:        $NAT_PUBLIC_IP"
        Write-Host "  Cost:            ~`$0.045/hour + data transfer" -ForegroundColor Yellow
    }
}

Write-Host ""

# ----------------------------------------
# VPC Endpoints Status
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "VPC Endpoints (SSM) Status" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

$VPC_ENDPOINTS = Invoke-AwsJson -AwsArgs @(
    'ec2', 'describe-vpc-endpoints',
    '--region', $AWS_REGION,
    '--filters',
    "Name=tag:Environment,Values=$ENVIRONMENT",
    "Name=tag:Project,Values=$PROJECT_NAME",
    '--query', 'VpcEndpoints[]',
    '--output', 'json'
)

if (-not $VPC_ENDPOINTS -or $VPC_ENDPOINTS.Count -eq 0) {
    Write-Host "  OK No VPC Endpoints (saving ~`$0.03/hour)" -ForegroundColor Green
    Write-Host "    Note: SSM Session Manager requires NAT Gateway or VPC Endpoints"
    Write-Host "    Enable in terraform.tfvars: enable_ssm_vpc_endpoints = true"
} else {
    $endpointCount = 0
    foreach ($endpoint in $VPC_ENDPOINTS) {
        $endpointCount++
        $EP_ID = $endpoint.VpcEndpointId
        $EP_SERVICE = ($endpoint.ServiceName -split '\.')[-1]
        $EP_STATE = $endpoint.State
        
        Write-Host "  Endpoint ${endpointCount}:     $EP_SERVICE"
        Write-Host "    ID:             $EP_ID"
        Write-Host "    Status:         $EP_STATE"
    }
    $epCost = [math]::Round($endpointCount * 0.01, 3)
    Write-Host ""
    Write-Host "  Total Cost:      ~`$$epCost/hour ($endpointCount endpoints)" -ForegroundColor Yellow
}

Write-Host ""

# ----------------------------------------
# ALB Status
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "Application Load Balancer Status" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

$albQuery = "LoadBalancers[?contains(LoadBalancerName, '{0}') && contains(LoadBalancerName, '{1}')]" -f $PROJECT_NAME, $ENVIRONMENT
$ALBS = Invoke-AwsJson -AwsArgs @(
    'elbv2', 'describe-load-balancers',
    '--region', $AWS_REGION,
    '--query', $albQuery,
    '--output', 'json'
)

if (-not $ALBS -or $ALBS.Count -eq 0) {
    Write-Host "  OK No ALB (saving ~`$0.0225/hour)" -ForegroundColor Green
    Write-Host "    Enable in terraform.tfvars: enable_alb = true"
} else {
    foreach ($alb in $ALBS) {
        $ALB_NAME = $alb.LoadBalancerName
        $ALB_DNS = $alb.DNSName
        $ALB_STATE = $alb.State.Code
        
        Write-Host "  Load Balancer:    $ALB_NAME"
        Write-Host "  Status:           $ALB_STATE"
        Write-Host "  DNS Name:         $ALB_DNS"
        Write-Host "  Cost:            ~`$0.0225/hour + LCU charges" -ForegroundColor Yellow
    }
}

Write-Host ""

# ----------------------------------------
# Cost Summary
# ----------------------------------------
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "Cost Summary" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue

# Count running resources
$RUNNING_EC2 = ($EC2_INSTANCES | Where-Object { $_.State.Name -eq "running" }).Count
$RDS_RUNNING = if ($RDS_STATUS -eq "available") { 1 } else { 0 }
$NAT_RUNNING = if ($NAT_GATEWAYS -and $NAT_GATEWAYS.Count -gt 0) { $NAT_GATEWAYS.Count } else { 0 }
$VPC_EP_COUNT = if ($VPC_ENDPOINTS) { $VPC_ENDPOINTS.Count } else { 0 }
$ALB_RUNNING = if ($ALBS -and $ALBS.Count -gt 0) { $ALBS.Count } else { 0 }

$totalHourlyCost = 0

if ($RUNNING_EC2 -gt 0 -or $RDS_RUNNING -gt 0 -or $NAT_RUNNING -gt 0 -or $VPC_EP_COUNT -gt 0 -or $ALB_RUNNING -gt 0) {
    Write-Host "WARN: Resources are running and incurring charges" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Estimated hourly cost:"
    
    if ($RDS_RUNNING -gt 0) {
        $rdsCost = 0.017
        $totalHourlyCost += $rdsCost
        Write-Host "    - RDS db.t3.micro:     ~`$$rdsCost/hour"
    }
    
    if ($RUNNING_EC2 -gt 0) {
        $ec2Cost = [math]::Round($RUNNING_EC2 * 0.0104, 4)
        $totalHourlyCost += $ec2Cost
        Write-Host "    - EC2 t3.micro x${RUNNING_EC2}:    ~`$$ec2Cost/hour"
    }
    
    if ($NAT_RUNNING -gt 0) {
        $natCost = [math]::Round($NAT_RUNNING * 0.045, 3)
        $totalHourlyCost += $natCost
        Write-Host "    - NAT Gateway x${NAT_RUNNING}:     ~`$$natCost/hour"
    }
    
    if ($VPC_EP_COUNT -gt 0) {
        $epCost = [math]::Round($VPC_EP_COUNT * 0.01, 3)
        $totalHourlyCost += $epCost
        Write-Host "    - VPC Endpoints x${VPC_EP_COUNT}:  ~`$$epCost/hour"
    }
    
    if ($ALB_RUNNING -gt 0) {
        $albCost = [math]::Round($ALB_RUNNING * 0.0225, 4)
        $totalHourlyCost += $albCost
        Write-Host "    - ALB x${ALB_RUNNING}:             ~`$$albCost/hour"
    }
    
    $totalHourlyCost = [math]::Round($totalHourlyCost, 3)
    $dailyCost = [math]::Round($totalHourlyCost * 24, 2)
    $monthlyCost = [math]::Round($totalHourlyCost * 730, 2)
    
    Write-Host ""
    Write-Host "  --------------------------------------"
    Write-Host "  TOTAL:                 ~`$$totalHourlyCost/hour" -ForegroundColor Cyan
    Write-Host "  Estimated daily:       ~`$$dailyCost/day" -ForegroundColor Cyan
    Write-Host "  Estimated monthly:     ~`$$monthlyCost/month" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  To stop compute resources:" -ForegroundColor Yellow
    Write-Host "    .\infra\scripts\dev-stop.ps1"
    Write-Host ""
    Write-Host "  To disable infrastructure components:" -ForegroundColor Yellow
    Write-Host "    Edit infra\terraform\envs\dev\terraform.tfvars"
    Write-Host "    Set enable_* variables to false"
    Write-Host "    Run: terraform apply"
} else {
    Write-Host "OK All compute resources are stopped" -ForegroundColor Green
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
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "Quick Actions" -ForegroundColor Blue
Write-Host "----------------------------------------" -ForegroundColor Blue
Write-Host "  Start DEV:        .\infra\scripts\dev-start.ps1"
Write-Host "  Stop DEV:         .\infra\scripts\dev-stop.ps1"
Write-Host "  Check Status:     .\infra\scripts\dev-status.ps1"
Write-Host ""
Write-Host "  Apply Changes:    cd infra\terraform\envs\dev; terraform apply"
Write-Host "  Destroy All:      cd infra\terraform\envs\dev; terraform destroy"
Write-Host ""
Write-Host "========================================"
