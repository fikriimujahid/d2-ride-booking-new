#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Generic deploy script (PROD) via S3 + SSM (NO SSH), rolling by default.
#
# This is designed for ASGs behind an ALB:
# - Targets instances by tags (Environment + Service + ManagedBy)
# - Uses SSM send-command with max-concurrency=1 to do a safe rolling deploy
# - Keeps previous releases on disk for fast rollback (re-run with older RELEASE_ID)
# ==============================================================================

: "${AWS_REGION:?Set AWS_REGION}"
: "${S3_BUCKET_ARTIFACT:?Set S3_BUCKET_ARTIFACT}"
: "${RELEASE_ID:?Set RELEASE_ID (e.g. 20260128-120000)}"
: "${ENVIRONMENT:?Set ENVIRONMENT (e.g. prod)}"
: "${PROJECT_NAME:?Set PROJECT_NAME (must match Terraform project_name)}"

: "${SERVICE_NAME:?Set SERVICE_NAME (e.g. backend-api, web-driver)}"
: "${ARTIFACT_NAMESPACE:?Set ARTIFACT_NAMESPACE (e.g. apps/backend or apps/frontend)}"

PM2_APP_NAME="${PM2_APP_NAME:-$SERVICE_NAME}"
NEEDS_RDS_CA="${NEEDS_RDS_CA:-false}"
ROLLING_MAX_CONCURRENCY="${ROLLING_MAX_CONCURRENCY:-1}"

SSM_TAG_KEY_SERVICE="${SSM_TAG_KEY_SERVICE:-Service}"

APP_DIR="/opt/apps/${SERVICE_NAME}"
S3_KEY_TGZ="${ARTIFACT_NAMESPACE}/${SERVICE_NAME}-${RELEASE_ID}.tar.gz"
S3_KEY_SHA="${ARTIFACT_NAMESPACE}/${SERVICE_NAME}-${RELEASE_ID}.sha256"
PARAM_PATH="/${ENVIRONMENT}/${PROJECT_NAME}/${SERVICE_NAME}"

echo "[deploy] env=${ENVIRONMENT} service=${SERVICE_NAME} release=${RELEASE_ID}"
echo "[deploy] s3=s3://${S3_BUCKET_ARTIFACT}/${S3_KEY_TGZ}"
echo "[deploy] ssm_param_path=${PARAM_PATH}"

# Preflight: ensure at least one param exists (fail fast)
if ! aws ssm get-parameters-by-path \
  --region "$AWS_REGION" \
  --path "$PARAM_PATH" \
  --with-decryption \
  --recursive \
  --max-items 1 \
  --query 'Parameters[0].Name' \
  --output text >/tmp/ssm-preflight.out 2>/tmp/ssm-preflight.err; then
  echo "[deploy] preflight failed reading SSM params at ${PARAM_PATH}" >&2
  cat /tmp/ssm-preflight.err >&2 || true
  exit 1
fi

if [ "$(cat /tmp/ssm-preflight.out)" = "None" ] || [ ! -s /tmp/ssm-preflight.out ]; then
  echo "[deploy] no SSM parameters found under ${PARAM_PATH}" >&2
  exit 1
fi

python3 - <<'PY' > /tmp/ssm-commands.json
import json, os

AWS_REGION = os.environ["AWS_REGION"]
SERVICE_NAME = os.environ["SERVICE_NAME"]
PM2_APP_NAME = os.environ.get("PM2_APP_NAME", SERVICE_NAME)
APP_DIR = os.environ["APP_DIR"]
RELEASE_ID = os.environ["RELEASE_ID"]
S3_BUCKET = os.environ["S3_BUCKET_ARTIFACT"]
S3_KEY_TGZ = os.environ["S3_KEY_TGZ"]
S3_KEY_SHA = os.environ["S3_KEY_SHA"]
PARAM_PATH = os.environ["PARAM_PATH"]
NEEDS_RDS_CA = os.environ.get("NEEDS_RDS_CA", "false").lower() == "true"

release_dir = f"{APP_DIR}/releases/{RELEASE_ID}"

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
  f"export PARAM_PATH={PARAM_PATH}",

  # Ensure runtime user
  "if ! getent group appuser >/dev/null 2>&1; then groupadd --system appuser; fi",
  "if ! id -u appuser >/dev/null 2>&1; then useradd --system --gid appuser --create-home --home-dir /home/appuser --shell /bin/bash appuser; fi",

  # Directories
  "install -d -m 0755 -o appuser -g appuser ${APP_DIR} ${APP_DIR}/releases ${APP_DIR}/shared ${APP_DIR}/shared/logs",

  # Download + verify
  "cd /tmp",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_TGZ} ${SERVICE_NAME}-${RELEASE_ID}.tar.gz",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_SHA} ${SERVICE_NAME}-${RELEASE_ID}.sha256",
  "sha256sum -c ${SERVICE_NAME}-${RELEASE_ID}.sha256",

  # Extract
  f"rm -rf {release_dir} && mkdir -p {release_dir}",
  f"tar -xzf /tmp/{SERVICE_NAME}-{RELEASE_ID}.tar.gz -C {release_dir}",
  f"chown -R appuser:appuser {release_dir}",

  # Optional: RDS CA bundle for IAM-auth TLS
  "RDS_CA_PATH=${APP_DIR}/shared/aws-rds-global-bundle.pem",
]

