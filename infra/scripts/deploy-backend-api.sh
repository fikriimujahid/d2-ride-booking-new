# ==============================================================================
# SHEBANG LINE: Tells the OS which interpreter to use when executing this file
# ==============================================================================
# The "env" command searches the system PATH for "bash" and uses it
# Why: Makes the script portable across systems where bash may be in different locations
#!/usr/bin/env bash

# ==============================================================================
# BASH STRICT MODE: Makes the script fail fast on errors
# ==============================================================================
# -e = Exit immediately if any command returns non-zero (fails)
# -u = Treat unset variables as errors (prevents typos like $RELASE_ID from being blank)
# -o pipefail = Make pipelines (cmd1 | cmd2) fail if ANY command in the chain fails
# Why: Without this, errors would be silently ignored and deployment might partially succeed
# What breaks: Without -e, a failed download from S3 would continue to deploy broken code
#              Without -u, $TYPO would be treated as empty string instead of failing
#              Without pipefail, "aws s3 cp (fails) | tar" would succeed even if download failed
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

# ==============================================================================
# REQUIRED ENVIRONMENT VARIABLES: These must be set by CI or operator before running
# ==============================================================================
# Syntax: : "${VAR:?error message}" is bash for "check VAR is set, fail with message if not"
# The colon ":" is a no-op command, but the parameter expansion happens first
: "${AWS_REGION:?Set AWS_REGION}"
: "${S3_BUCKET_ARTIFACT:?Set S3_BUCKET_ARTIFACT}"
: "${RELEASE_ID:?Set RELEASE_ID (e.g. 20260124-123000)}"
: "${ENVIRONMENT:?Set ENVIRONMENT (e.g. dev)}"

# The project name (must match Terraform's project_name variable exactly)
# Used to construct SSM parameter path: /ENVIRONMENT/PROJECT_NAME/SERVICE_NAME
: "${PROJECT_NAME:?Set PROJECT_NAME (e.g. d2-ride-booking)}"

# ==============================================================================
# SERVICE CONFIGURATION: Defines what and where we're deploying
# ==============================================================================

# The name of the service we're deploying (matches Terraform EC2 tags)
# Why: Used to target correct EC2 instances via SSM tag filters
SERVICE_NAME="backend-api"

# The name of the PM2 process (PM2 is a Node.js process manager)
# Why: Used to start/restart/delete the correct PM2 application by name
PM2_APP_NAME="backend-api"

# The root directory on EC2 where the app lives
# Why: Follows standard deployment pattern: /opt/apps/SERVICE_NAME/{releases,current,shared}
APP_DIR="/opt/apps/${SERVICE_NAME}"

# ==============================================================================
# S3 ARTIFACT PATHS: Where to find the deployment artifact in S3
# ==============================================================================

# The S3 key (path) to the tarball containing the compiled app code
S3_KEY_TGZ="apps/backend/${SERVICE_NAME}-${RELEASE_ID}.tar.gz"

# The S3 key to the SHA256 checksum file for the tarball
S3_KEY_SHA="apps/backend/${SERVICE_NAME}-${RELEASE_ID}.sha256"

# ==============================================================================
# SSM PARAMETER PATH: Where runtime config (env vars) is stored
# ==============================================================================

# The path in AWS Systems Manager Parameter Store where environment variables live
# Why: All runtime config (DB_HOST, JWT_SECRET, etc.) is stored in SSM, not .env files
#      This follows AWS best practice: secrets in Parameter Store, not in code/Docker images
PARAM_PATH="/${ENVIRONMENT}/${PROJECT_NAME}/${SERVICE_NAME}"

echo "[deploy] param_path=${PARAM_PATH}"

# ==============================================================================
# SSM PREFLIGHT CHECK: Verify SSM parameters exist BEFORE sending commands to EC2
# ==============================================================================
# This is a "fail fast" check that runs locally (in CI) before wasting time on SSM command
# Why: If SSM params don't exist, deployment will fail anyway when EC2 tries to read them
#      Better to fail here with clear error message than wait 5 minutes for SSM to fail on EC2

