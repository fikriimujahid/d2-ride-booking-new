#!/bin/bash
# ========================================
# DEV Environment - Status Script
# ========================================
# Purpose: Show current status of RDS and EC2 instances
# Usage: ./infra/scripts/dev-status.sh

set -e  # Exit on error

# Configuration
ENVIRONMENT="dev"
PROJECT_NAME="d2-ride-booking"
AWS_REGION="ap-southeast-1"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "========================================"
echo "📊 DEV Environment Status"
echo "========================================"
echo ""
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"
echo "Timestamp: $(date)"
echo ""

# ----------------------------------------
# Function: Get RDS Instance Identifier
# ----------------------------------------
get_rds_instance() {
    aws rds describe-db-instances \
        --region "${AWS_REGION}" \
        --query "DBInstances[?starts_with(DBInstanceIdentifier, '${PROJECT_NAME}-${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text | head -n 1
}

# ----------------------------------------
# RDS Status
# ----------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📊 RDS MySQL Status${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

RDS_INSTANCE=$(get_rds_instance)

if [ -z "$RDS_INSTANCE" ]; then
    echo -e "${RED}✗ No RDS instance found${NC}"
    echo "  Run 'terraform apply' to create infrastructure"
else
    RDS_INFO=$(aws rds describe-db-instances \
        --region "${AWS_REGION}" \
        --db-instance-identifier "${RDS_INSTANCE}" \
        --query "DBInstances[0]" \
        --output json)
    
    RDS_STATUS=$(echo "$RDS_INFO" | jq -r '.DBInstanceStatus')
    RDS_ENDPOINT=$(echo "$RDS_INFO" | jq -r '.Endpoint.Address // "N/A"')
    RDS_PORT=$(echo "$RDS_INFO" | jq -r '.Endpoint.Port // "N/A"')
    RDS_ENGINE=$(echo "$RDS_INFO" | jq -r '.Engine')
    RDS_ENGINE_VERSION=$(echo "$RDS_INFO" | jq -r '.EngineVersion')
    RDS_INSTANCE_CLASS=$(echo "$RDS_INFO" | jq -r '.DBInstanceClass')
    RDS_STORAGE=$(echo "$RDS_INFO" | jq -r '.AllocatedStorage')
    RDS_IAM_AUTH=$(echo "$RDS_INFO" | jq -r '.IAMDatabaseAuthenticationEnabled')
    RDS_DB_NAME=$(echo "$RDS_INFO" | jq -r '.DBName // "N/A"')
    
    # Status color coding
    if [ "$RDS_STATUS" = "available" ]; then
        STATUS_COLOR="${GREEN}"
        STATUS_ICON="✓"
    elif [ "$RDS_STATUS" = "stopped" ]; then
        STATUS_COLOR="${YELLOW}"
        STATUS_ICON="⏸"
    else
        STATUS_COLOR="${CYAN}"
        STATUS_ICON="⚙"
    fi
    
    echo -e "  Instance ID:      ${RDS_INSTANCE}"
    echo -e "  Status:           ${STATUS_COLOR}${STATUS_ICON} ${RDS_STATUS}${NC}"
    echo -e "  Endpoint:         ${RDS_ENDPOINT}:${RDS_PORT}"
    echo -e "  Database:         ${RDS_DB_NAME}"
    echo -e "  Engine:           ${RDS_ENGINE} ${RDS_ENGINE_VERSION}"
    echo -e "  Instance Class:   ${RDS_INSTANCE_CLASS}"
    echo -e "  Storage:          ${RDS_STORAGE} GB"
    echo -e "  IAM Auth:         ${RDS_IAM_AUTH}"
    
    # Cost information
    echo ""
    if [ "$RDS_STATUS" = "available" ]; then
        echo -e "  ${GREEN}💰 Running - Incurring hourly charges${NC}"
        echo "     Compute: ~\$0.017/hour (db.t3.micro)"
        echo "     Storage: ~\$0.10/GB/month"
    elif [ "$RDS_STATUS" = "stopped" ]; then
        echo -e "  ${GREEN}💰 Stopped - No compute charges${NC}"
        echo "     Storage: ~\$0.10/GB/month (continues)"
    fi
