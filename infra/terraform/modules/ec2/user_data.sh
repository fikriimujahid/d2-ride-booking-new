#!/bin/bash

# ==============================================================================
# EC2 BOOTSTRAP (Amazon Linux 2023)
# ==============================================================================
# Goals:
# - Deterministic + idempotent bootstrap
# - Install runtime dependencies (Node.js LTS 20, PM2, CloudWatch agent)
# - Create least-privileged runtime user (appuser) and standard directories
# - Enable SSM access (NO SSH)
# - Configure CloudWatch Logs collection for PM2 stdout/stderr
# - DO NOT start any application here (apps start only after artifact deploy)
#
# Deployment flow (documented here and re-used in GitHub Actions + SSM):
# 1) CI builds immutable artifact
# 2) CI uploads artifact to S3
# 3) CI triggers SSM Run Command
# 4) EC2 downloads artifact from S3 and swaps /opt/apps/<service>/current
# 5) PM2 (as appuser) restarts the service cleanly
#
# Validation checklist (DEV but production-grade):
# - EC2 boots without crashing
# - Apps do NOT start before deployment
# - Deployment is repeatable
# - PM2 survives reboot (systemd integration)
# - Logs are visible in CloudWatch
# - SSM Run Command works reliably (no SSH)
# - backend-api and web-driver stay up after deploy

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="/var/log/user-data.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Log everything to a file (and to the instance console via logger).
exec > >(tee -a "$LOG_FILE" | logger -t user-data -s 2>/dev/console) 2>&1

echo "[user-data] Starting bootstrap at $(date -Is)"

retry() {
  local attempts="$1"; shift
  local delay_seconds="$1"; shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    echo "[user-data] Command failed (attempt $n/$attempts), retrying in $${delay_seconds}s: $*" >&2
    n=$((n + 1))
    sleep "$delay_seconds"
  done
}

ENVIRONMENT="${environment}"
SERVICE_NAME="${service_name}"
PM2_APP_NAME="${pm2_app_name}"
CW_LOG_GROUP_NAME="${log_group_name}"

echo "[user-data] environment=$ENVIRONMENT service=$SERVICE_NAME pm2_app_name=$PM2_APP_NAME"

# ------------------------------------------------------------------------------
# 1) OS packages
# ------------------------------------------------------------------------------
# Keep the bootstrap predictable: install only what we need.
# Amazon Linux 2023 ships with curl-minimal by default; installing "curl" can
# conflict and break bootstrap. curl-minimal provides the curl CLI we need.
retry 3 5 dnf -y install ca-certificates curl-minimal tar gzip python3

# Node.js 20 LTS
if ! command -v node >/dev/null 2>&1 || ! node -v | grep -qE '^v20\.'; then
  echo "[user-data] Installing Node.js 20 (NodeSource)"
  retry 3 5 curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
  retry 3 5 dnf -y install nodejs
fi

echo "[user-data] node=$(node -v) npm=$(npm -v)"

# CloudWatch agent
if ! rpm -q amazon-cloudwatch-agent >/dev/null 2>&1; then
  echo "[user-data] Installing amazon-cloudwatch-agent"
  retry 3 5 dnf -y install amazon-cloudwatch-agent
fi

# PM2 (global)
if ! command -v pm2 >/dev/null 2>&1; then
  echo "[user-data] Installing pm2 globally"
  retry 3 5 npm install -g pm2
fi

echo "[user-data] pm2=$(pm2 -v)"

# ------------------------------------------------------------------------------
# 2) Create app runtime user + directories
# ------------------------------------------------------------------------------
# Dedicated non-login user (no SSH, no sudo)
if ! getent group appuser >/dev/null 2>&1; then
  echo "[user-data] Creating system group 'appuser'"
  groupadd --system appuser
fi

if ! id -u appuser >/dev/null 2>&1; then
  echo "[user-data] Creating system user 'appuser'"
  # Use /bin/bash so systemd/pm2/runuser flows are reliable; SSH is still blocked
  # by design (no keys, no password) and we do not grant sudo.
  useradd --system --gid appuser --create-home --home-dir /home/appuser --shell /bin/bash appuser
fi

mkdir -p /opt/apps/backend-api /opt/apps/web-driver /var/log/app

# Service-specific layout used by deploy automation.
mkdir -p "/opt/apps/$${SERVICE_NAME}/releases" "/opt/apps/$${SERVICE_NAME}/shared"

chown -R appuser:appuser /opt/apps/backend-api /opt/apps/web-driver /var/log/app
chmod 0755 /opt/apps /opt/apps/backend-api /opt/apps/web-driver /var/log/app || true

# ------------------------------------------------------------------------------
# 3) Ensure SSM agent is enabled (no SSH access)
# ------------------------------------------------------------------------------
echo "[user-data] Enabling amazon-ssm-agent"
systemctl enable --now amazon-ssm-agent
systemctl is-active --quiet amazon-ssm-agent

# ------------------------------------------------------------------------------
# 4) Configure PM2 systemd integration for appuser (no apps started here)
# ------------------------------------------------------------------------------
# This enables PM2 itself to start on boot. The app processes are started later
# during deployment via SSM.
if [ ! -f /etc/systemd/system/pm2-appuser.service ]; then
  echo "[user-data] Configuring pm2 systemd unit for appuser"
  # pm2 needs PATH injected when running via systemd.
  env PATH="$PATH:/usr/bin:/usr/local/bin" pm2 startup systemd -u appuser --hp /home/appuser
fi

systemctl daemon-reload
systemctl enable pm2-appuser
systemctl start pm2-appuser || true

# ------------------------------------------------------------------------------
# 5) CloudWatch Logs agent: collect PM2 stdout/stderr
# ------------------------------------------------------------------------------
# Required log group naming:
# - /dev/backend-api
# - /dev/web-driver
#
# NOTE: The instance role must allow logs:CreateLogStream + PutLogEvents to CW_LOG_GROUP_NAME.

# Ensure PM2 log directory exists and is owned by appuser
install -d -m 0755 -o appuser -g appuser /home/appuser/.pm2/logs
touch "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-out.log" "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-error.log" || true
chown appuser:appuser "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-out.log" "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-error.log" || true

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-out.log",
            "log_group_name": "$${CW_LOG_GROUP_NAME}",
            "log_stream_name": "{instance_id}-stdout"
          },
          {
            "file_path": "/home/appuser/.pm2/logs/$${PM2_APP_NAME}-error.log",
            "log_group_name": "$${CW_LOG_GROUP_NAME}",
            "log_stream_name": "{instance_id}-stderr"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "$${CW_LOG_GROUP_NAME}",
            "log_stream_name": "{instance_id}-user-data"
          }
        ]
      }
    }
  }
}
EOF

systemctl enable amazon-cloudwatch-agent
systemctl restart amazon-cloudwatch-agent || systemctl start amazon-cloudwatch-agent

echo "[user-data] Bootstrap complete at $(date -Is)"