# Try to read at least one parameter from the SSM path
# --recursive = read all parameters under this path (including nested paths)
# --with-decryption = decrypt SecureString parameters (required for secrets like DB_PASSWORD)
# --max-items 1 = only fetch 1 parameter (we just want to know if path exists, not read all values)
# --query 'Parameters[0].Name' = extract just the name of the first parameter
# --output text = output as plain text instead of JSON
# >/tmp/ssm-preflight-backend-api.out = redirect stdout to temp file
# 2>/tmp/ssm-preflight-backend-api.err = redirect stderr to temp file
# Why redirect: So we can inspect both success output and error messages separately
if ! aws ssm get-parameters-by-path \
  --region "$AWS_REGION" \
  --path "$PARAM_PATH" \
  --with-decryption \
  --recursive \
  --max-items 1 \
  --query 'Parameters[0].Name' \
  --output text >/tmp/ssm-preflight-backend-api.out 2>/tmp/ssm-preflight-backend-api.err; then
  
  # If the aws command exited non-zero (failed), print error and exit
  # Why: Could be network error, wrong region, missing IAM permissions, or wrong path
  echo "[deploy] preflight failed reading SSM params at ${PARAM_PATH}" >&2
  
  # Print the stderr output from aws command (the actual error message)
  # || true = don't fail if cat fails (e.g., file doesn't exist)
  # Why: Gives operator the actual AWS error message to debug (e.g., "AccessDenied")
  cat /tmp/ssm-preflight-backend-api.err >&2 || true
  
  # Exit with non-zero status to fail the CI job immediately
  # Why: No point continuing if we can't read SSM parameters
  exit 1
fi

# Check if the output file is empty or contains "None" (AWS CLI returns "None" if no params found)
# [ "$(cat ...)" = "None" ] = check if file contents equal "None"
# || [ ! -s ... ] = OR check if file is empty or doesn't exist (-s = "file exists and has size > 0")
# Why: AWS CLI might succeed but return empty result if path exists but has no parameters
if [ "$(cat /tmp/ssm-preflight-backend-api.out)" = "None" ] || [ ! -s /tmp/ssm-preflight-backend-api.out ]; then
  echo "[deploy] preflight found no SSM parameters under ${PARAM_PATH}." >&2
  echo "[deploy] Check ENVIRONMENT/PROJECT_NAME/SERVICE_NAME (PROJECT_NAME should match Terraform, e.g. d2-ride-booking)." >&2
  exit 1
fi

# ==============================================================================
# GENERATE SSM COMMANDS: Build the shell script that will run ON THE EC2 INSTANCE
# ==============================================================================
# We use Python here-doc to generate a JSON file containing shell commands
# Why Python: Easier to do string interpolation and JSON escaping than bash
# Why here-doc: Embeds Python script inline without needing a separate .py file
# The output is a JSON file with a "commands" array that SSM will execute line by line

# Syntax: python3 - <<'PY' means:
#   - python3 = run Python 3
#   - "-" = read script from stdin (the here-doc)
#   - <<'PY' = here-doc marker (single quotes = disable bash variable expansion inside)
#   - > /tmp/ssm-commands-backend-api.json = redirect Python's stdout to this file
# Why: SSM send-command expects commands in JSON format; we generate it dynamically

python3 - <<'PY' > /tmp/ssm-commands-backend-api.json
import json
import os

# Read environment variables from bash (these were set earlier in the script)
# These variables define WHAT and WHERE we're deploying on the EC2 instance
AWS_REGION = os.environ["AWS_REGION"]
SERVICE_NAME = "backend-api"
PM2_APP_NAME = "backend-api"
APP_DIR = f"/opt/apps/{SERVICE_NAME}"
RELEASE_ID = os.environ["RELEASE_ID"]
S3_BUCKET = os.environ["S3_BUCKET_ARTIFACT"]

# Construct S3 keys for the tarball and checksum file
# These are the exact paths where CI uploaded the artifacts
S3_KEY_TGZ = f"apps/backend/{SERVICE_NAME}-{RELEASE_ID}.tar.gz"
S3_KEY_SHA = f"apps/backend/{SERVICE_NAME}-{RELEASE_ID}.sha256"

