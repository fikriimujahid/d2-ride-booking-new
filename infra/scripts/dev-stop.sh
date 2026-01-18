#!/bin/bash
# ========================================
# DEV Environment - Stop Script
# ========================================
# Purpose: Stop RDS and EC2 instances to minimize costs when not in use
# Cost Impact: Eliminates hourly compute charges (storage charges continue)
# Usage: ./infra/scripts/dev-stop.sh
#
# IMPORTANT:
# - This does NOT destroy infrastructure (Terraform state unchanged)
# - This ONLY stops running instances
# - Use dev-start.sh to resume work
# - For full cleanup, use 'terraform destroy'

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
echo "⏸️  Stopping DEV Environment"
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
            "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text
}

# ----------------------------------------
# Stop RDS Instance
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
    
    if [ "$RDS_STATUS" = "available" ]; then
        echo -e "${GREEN}⏸️  Stopping RDS instance...${NC}"
        aws rds stop-db-instance \
            --region "${AWS_REGION}" \
            --db-instance-identifier "${RDS_INSTANCE}"
        echo "   Stopped (will take 1-2 minutes to complete)"
        echo ""
        echo -e "${GREEN}   💰 Cost savings: ~\$0.017/hour (db.t3.micro)${NC}"
        echo "      Storage charges continue: ~\$0.10/GB/month"
    elif [ "$RDS_STATUS" = "stopped" ]; then
        echo -e "${GREEN}✓ RDS instance is already stopped${NC}"
    else
        echo -e "${YELLOW}⚠️  RDS instance is in '${RDS_STATUS}' state${NC}"
        echo "   Wait for current operation to complete"
    fi
fi

echo ""

# ----------------------------------------
# Stop EC2 Instances
# ----------------------------------------
echo -e "${BLUE}🖥️  Checking EC2 instances...${NC}"
EC2_INSTANCES=$(get_ec2_instances)

if [ -z "$EC2_INSTANCES" ]; then
    echo -e "${YELLOW}⚠️  No running EC2 instances found${NC}"
    echo "   Either instances are already stopped or not created yet"
else
    echo "   Found running instances: ${EC2_INSTANCES}"
    echo -e "${GREEN}⏸️  Stopping EC2 instances...${NC}"
    aws ec2 stop-instances \
        --region "${AWS_REGION}" \
        --instance-ids ${EC2_INSTANCES}
    echo "   Stopped (will take 1-2 minutes to complete)"
    echo ""
    echo -e "${GREEN}   💰 Cost savings: ~\$0.0104/hour per t3.micro${NC}"
    echo "      EBS storage charges continue: ~\$0.08/GB/month"
fi

echo ""

# ----------------------------------------
# Summary
# ----------------------------------------
echo "========================================"
echo -e "${GREEN}✓ DEV Environment Stop Initiated${NC}"
echo "========================================"
echo ""
echo "What was stopped:"
echo "  • RDS MySQL instance (compute charges eliminated)"
echo "  • EC2 instances (compute charges eliminated)"
echo ""
echo "What continues to incur charges:"
echo "  • RDS storage (~\$0.10/GB/month)"
echo "  • EBS volumes (~\$0.08/GB/month)"
echo "  • VPC components (NAT Gateway if enabled)"
echo ""
echo "To resume work:"
echo "  Run: ./infra/scripts/dev-start.sh"
echo ""
echo "To fully destroy infrastructure:"
echo "  cd infra/terraform/envs/dev"
echo "  terraform destroy"
echo ""
