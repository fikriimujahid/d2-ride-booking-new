#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DEPLOY WEB-DRIVER (DEV) via S3 + SSM (NO SSH)
# ==============================================================================
# Final flow:
#  1) CI builds immutable artifact
#  2) CI uploads artifact to S3
#  3) CI triggers this script (or equivalent inline logic)
#  4) Script invokes SSM Run Command on tagged EC2 instances
#  5) EC2 pulls artifact from S3, swaps symlink, restarts PM2 as appuser
#
# Validation checklist:
# - EC2 boots without crashing
# - App does NOT start before deployment
# - Deployment is repeatable
# - PM2 survives reboot
# - Logs visible in CloudWatch (/dev/web-driver)
# - SSM Run Command reliable
# - web-driver stays up after deploy

: "${AWS_REGION:?Set AWS_REGION}"
: "${S3_BUCKET_ARTIFACT:?Set S3_BUCKET_ARTIFACT}"
: "${RELEASE_ID:?Set RELEASE_ID (e.g. 20260124-123000)}"
: "${ENVIRONMENT:?Set ENVIRONMENT (e.g. dev)}"
: "${PROJECT_NAME:?Set PROJECT_NAME (e.g. d2-ride-booking)}"

SERVICE_NAME="web-driver"
PM2_APP_NAME="web-driver"
APP_DIR="/opt/apps/${SERVICE_NAME}"

S3_KEY_TGZ="apps/frontend/${SERVICE_NAME}-${RELEASE_ID}.tar.gz"
S3_KEY_SHA="apps/frontend/${SERVICE_NAME}-${RELEASE_ID}.sha256"

PARAM_PATH="/${ENVIRONMENT}/${PROJECT_NAME}/${SERVICE_NAME}"

python3 - <<'PY' > /tmp/ssm-commands-web-driver.json
import json
import os

AWS_REGION = os.environ["AWS_REGION"]
SERVICE_NAME = "web-driver"
PM2_APP_NAME = "web-driver"
APP_DIR = f"/opt/apps/{SERVICE_NAME}"
RELEASE_ID = os.environ["RELEASE_ID"]
S3_BUCKET = os.environ["S3_BUCKET_ARTIFACT"]
S3_KEY_TGZ = f"apps/frontend/{SERVICE_NAME}-{RELEASE_ID}.tar.gz"
S3_KEY_SHA = f"apps/frontend/{SERVICE_NAME}-{RELEASE_ID}.sha256"
PARAM_PATH = f"/{os.environ['ENVIRONMENT']}/{os.environ['PROJECT_NAME']}/{SERVICE_NAME}"

commands = [
  "set -euo pipefail",
  f"export AWS_REGION={AWS_REGION}",
  f"SERVICE_NAME={SERVICE_NAME}",
  f"PM2_APP_NAME={PM2_APP_NAME}",
  f"APP_DIR={APP_DIR}",
  f"RELEASE_ID={RELEASE_ID}",
  f"S3_BUCKET={S3_BUCKET}",
  f"S3_KEY_TGZ={S3_KEY_TGZ}",
  f"S3_KEY_SHA={S3_KEY_SHA}",
  f"PARAM_PATH={PARAM_PATH}",

  "install -d -m 0755 -o appuser -g appuser ${APP_DIR} ${APP_DIR}/releases",
  "cd /tmp",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_TGZ} ${SERVICE_NAME}-${RELEASE_ID}.tar.gz",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_SHA} ${SERVICE_NAME}-${RELEASE_ID}.sha256",
  "sha256sum -c ${SERVICE_NAME}-${RELEASE_ID}.sha256",

  "mkdir -p ${APP_DIR}/releases/${RELEASE_ID}",
  "tar -xzf ${SERVICE_NAME}-${RELEASE_ID}.tar.gz -C ${APP_DIR}/releases/${RELEASE_ID}",
  "chown -R appuser:appuser ${APP_DIR}/releases/${RELEASE_ID}",

  "ln -sfn ${APP_DIR}/releases/${RELEASE_ID} ${APP_DIR}/current",

  "# Load runtime config from SSM Parameter Store (no .env files)",
  "if ! command -v python3 >/dev/null 2>&1; then dnf -y install python3; fi",
  "ENV_EXPORT_FILE=$(mktemp /tmp/${SERVICE_NAME}-env.XXXXXX)",
  "python3 - <<'PY' > \"$ENV_EXPORT_FILE\"\nimport json, os, shlex, subprocess\npath=os.environ['PARAM_PATH']\nout=subprocess.check_output(['aws','ssm','get-parameters-by-path','--path',path,'--with-decryption','--recursive','--output','json'])\ndata=json.loads(out)\nfor p in data.get('Parameters',[]):\n    key=p['Name'].split('/')[-1]\n    val=p.get('Value','')\n    print(f'export {key}={shlex.quote(val)}')\nPY",
  "chmod 0600 \"$ENV_EXPORT_FILE\"",

  "runuser -u appuser -- env APP_DIR=\"${APP_DIR}\" PM2_APP_NAME=\"${PM2_APP_NAME}\" bash -lc 'set -euo pipefail; export HOME=/home/appuser; export PM2_HOME=/home/appuser/.pm2; cd \"$APP_DIR/current\"; [ -s \"'$ENV_EXPORT_FILE'\" ] && source \"'$ENV_EXPORT_FILE'\" || true; pm2 startOrReload ecosystem.config.js --only \"$PM2_APP_NAME\" --update-env; pm2 save'",
  "rm -f \"$ENV_EXPORT_FILE\" || true",

  "# Health check",
  "PORT=$(python3 -c \"import os; print(os.getenv('PORT','3000'))\")",
  "for i in $(seq 1 30); do curl -fsS http://127.0.0.1:${PORT}/health >/dev/null && break; sleep 2; done",
  "curl -fsS http://127.0.0.1:${PORT}/health | head -c 300",

  "# Keep only last 3 releases",
  "cd ${APP_DIR}/releases && ls -1 | sort -r | tail -n +4 | xargs -r rm -rf || true",

  "echo Deployment successful: ${SERVICE_NAME} ${RELEASE_ID}"
]

print(json.dumps({"commands": commands}))
PY

COMMAND_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy ${SERVICE_NAME} ${RELEASE_ID}" \
  --targets \
    "Key=tag:Environment,Values=${ENVIRONMENT}" \
    "Key=tag:Service,Values=${SERVICE_NAME}" \
    "Key=tag:ManagedBy,Values=terraform" \
  --parameters file:///tmp/ssm-commands-web-driver.json \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId=$COMMAND_ID"

STATUS="InProgress"
for i in $(seq 1 90); do
  STATUS=$(aws ssm list-command-invocations \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --details \
    --query 'CommandInvocations[0].Status' \
    --output text || echo "Unknown")

  echo "SSM Status=$STATUS (attempt $i/90)"
  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut)
      break
      ;;
  esac
  sleep 10
done

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --details \
  --output json

if [ "$STATUS" != "Success" ]; then
  exit 1
fi