# Construct SSM parameter path (same as bash calculated earlier)
# This is where the EC2 instance will read runtime environment variables from
PARAM_PATH = f"/{os.environ['ENVIRONMENT']}/{os.environ['PROJECT_NAME']}/{SERVICE_NAME}"

# ==============================================================================
# BUILD COMMAND LIST: Each string is one shell command that runs on EC2
# ==============================================================================
# These commands run sequentially on the EC2 instance via SSM Run Command
# If any command fails (exits non-zero), the entire deployment stops due to "set -euo pipefail"

commands = [
  # Enable bash strict mode on EC2 (same as at top of this script)
  # Why: Make sure deployment fails fast if any step has an error
  "set -euo pipefail",
  
  # Set shell variables for use in later commands
  # Why: Makes commands more readable and easier to maintain
  f"export AWS_REGION={AWS_REGION}",
  f"SERVICE_NAME={SERVICE_NAME}",
  f"PM2_APP_NAME={PM2_APP_NAME}",
  f"APP_DIR={APP_DIR}",
  f"RELEASE_ID={RELEASE_ID}",
  f"S3_BUCKET={S3_BUCKET}",
  f"S3_KEY_TGZ={S3_KEY_TGZ}",
  f"S3_KEY_SHA={S3_KEY_SHA}",
  
  # Export PARAM_PATH so later Python scripts can read it
  # Why: export makes it available to child processes (like the Python script that reads SSM)
  f"export PARAM_PATH={PARAM_PATH}",

  # ==============================================================================
  # ENSURE RUNTIME USER EXISTS
  # ==============================================================================
  # This is defensive: user-data (EC2 startup script) should already create appuser
  # Why: We never run the app as root (security best practice: principle of least privilege)
  #      appuser is a non-privileged Linux user that owns the app files and runs PM2
  # What breaks: If appuser doesn't exist, all the chown and runuser commands will fail
  
  # Check if "appuser" group exists; if not, create it
  # getent group appuser = query system group database for "appuser"
  # >/dev/null 2>&1 = hide output (we only care about exit code)
  "if ! getent group appuser >/dev/null 2>&1; then groupadd appuser; fi",
  
  # Check if "appuser" user exists; if not, create it
  # id -u appuser = check if user exists
  # useradd -m = create user with home directory
  # -g appuser = set primary group to appuser
  # -s /bin/bash = set shell to bash (so we can runuser with bash -lc later)
  # Why: appuser needs a home directory for ~/.pm2 (PM2's config/process state)
  "if ! id -u appuser >/dev/null 2>&1; then useradd -m -g appuser -s /bin/bash appuser; fi",

  # ==============================================================================
  # CREATE DIRECTORY STRUCTURE
  # ==============================================================================
  # Standard deployment layout: /opt/apps/SERVICE_NAME/{releases, shared, current -> release}
  # releases/ = keeps multiple versions so we can rollback
  # shared/ = persistent data (logs) that survives across deployments
  # current = symlink pointing to the active release
  
  # install -d = create directory if it doesn't exist (like mkdir -p)
  # -m 0755 = set permissions (owner: rwx, group: rx, other: rx)
  # -o appuser -g appuser = set owner and group to appuser
  "install -d -m 0755 -o appuser -g appuser ${APP_DIR} ${APP_DIR}/releases ${APP_DIR}/shared ${APP_DIR}/shared/logs",
  
  # Create empty log files with correct ownership (defensive, in case PM2 expects them)
  # install -m 0644 = create file with rw-r--r-- permissions
  # /dev/null = copy from /dev/null (creates empty file)
  "install -m 0644 -o appuser -g appuser /dev/null ${APP_DIR}/shared/logs/backend-api-out.log",
  "install -m 0644 -o appuser -g appuser /dev/null ${APP_DIR}/shared/logs/backend-api-error.log",
  
  # Create directory for application logs (separate from PM2 logs)
  # -o root -g root = owned by root (app logs may be written by multiple users/processes)
  # Why: Centralized log directory for CloudWatch agent to collect from
  "install -d -m 0755 -o root -g root /var/log/app",

  # ==============================================================================
  # DOWNLOAD ARTIFACT FROM S3
  # ==============================================================================
  "cd /tmp",
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_TGZ} ${SERVICE_NAME}-${RELEASE_ID}.tar.gz",
  
  # Download checksum file from S3
  # Why: Used to verify tarball wasn't corrupted during upload/download
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_SHA} ${SERVICE_NAME}-${RELEASE_ID}.sha256",
  
  # Verify checksum matches the downloaded tarball
  # sha256sum -c = read checksum from file and verify it matches the tarball
  # Why: CRITICAL security and reliability check - ensures we don't deploy corrupted/tampered code
  "sha256sum -c ${SERVICE_NAME}-${RELEASE_ID}.sha256",

  # ==============================================================================
  # EXTRACT ARTIFACT TO RELEASES DIRECTORY
  # ==============================================================================
  
  # Create a new timestamped release directory
  # mkdir -p = create parent directories if needed, don't fail if already exists
  # Why: Each deployment gets its own directory so we can keep multiple versions and rollback
  "mkdir -p ${APP_DIR}/releases/${RELEASE_ID}",
  
  # Extract tarball into the release directory
  # tar -xzf = extract gzipped tarball
  # -C = change to this directory before extracting
  "tar -xzf ${SERVICE_NAME}-${RELEASE_ID}.tar.gz -C ${APP_DIR}/releases/${RELEASE_ID}",
  
  # Fix ownership of extracted files (tar preserves original ownership from build machine)
  # chown -R = recursively change owner
  # appuser:appuser = owner:group
  # Why: appuser must own all files to be able to run the app and write logs
  "chown -R appuser:appuser ${APP_DIR}/releases/${RELEASE_ID}",

  # ==============================================================================
  # DOWNLOAD AWS RDS TLS CA BUNDLE (required for secure database connections)
  # ==============================================================================
  
  # Set path to where we'll store the RDS certificate bundle
  # Why: When using IAM database authentication with RDS, you MUST use TLS
  #      The app needs this certificate to verify it's really connecting to AWS RDS
  # Security: Without this, connection could be MITMed (man-in-the-middle attacked)
  "RDS_CA_PATH=${APP_DIR}/shared/aws-rds-global-bundle.pem",
  
  # Download the bundle only if it doesn't exist or is empty
  # [ ! -s \"$RDS_CA_PATH\" ] = file doesn't exist or has zero size
  # curl -fsSL = download silently (-s) but fail on errors (-f), follow redirects (-L)
  # chmod 0644 = make file readable by everyone (appuser needs to read it)
  # Why: This bundle contains root certificates for all AWS RDS regions
  #      Without it, Node.js pg driver will reject the TLS connection
  # What breaks: Database connection will fail with "unable to verify certificate" error
  "if [ ! -s \"$RDS_CA_PATH\" ]; then curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o \"$RDS_CA_PATH\"; chmod 0644 \"$RDS_CA_PATH\"; fi",

  # ==============================================================================
  # ATOMIC SYMLINK SWAP (blue-green deployment pattern)
  # ==============================================================================
  
  # Update the "current" symlink to point to the new release
  # ln -sfn = create symlink, force overwrite (-f), don't dereference target (-n)
  # Why: Atomic operation - PM2 restart reads from "current", so this is the actual deployment moment
  #      Old release stays in releases/ directory for easy rollback
  # What breaks: If PM2 is reading files during this swap, it might see inconsistent state
  #              (This is why we do pm2 delete + pm2 start instead of pm2 reload)
  "ln -sfn ${APP_DIR}/releases/${RELEASE_ID} ${APP_DIR}/current",

  # ==============================================================================
  # LOAD RUNTIME CONFIGURATION FROM SSM PARAMETER STORE
  # ==============================================================================
  # Instead of .env files, we read all environment variables from AWS SSM
  # Why: .env files are insecure (might be committed to git, visible in Docker images)
  #      SSM Parameter Store is encrypted at rest, access-controlled via IAM, and audited
  
  # Ensure Python 3 is installed (needed to parse SSM JSON response)
  # command -v python3 = check if python3 command exists
  # >/dev/null 2>&1 = hide output
  # || = if python3 doesn't exist, install it
  # dnf -y install python3 = install Python 3 using DNF package manager (Amazon Linux 2023)
  # Why: We use Python to parse AWS CLI JSON output and generate bash export statements
  "# Load runtime config from SSM Parameter Store (no .env files)",
  "if ! command -v python3 >/dev/null 2>&1; then dnf -y install python3; fi",
  
  # Create a temporary file to store environment variable exports
  # mktemp /tmp/SERVICE_NAME-env.XXXXXX = create temp file with random suffix
  # Why: Store exports in temp file instead of directly in shell (avoids escaping issues)
  #      We'll source this file later to load all env vars at once
  "ENV_EXPORT_FILE=$(mktemp /tmp/${SERVICE_NAME}-env.XXXXXX)",
  
  # Generate bash export statements from SSM parameters using Python
  # This is a compressed Python script that:
  # 1. Fetches all parameters from SSM under PARAM_PATH
  # 2. Parses the JSON response
  # 3. Generates bash export statements with proper shell quoting
  # 4. Writes them to ENV_EXPORT_FILE
  # \\n = newline character (escaped for Python string in bash string)
  # Why compressed: SSM Run Command has character limits, so we minimize whitespace
  # Security: Uses shlex.quote() to safely escape special characters in values
  # What breaks: If SSM parameters don't exist, Python script exits with error and deployment stops
  "python3 - <<'PY' > \"$ENV_EXPORT_FILE\"\nimport json, os, shlex, subprocess\npath=os.environ['PARAM_PATH']\nout=subprocess.check_output(['aws','ssm','get-parameters-by-path','--path',path,'--with-decryption','--recursive','--output','json'])\ndata=json.loads(out)\nparams=data.get('Parameters',[])\nif not params:\n    raise SystemExit(f'No SSM parameters found under {path}')\nfor p in params:\n    key=p['Name'].split('/')[-1]\n    val=p.get('Value','')\n    print(f'export {key}={shlex.quote(val)}')\nPY",
  
  # Set restrictive permissions on the env file (contains secrets)
  # chmod 0600 = only owner can read/write (rw-------)
  # Why: Env file contains secrets like DB_PASSWORD, JWT_SECRET
  # Security: Other users on the EC2 instance should NOT be able to read these secrets
  "chmod 0600 \"$ENV_EXPORT_FILE\"",
  
  # Change ownership of env file to appuser
  # Why: appuser needs to read this file to source the environment variables
  "chown appuser:appuser \"$ENV_EXPORT_FILE\"",

  # ==============================================================================
  # START/RESTART PM2 PROCESS AS APPUSER
  # ==============================================================================
  # This is the most complex command - it switches to appuser and manages the PM2 process
  
  # runuser -u appuser = run the following command as appuser (not root)
  # -- = end of runuser options, start of command to run
  # env = run command with specified environment variables
  # APP_DIR=\"${APP_DIR}\" = pass APP_DIR to the command
  # PM2_APP_NAME=\"${PM2_APP_NAME}\" = pass PM2_APP_NAME to the command
  # PM2_LOG_DIR=\"${APP_DIR}/shared/logs\" = tell PM2 where to write logs
  # bash -lc = run bash as login shell (-l) with command (-c)
  #   -l = load ~/.bashrc and ~/.bash_profile (so nvm/node/pm2 are in PATH)
  #   -c = execute the string as a command
  # Why: PM2 was installed by appuser using npm, so it's in appuser's PATH, not root's PATH
  
  # Inside the bash command (runs as appuser):
  # set -euo pipefail = enable strict mode inside this subshell too
  # export HOME=/home/appuser = explicitly set HOME (runuser might not set it)
  # export PM2_HOME=/home/appuser/.pm2 = tell PM2 where to store process state
  # cd \"$APP_DIR/current\" = change to the current release directory
  # source \"'$ENV_EXPORT_FILE'\" = load all environment variables from SSM
  #   Note: ENV_EXPORT_FILE is from outer shell, so we use '$ENV_EXPORT_FILE' (single quotes)
  # pm2 delete \"$PM2_APP_NAME\" >/dev/null 2>&1 || true = stop and remove existing process
  #   || true = don't fail if process doesn't exist (first deployment)
  #   Why delete instead of reload: Ensures clean state, no risk of old code still running
  # pm2 start ecosystem.config.js --only \"$PM2_APP_NAME\" = start the app
  #   ecosystem.config.js = PM2 configuration file (defines app name, script, instances, etc.)
  #   --only = start only this specific app (in case ecosystem.config.js has multiple apps)
  #   --update-env = merge new environment variables with existing ones
  # pm2 save = persist PM2 process list to disk so it survives reboot
  #   Why: systemd unit file runs "pm2 resurrect" on boot to restore saved processes
  # echo \"[deploy] pm2 describe...\" = print deployment status message
  # pm2 describe \"$PM2_APP_NAME\" = show detailed process information
  # | head -n 200 = limit output to 200 lines (SSM has output limits)
  # Why this approach: Ensures PM2 is running with correct code, env vars, and configuration
  # What breaks: If PM2 isn't in PATH, this fails with "command not found"
  #              If ecosystem.config.js is invalid, PM2 won't start
  #              If app crashes immediately, PM2 will restart it (but deployment succeeds)
  "# Start/restart via PM2 as appuser",
  "runuser -u appuser -- env APP_DIR=\"${APP_DIR}\" PM2_APP_NAME=\"${PM2_APP_NAME}\" PM2_LOG_DIR=\"${APP_DIR}/shared/logs\" bash -lc 'set -euo pipefail; export HOME=/home/appuser; export PM2_HOME=/home/appuser/.pm2; cd \"$APP_DIR/current\"; source \"'$ENV_EXPORT_FILE'\"; pm2 delete \"$PM2_APP_NAME\" >/dev/null 2>&1 || true; pm2 start ecosystem.config.js --only \"$PM2_APP_NAME\" --update-env; pm2 save; echo \"[deploy] pm2 describe $PM2_APP_NAME:\"; pm2 describe \"$PM2_APP_NAME\" | head -n 200'",
  
  # Clean up the temporary env file (contains secrets)
  # rm -f = force remove (don't fail if file doesn't exist)
  # || true = don't fail if rm fails (deployment already succeeded)
  # Security: Important to remove this file after use (contains DB passwords, API keys, etc.)
  "rm -f \"$ENV_EXPORT_FILE\" || true",

  # ==============================================================================
  # HEALTH CHECK: Verify app is responding to HTTP requests
  # ==============================================================================
  # This catches immediate startup failures (app crashes, port already in use, etc.)
  
  # Get the PORT from environment variables (default to 3000 if not set)
  # python3 -c = run Python one-liner
  # import os; print(os.getenv('PORT','3000')) = read PORT env var or default to 3000
  # Why Python: Simpler than bash parameter expansion for default values
  # Note: This reads from shell environment, NOT from SSM (SSM was sourced into PM2 process only)
  "# Health check (surface crash loops in CloudWatch/SSM output)",
  "PORT=$(python3 -c \"import os; print(os.getenv('PORT','3000'))\")",
  
  # Poll the health endpoint until it responds or we give up
  # for i in $(seq 1 30) = loop 30 times (30 * 2 seconds = 60 second timeout)
  # curl -fsS = fetch URL, fail on errors (-f), silent (-s), but show errors (-S)
  # http://127.0.0.1:${PORT}/health = local health check endpoint
  # >/dev/null = discard output (we only care if it succeeds)
  # && break = if curl succeeds, exit the loop early
  # sleep 2 = wait 2 seconds between attempts
  # Why: App takes time to start (Node.js initialization, database connections, etc.)
  #      If we don't wait, health check would fail even though app will start successfully
  # What breaks: If app is in crash loop, this will retry for 60 seconds then fail
  "for i in $(seq 1 30); do curl -fsS http://127.0.0.1:${PORT}/health >/dev/null && break; sleep 2; done",
  
  # Fetch and display health check response (for debugging)
  # curl -fsS = same as above but we capture output this time
  # | head -c 300 = limit to first 300 characters (SSM has output limits)
  # Why: Shows app version, uptime, or other health info in deployment logs
  # What breaks: If this curl fails, deployment fails (which is correct - app isn't healthy)
  "curl -fsS http://127.0.0.1:${PORT}/health | head -c 300",

  # ==============================================================================
  # CLEANUP: Remove old releases (keep disk usage under control)
  # ==============================================================================
  
  # Keep only the 3 most recent releases
  "# Keep only last 3 releases",
  "cd ${APP_DIR}/releases && ls -1 | sort -r | tail -n +4 | xargs -r rm -rf || true",

  "echo Deployment successful: ${SERVICE_NAME} ${RELEASE_ID}"
]