fi

echo ""

# ----------------------------------------
# EC2 Status
# ----------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🖥️  EC2 Instances Status${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

EC2_INSTANCES=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
        "Name=tag:Environment,Values=${ENVIRONMENT}" \
        "Name=tag:Project,Values=${PROJECT_NAME}" \
    --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key=='Name'].Value|[0],PrivateIpAddress]" \
    --output text)

if [ -z "$EC2_INSTANCES" ]; then
    echo -e "${RED}✗ No EC2 instances found${NC}"
    echo "  Run 'terraform apply' to create infrastructure"
else
    echo "$EC2_INSTANCES" | while IFS=$'\t' read -r INSTANCE_ID INSTANCE_TYPE STATE NAME PRIVATE_IP; do
        # Status color coding
        if [ "$STATE" = "running" ]; then
            STATUS_COLOR="${GREEN}"
            STATUS_ICON="✓"
        elif [ "$STATE" = "stopped" ]; then
            STATUS_COLOR="${YELLOW}"
            STATUS_ICON="⏸"
        else
            STATUS_COLOR="${CYAN}"
            STATUS_ICON="⚙"
        fi
        
        echo -e "  Instance ID:      ${INSTANCE_ID}"
        echo -e "  Name:             ${NAME}"
        echo -e "  Status:           ${STATUS_COLOR}${STATUS_ICON} ${STATE}${NC}"
        echo -e "  Type:             ${INSTANCE_TYPE}"
        echo -e "  Private IP:       ${PRIVATE_IP}"
        
        if [ "$STATE" = "running" ]; then
            echo -e "  ${GREEN}💰 Running - ~\$0.0104/hour${NC}"
        elif [ "$STATE" = "stopped" ]; then
            echo -e "  ${GREEN}💰 Stopped - No compute charges${NC}"
        fi
        
        echo ""
    done
fi

# ----------------------------------------
# Cost Summary
# ----------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}💰 Cost Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Count running resources
RUNNING_EC2=$(echo "$EC2_INSTANCES" | grep -c "running" || echo "0")
RDS_RUNNING=0
if [ "$RDS_STATUS" = "available" ]; then
    RDS_RUNNING=1
fi

if [ "$RUNNING_EC2" -gt 0 ] || [ "$RDS_RUNNING" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Resources are running and incurring charges${NC}"
    echo ""
    echo "  Estimated hourly cost:"
    if [ "$RDS_RUNNING" -gt 0 ]; then
        echo "    • RDS db.t3.micro:  ~\$0.017/hour"
    fi
    if [ "$RUNNING_EC2" -gt 0 ]; then
        echo "    • EC2 t3.micro x${RUNNING_EC2}: ~\$$(echo "$RUNNING_EC2 * 0.0104" | bc)/hour"
    fi
    echo ""
    echo -e "${YELLOW}  To stop resources and save costs:${NC}"
    echo "    ./infra/scripts/dev-stop.sh"
else
    echo -e "${GREEN}✓ All compute resources are stopped${NC}"
    echo ""
    echo "  No hourly charges (storage charges continue)"
    echo ""
    echo "  To resume work:"
    echo "    ./infra/scripts/dev-start.sh"
fi

echo ""

# ----------------------------------------
# Quick Actions
# ----------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}⚡ Quick Actions${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Start DEV:        ./infra/scripts/dev-start.sh"
echo "  Stop DEV:         ./infra/scripts/dev-stop.sh"
echo "  Check Status:     ./infra/scripts/dev-status.sh"
echo ""
echo "  Apply Changes:    cd infra/terraform/envs/dev && terraform apply"
echo "  Destroy All:      cd infra/terraform/envs/dev && terraform destroy"
echo ""
echo "========================================"
