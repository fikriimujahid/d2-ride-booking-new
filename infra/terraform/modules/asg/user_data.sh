#!/bin/bash

# ==============================================================================
# EC2 BOOTSTRAP (Amazon Linux 2023) - SINGLE SERVICE HOST (PROD)
# ==============================================================================
# Differences vs DEV:
# - One service per instance (no consolidation)
# - Hardened metadata (IMDSv2 required is configured in Launch Template)
# - Still NO SSH (SSM only)
# - Does NOT start the app; deployment happens via SSM with immutable artifacts

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="/var/log/user-data.log"
mkdir -p "$(dirname "$LOG_FILE")"
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
APP_PORT="${app_port}"

echo "[user-data] environment=$ENVIRONMENT service=$SERVICE_NAME app_port=$APP_PORT"

# OS packages (keep minimal)
retry 3 5 dnf -y install ca-certificates curl-minimal tar gzip python3

# Node.js 20 LTS
if ! command -v node >/dev/null 2>&1 || ! node -v | grep -qE '^v20\.'; then
  retry 3 5 curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
  retry 3 5 dnf -y install nodejs
fi

echo "[user-data] node=$(node -v) npm=$(npm -v)"

# CloudWatch agent
if ! rpm -q amazon-cloudwatch-agent >/dev/null 2>&1; then
  retry 3 5 dnf -y install amazon-cloudwatch-agent
fi

# PM2
if ! command -v pm2 >/dev/null 2>&1; then
  retry 3 5 npm install -g pm2
fi

echo "[user-data] pm2=$(pm2 -v)"

# Create runtime user
if ! getent group appuser >/dev/null 2>&1; then
  groupadd --system appuser
fi
if ! id -u appuser >/dev/null 2>&1; then
  useradd --system --gid appuser --create-home --home-dir /home/appuser --shell /bin/bash appuser
fi

# App directories
APP_DIR="/opt/apps/$${SERVICE_NAME}"
mkdir -p "$${APP_DIR}/releases" "$${APP_DIR}/shared" "$${APP_DIR}/shared/logs" "/var/log/app/$${SERVICE_NAME}"
chown -R appuser:appuser /opt/apps /var/log/app
chmod 0755 /opt/apps "$${APP_DIR}" || true

# SSM only (no SSH)
systemctl enable --now amazon-ssm-agent
systemctl is-active --quiet amazon-ssm-agent

# PM2 systemd integration (no app start)
if [ ! -f /etc/systemd/system/pm2-appuser.service ]; then
  env PATH="$PATH:/usr/bin:/usr/local/bin" pm2 startup systemd -u appuser --hp /home/appuser
fi
systemctl daemon-reload
systemctl enable pm2-appuser
systemctl start pm2-appuser || true

# CloudWatch logs: PM2 logs + user-data
# Deployment scripts set PM2_LOG_DIR=$${APP_DIR}/shared/logs, so we ship logs from there.
# We also ship the default PM2 log dir as a fallback.
install -d -m 0755 -o appuser -g appuser /home/appuser/.pm2/logs
install -d -m 0755 -o appuser -g appuser "$${APP_DIR}/shared/logs"

touch "/home/appuser/.pm2/logs/$${SERVICE_NAME}-out.log" "/home/appuser/.pm2/logs/$${SERVICE_NAME}-error.log" || true
touch "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-out.log" "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-error.log" || true
chown appuser:appuser "/home/appuser/.pm2/logs/$${SERVICE_NAME}-out.log" "/home/appuser/.pm2/logs/$${SERVICE_NAME}-error.log" || true
chown appuser:appuser "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-out.log" "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-error.log" || true

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-out.log",
            "log_group_name": "/$${ENVIRONMENT}/$${SERVICE_NAME}",
            "log_stream_name": "{instance_id}-stdout"
          },
          {
            "file_path": "$${APP_DIR}/shared/logs/$${SERVICE_NAME}-error.log",
            "log_group_name": "/$${ENVIRONMENT}/$${SERVICE_NAME}",
            "log_stream_name": "{instance_id}-stderr"
          },
          {
            "file_path": "/home/appuser/.pm2/logs/$${SERVICE_NAME}-out.log",
            "log_group_name": "/$${ENVIRONMENT}/$${SERVICE_NAME}",
            "log_stream_name": "{instance_id}-stdout-fallback"
          },
          {
            "file_path": "/home/appuser/.pm2/logs/$${SERVICE_NAME}-error.log",
            "log_group_name": "/$${ENVIRONMENT}/$${SERVICE_NAME}",
            "log_stream_name": "{instance_id}-stderr-fallback"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/$${ENVIRONMENT}/$${SERVICE_NAME}",
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