# ==============================================================================
# OUTPUT JSON: Serialize commands array to JSON format for SSM
# ==============================================================================
# SSM send-command --parameters expects JSON like {"commands": ["cmd1", "cmd2", ...]}
# print(json.dumps(...)) = convert Python dict to JSON string
print(json.dumps({"commands": commands}))
PY

# ==============================================================================
# SEND SSM COMMAND TO EC2 INSTANCES
# ==============================================================================
# Now that we've generated the commands, send them to all matching EC2 instances

# aws ssm send-command = send shell script to EC2 instances via SSM agent
# --document-name "AWS-RunShellScript" = built-in SSM document for running shell commands
# --comment = description shown in AWS console (for auditing)
# --targets = select EC2 instances by tags (instead of explicit instance IDs)
#   Key=tag:Environment,Values=${ENVIRONMENT} = match Environment tag
#   Key=tag:ServiceBackend,Values=${SERVICE_NAME} = match ServiceBackend tag (consolidated instance)
#   Key=tag:ManagedBy,Values=terraform = match ManagedBy tag
#   Why tags: Dynamic targeting - works even when instances change
#   DEV consolidation: Uses ServiceBackend tag to target the consolidated app-host instance
#   PROD: Will use separate instances with Service=backend-api tag
COMMAND_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy ${SERVICE_NAME} ${RELEASE_ID}" \
  --targets \
    "Key=tag:Environment,Values=${ENVIRONMENT}" \
    "Key=tag:ServiceBackend,Values=${SERVICE_NAME}" \
    "Key=tag:ManagedBy,Values=terraform" \
  --parameters file:///tmp/ssm-commands-backend-api.json \
  --query 'Command.CommandId' \
  --output text)