if NEEDS_RDS_CA:
  commands += [
    "if [ ! -s \"${RDS_CA_PATH}\" ]; then curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o \"${RDS_CA_PATH}\"; fi",
    "chown appuser:appuser \"${RDS_CA_PATH}\" || true",
    "chmod 0644 \"${RDS_CA_PATH}\" || true",
  ]

commands += [
  # Atomic switch
  f"ln -sfn {release_dir} ${APP_DIR}/current",
  f"chown -h appuser:appuser ${APP_DIR}/current || true",

  # Generate env export file from SSM
  "ENV_EXPORT_FILE=$(mktemp /tmp/${SERVICE_NAME}-env.XXXXXX)",
  "python3 - <<'PYY' > \"$ENV_EXPORT_FILE\"\nimport json, os, shlex, subprocess\npath=os.environ['PARAM_PATH']\nout=subprocess.check_output(['aws','ssm','get-parameters-by-path','--path',path,'--with-decryption','--recursive','--output','json'])\ndata=json.loads(out)\nparams=data.get('Parameters',[])\nif not params:\n    raise SystemExit(f'No SSM parameters found under {path}')\nfor p in params:\n    key=p['Name'].split('/')[-1]\n    val=p.get('Value','')\n    print(f'export {key}={shlex.quote(val)}')\nPYY",
  "chmod 0600 \"$ENV_EXPORT_FILE\"",
  "chown appuser:appuser \"$ENV_EXPORT_FILE\"",

  # Start/restart via PM2
  "runuser -u appuser -- env APP_DIR=\"${APP_DIR}\" PM2_APP_NAME=\"${PM2_APP_NAME}\" PM2_LOG_DIR=\"${APP_DIR}/shared/logs\" bash -lc 'set -euo pipefail; export HOME=/home/appuser; export PM2_HOME=/home/appuser/.pm2; cd \"$APP_DIR/current\"; source \"'$ENV_EXPORT_FILE'\"; pm2 delete \"$PM2_APP_NAME\" >/dev/null 2>&1 || true; pm2 start ecosystem.config.js --only \"$PM2_APP_NAME\" --update-env --env production; pm2 save; pm2 describe \"$PM2_APP_NAME\" | head -n 120'",

  "rm -f \"$ENV_EXPORT_FILE\" || true",

  # Health check
  "PORT=$(python3 -c \"import os; print(os.getenv('PORT','3000'))\")",
  "for i in $(seq 1 30); do if curl -fsS http://127.0.0.1:${PORT}/health >/dev/null; then echo '[deploy] health ok'; break; fi; echo '[deploy] waiting for health...'; sleep 2; done",

  # Keep last 3 releases
  "cd ${APP_DIR}/releases && ls -1 | sort -r | tail -n +4 | xargs -r rm -rf || true",

  "echo Deployment successful: ${SERVICE_NAME} ${RELEASE_ID}"
]

print(json.dumps({"commands": commands}))
PY

COMMAND_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy ${SERVICE_NAME} ${RELEASE_ID} (${ENVIRONMENT})" \
  --targets \
    "Key=tag:Environment,Values=${ENVIRONMENT}" \
    "Key=tag:${SSM_TAG_KEY_SERVICE},Values=${SERVICE_NAME}" \
    "Key=tag:ManagedBy,Values=terraform" \
  --max-concurrency "$ROLLING_MAX_CONCURRENCY" \
  --max-errors "0" \
  --parameters file:///tmp/ssm-commands.json \
  --query 'Command.CommandId' \
  --output text)

echo "SSM CommandId=$COMMAND_ID"

STATUS="InProgress"
for i in $(seq 1 120); do
  STATUSES=$(aws ssm list-command-invocations \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --details \
    --query 'CommandInvocations[].Status' \
    --output text || echo "Unknown")

  echo "SSM Statuses=$STATUSES (attempt $i/120)"

  if echo "$STATUSES" | grep -Eq '(Failed|Cancelled|TimedOut)'; then
    STATUS="Failed"
    break
  fi

  if [ -n "$STATUSES" ] && ! echo "$STATUSES" | grep -Eq '(Pending|InProgress|Delayed)'; then
    STATUS="Success"
    break
  fi

  sleep 10
done

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --details \
  --output json

if [ "$STATUS" != "Success" ]; then
  echo "[deploy] deployment failed (status=$STATUS)" >&2
  exit 1
fi

echo "[deploy] success"
