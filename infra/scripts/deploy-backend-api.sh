#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DEPLOY BACKEND-API (DEV) via S3 + SSM (NO SSH)
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
# - Deployment is repeatable (idempotent, safe to rerun)
# - PM2 survives reboot (systemd + pm2 save)
# - Logs visible in CloudWatch (/dev/backend-api)
# - SSM Run Command reliable
# - backend-api stays up after deploy

: "${AWS_REGION:?Set AWS_REGION}"
: "${S3_BUCKET_ARTIFACT:?Set S3_BUCKET_ARTIFACT}"
: "${RELEASE_ID:?Set RELEASE_ID (e.g. 20260124-123000)}"
: "${ENVIRONMENT:?Set ENVIRONMENT (e.g. dev)}"
: "${PROJECT_NAME:?Set PROJECT_NAME (e.g. d2-ride-booking)}"

SERVICE_NAME="backend-api"
PM2_APP_NAME="backend-api"
APP_DIR="/opt/apps/${SERVICE_NAME}"

S3_KEY_TGZ="apps/backend/${SERVICE_NAME}-${RELEASE_ID}.tar.gz"
S3_KEY_SHA="apps/backend/${SERVICE_NAME}-${RELEASE_ID}.sha256"

PARAM_PATH="/${ENVIRONMENT}/${PROJECT_NAME}/${SERVICE_NAME}"

python3 - <<'PY' > /tmp/ssm-commands-backend-api.json
import json
import os

AWS_REGION = os.environ["AWS_REGION"]
SERVICE_NAME = "backend-api"
PM2_APP_NAME = "backend-api"
APP_DIR = f"/opt/apps/{SERVICE_NAME}"
RELEASE_ID = os.environ["RELEASE_ID"]
S3_BUCKET = os.environ["S3_BUCKET_ARTIFACT"]
S3_KEY_TGZ = f"apps/backend/{SERVICE_NAME}-{RELEASE_ID}.tar.gz"
S3_KEY_SHA = f"apps/backend/{SERVICE_NAME}-{RELEASE_ID}.sha256"
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

  "install -d -m 0755 -o appuser -g appuser ${APP_DIR} ${APP_DIR}/releases ${APP_DIR}/shared",
  "install -d -m 0755 -o root -g root /var/log/app",

  "cd /tmp",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_TGZ} ${SERVICE_NAME}-${RELEASE_ID}.tar.gz",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_SHA} ${SERVICE_NAME}-${RELEASE_ID}.sha256",
  "sha256sum -c ${SERVICE_NAME}-${RELEASE_ID}.sha256",

  "mkdir -p ${APP_DIR}/releases/${RELEASE_ID}",
  "tar -xzf ${SERVICE_NAME}-${RELEASE_ID}.tar.gz -C ${APP_DIR}/releases/${RELEASE_ID}",
  "chown -R appuser:appuser ${APP_DIR}/releases/${RELEASE_ID}",

  "# Ensure AWS RDS TLS CA bundle exists (required for IAM DB auth with strict TLS)",
  "RDS_CA_PATH=${APP_DIR}/shared/aws-rds-global-bundle.pem",
  "if [ ! -s \"$RDS_CA_PATH\" ]; then curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o \"$RDS_CA_PATH\"; chmod 0644 \"$RDS_CA_PATH\"; fi",

  "ln -sfn ${APP_DIR}/releases/${RELEASE_ID} ${APP_DIR}/current",

  "# Load runtime config from SSM Parameter Store (no .env files)",
  "if ! command -v python3 >/dev/null 2>&1; then dnf -y install python3; fi",
  "ENV_EXPORT_FILE=$(mktemp /tmp/${SERVICE_NAME}-env.XXXXXX)",
  "python3 - <<'PY' > \"$ENV_EXPORT_FILE\"\nimport json, os, shlex, subprocess\npath=os.environ['PARAM_PATH']\nout=subprocess.check_output(['aws','ssm','get-parameters-by-path','--path',path,'--with-decryption','--recursive','--output','json'])\ndata=json.loads(out)\nparams=data.get('Parameters',[])\nif not params:\n    raise SystemExit(f'No SSM parameters found under {path}')\nfor p in params:\n    key=p['Name'].split('/')[-1]\n    val=p.get('Value','')\n    print(f'export {key}={shlex.quote(val)}')\nPY",
  "chmod 0600 \"$ENV_EXPORT_FILE\"",

  "# Start/restart via PM2 as appuser",
  "runuser -u appuser -- bash -lc 'set -euo pipefail; export HOME=/home/appuser; export PM2_HOME=/home/appuser/.pm2; cd ${APP_DIR}/current; source \"'$ENV_EXPORT_FILE'\"; pm2 startOrReload ecosystem.config.js --only ${PM2_APP_NAME} --update-env; pm2 save'",
  "rm -f \"$ENV_EXPORT_FILE\" || true",

  "# Health check (surface crash loops in CloudWatch/SSM output)",
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
  --parameters file:///tmp/ssm-commands-backend-api.json \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId=$COMMAND_ID"

# Poll status and print output (avoid silent failures)
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