# Print the command ID for debugging/auditing
# Why: Operator can use this ID to look up the deployment in AWS console
echo "SSM CommandId=$COMMAND_ID"

# ==============================================================================
# POLL SSM COMMAND STATUS: Wait for command to complete
# ==============================================================================
# SSM send-command is asynchronous - it returns immediately, command runs in background
# We need to poll until it finishes (success or failure)

# Initialize status to InProgress (assumption)
STATUS="InProgress"

# Poll up to 90 times (90 * 10 seconds = 15 minute timeout)
# seq 1 90 = generate numbers 1 through 90
# Why 15 minutes: Deployment includes download from S3, extraction, npm install, etc.
# for i in $(seq 1 90) = loop 90 times
for i in $(seq 1 90); do
  
  # Fetch current status of the SSM command
  # aws ssm list-command-invocations = get status of command on each instance
  # --command-id "$COMMAND_ID" = filter by our command
  # --details = include full output (we don't use it here, but needed for later)
  # --query 'CommandInvocations[0].Status' = extract status of first invocation
  #   Note: [0] assumes single instance or all instances have same status
  # --output text = plain text output
  # || echo "Unknown" = if AWS CLI fails, treat status as "Unknown"
  STATUS=$(aws ssm list-command-invocations \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --details \
    --query 'CommandInvocations[0].Status' \
    --output text || echo "Unknown")

  # Print status for operator visibility
  # Why: Shows progress in CI logs, helps debug stuck deployments
  echo "SSM Status=$STATUS (attempt $i/90)"
  
  # Check if status is terminal (finished, whether success or failure)
  # case = bash switch statement
  # $STATUS in = check if STATUS matches any of these patterns
  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut)
      # Command finished (success or failure) - stop polling
      # break = exit the for loop
      break
      ;;
  esac
  
  # Status is still InProgress or Pending - wait and try again
  # sleep 10 = wait 10 seconds before next poll
  # Why 10 seconds: Balance between responsiveness and API rate limits
  sleep 10
