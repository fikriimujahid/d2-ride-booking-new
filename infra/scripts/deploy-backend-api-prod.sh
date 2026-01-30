#!/usr/bin/env bash
set -euo pipefail

# PROD wrapper: backend-api (ASG) rolling deploy
export SERVICE_NAME="backend-api"
export PM2_APP_NAME="backend-api"
export ARTIFACT_NAMESPACE="apps/backend"
export NEEDS_RDS_CA="true"

bash infra/scripts/deploy-service-rolling.sh
