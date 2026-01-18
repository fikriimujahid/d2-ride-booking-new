#!/bin/bash
# ========================================
# DEV Environment - Start Script
# ========================================
# Purpose: Start RDS and EC2 instances to resume DEV work
# Cost Impact: Resumes hourly charges for compute resources
# Usage: ./infra/scripts/dev-start.sh

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
NC='\033[0m' # No Color

echo "========================================"
echo "🚀 Starting DEV Environment"
echo "========================================"
echo ""
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"
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
# Function: Get EC2 Instance IDs
# ----------------------------------------
get_ec2_instances() {
    aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters \
            "Name=tag:Environment,Values=${ENVIRONMENT}" \
            "Name=tag:Project,Values=${PROJECT_NAME}" \
            "Name=instance-state-name,Values=stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text
}

# ----------------------------------------
# Start RDS Instance
# ----------------------------------------
echo -e "${BLUE}📊 Checking RDS instances...${NC}"
RDS_INSTANCE=$(get_rds_instance)

if [ -z "$RDS_INSTANCE" ]; then
    echo -e "${YELLOW}⚠️  No RDS instance found${NC}"
    echo "   Run 'terraform apply' to create infrastructure first"
else
    RDS_STATUS=$(aws rds describe-db-instances \
        --region "${AWS_REGION}" \
        --db-instance-identifier "${RDS_INSTANCE}" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text)
    
    echo "   RDS Instance: ${RDS_INSTANCE}"
    echo "   Current Status: ${RDS_STATUS}"
    
    if [ "$RDS_STATUS" = "stopped" ]; then
        echo -e "${GREEN}▶️  Starting RDS instance...${NC}"
        aws rds start-db-instance \
            --region "${AWS_REGION}" \
            --db-instance-identifier "${RDS_INSTANCE}"
        echo "   Started (will take 2-5 minutes to become available)"
    elif [ "$RDS_STATUS" = "available" ]; then
        echo -e "${GREEN}✓ RDS instance is already running${NC}"
    else
        echo -e "${YELLOW}⚠️  RDS instance is in '${RDS_STATUS}' state${NC}"
        echo "   Wait for current operation to complete"
    fi
fi

echo ""

# ----------------------------------------
# Start EC2 Instances
# ----------------------------------------
echo -e "${BLUE}🖥️  Checking EC2 instances...${NC}"
EC2_INSTANCES=$(get_ec2_instances)

if [ -z "$EC2_INSTANCES" ]; then
    echo -e "${YELLOW}⚠️  No stopped EC2 instances found${NC}"
    echo "   Either instances are already running or not created yet"
else
    echo "   Found stopped instances: ${EC2_INSTANCES}"
    echo -e "${GREEN}▶️  Starting EC2 instances...${NC}"
    aws ec2 start-instances \
        --region "${AWS_REGION}" \
        --instance-ids ${EC2_INSTANCES}
    echo "   Started (will take 1-2 minutes to become running)"
fi

echo ""

# ----------------------------------------
# Summary
# ----------------------------------------
echo "========================================"
echo -e "${GREEN}✓ DEV Environment Start Initiated${NC}"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Wait 2-5 minutes for resources to start"
echo "  2. Run: ./infra/scripts/dev-status.sh"
echo "  3. Access backend API via SSM Session Manager"
echo ""
echo "Cost reminder:"
echo "  💰 RDS and EC2 charges resume while running"
echo "  💰 Run './infra/scripts/dev-stop.sh' when done"
echo ""
