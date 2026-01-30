#!/usr/bin/env bash
set -euo pipefail

# PROD wrapper: web-driver (ASG) rolling deploy
export SERVICE_NAME="web-driver"
export PM2_APP_NAME="web-driver"
export ARTIFACT_NAMESPACE="apps/frontend"
export NEEDS_RDS_CA="false"

bash infra/scripts/deploy-service-rolling.sh