done

# ==============================================================================
# FETCH FULL COMMAND OUTPUT (for auditing and debugging)
# ==============================================================================

# Print full command invocation details as JSON
# Why: Includes stdout, stderr, timing info for all instances
#      Useful for debugging even if deployment succeeded
aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --details \
  --output json

# ==============================================================================
# ERROR HANDLING: If deployment failed, fetch detailed output for debugging
# ==============================================================================

# Check if final status is Success (anything else is a failure)
if [ "$STATUS" != "Success" ]; then
  
  # Print error message to stderr (>&2 = redirect to stderr)
  # Why stderr: Separates error messages from normal output, shows in red in terminals
  echo "[deploy] command failed; fetching per-instance stdout/stderr" >&2

  # Get list of instance IDs where the command ran
  # mapfile -t INSTANCE_IDS = read lines into bash array
  # < <(...) = process substitution (feed command output to mapfile)
  # aws ssm list-command-invocations --query 'CommandInvocations[].InstanceId'
  #   = get all instance IDs where command ran
  # --output text = plain text, space-separated
  # | tr '\t' '\n' = convert tabs to newlines (so each instance ID is on its own line)
  # || true = don't fail if AWS CLI fails (defensive)
  # Why: Need instance IDs to fetch per-instance stdout/stderr
  mapfile -t INSTANCE_IDS < <(aws ssm list-command-invocations \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --query 'CommandInvocations[].InstanceId' \
    --output text | tr '\t' '\n' || true)

  # Check if we got any instance IDs
  # ${#INSTANCE_IDS[@]} = length of array
  # -eq 0 = equals zero
  if [ "${#INSTANCE_IDS[@]}" -eq 0 ]; then
    # No instances found - SSM command didn't run on any instances
    # Why this happens: Tags didn't match any instances, or all instances are offline
    echo "[deploy] no instance IDs found for command; cannot fetch invocation output" >&2
  fi

  # Loop through each instance and fetch its output
  # Why: SSM runs the same command on multiple instances (if multiple instances match tags)
  #      We need to see output from each instance to debug which one failed
  for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    
    # Skip empty instance IDs (defensive)
    # [ -n "$INSTANCE_ID" ] = string is not empty
    # || continue = if empty, skip to next iteration
    [ -n "$INSTANCE_ID" ] || continue
    
    # Print separator for readability
    # Why: When multiple instances fail, this helps identify which output is from which instance
    echo "----- SSM get-command-invocation: $INSTANCE_ID (stdout) -----" >&2
    
    # Fetch stdout from this specific instance
    # aws ssm get-command-invocation = get detailed output for one instance
    # --instance-id "$INSTANCE_ID" = specify which instance
    # --query 'StandardOutputContent' = extract stdout
    # || true = don't fail if fetch fails (defensive)
    # Why: Shows the actual command output (echo statements, error messages, etc.)
    aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text || true

    # Print separator for stderr
    echo "----- SSM get-command-invocation: $INSTANCE_ID (stderr) -----" >&2
    
    # Fetch stderr from this specific instance
    # Why: Shows errors from commands (bash errors, AWS CLI errors, etc.)
    # What you'll see: "file not found", "permission denied", "command not found", etc.
    aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardErrorContent' \
      --output text || true
  done

  # Exit with failure status
  # Why: Make CI job fail so operator knows deployment didn't succeed
  # What breaks: Without this, CI would show green even though deployment failed
  exit 1
fi
