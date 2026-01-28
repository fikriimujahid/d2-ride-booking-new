# ==============================================================================
# SHEBANG LINE: Tells the OS which interpreter to use when executing this file
# ==============================================================================
# The "env" command searches the system PATH for "bash" and uses it
# Why: Makes the script portable across systems where bash may be in different locations
# What breaks: Without this, you'd need to run "bash deploy-web-driver.sh" manually
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
# - Deployment is repeatable (idempotent, safe to rerun)
# - PM2 survives reboot (systemd + pm2 save)
# - Logs visible in CloudWatch (/dev/web-driver)
# - SSM Run Command reliable
# - web-driver stays up after deploy

# ==============================================================================
# REQUIRED ENVIRONMENT VARIABLES: These must be set by CI or operator before running
# ==============================================================================
# Syntax: : "${VAR:?error message}" is bash for "check VAR is set, fail with message if not"
# The colon ":" is a no-op command, but the parameter expansion happens first
# Why: These variables define WHERE and WHAT we're deploying - missing any would deploy to wrong place
# What breaks: Without AWS_REGION, AWS CLI commands would fail or use wrong region
#              Without S3_BUCKET_ARTIFACT, we wouldn't know where to download the artifact from
#              Without RELEASE_ID, we wouldn't know which version to deploy
#              Without ENVIRONMENT, we'd read SSM params from wrong environment (dev vs prod)
#              Without PROJECT_NAME, SSM param path would be wrong (must match Terraform)

# Which AWS region the EC2 instances and SSM commands run in (e.g. us-east-1)
: "${AWS_REGION:?Set AWS_REGION}"

# The S3 bucket where CI uploaded the deployment artifact (tarball + checksum)
: "${S3_BUCKET_ARTIFACT:?Set S3_BUCKET_ARTIFACT}"

# Unique identifier for this release (timestamp-based, e.g. 20260124-123000)
# Used to identify the artifact in S3 and create a versioned release folder on EC2
: "${RELEASE_ID:?Set RELEASE_ID (e.g. 20260124-123000)}"

# The environment we're deploying to (dev, staging, prod)
# Used to target correct EC2 instances and read correct SSM parameters
: "${ENVIRONMENT:?Set ENVIRONMENT (e.g. dev)}"

# The project name (must match Terraform's project_name variable exactly)
# Used to construct SSM parameter path: /ENVIRONMENT/PROJECT_NAME/SERVICE_NAME
# What breaks: If this doesn't match Terraform, SSM parameter loading will fail (no params found)
: "${PROJECT_NAME:?Set PROJECT_NAME (e.g. d2-ride-booking)}"

# ==============================================================================
# SERVICE CONFIGURATION: Defines what and where we're deploying
# ==============================================================================

# The name of the service we're deploying (matches Terraform EC2 tags)
# Why: Used to target correct EC2 instances via SSM tag filters
# What breaks: If this doesn't match the "Service" tag on EC2, SSM won't find any instances
SERVICE_NAME="web-driver"

# The name of the PM2 process (PM2 is a Node.js process manager)
# Why: Used to start/restart/delete the correct PM2 application by name
# What breaks: If this doesn't match ecosystem.config.js, PM2 won't know which app to manage
PM2_APP_NAME="web-driver"

# The root directory on EC2 where the app lives
# Why: Follows standard deployment pattern: /opt/apps/SERVICE_NAME/{releases,current,shared}
# What breaks: If appuser doesn't have permission here, deployment will fail with permission denied
APP_DIR="/opt/apps/${SERVICE_NAME}"

# ==============================================================================
# S3 ARTIFACT PATHS: Where to find the deployment artifact in S3
# ==============================================================================

# The S3 key (path) to the tarball containing the compiled Next.js app
# Example: apps/frontend/web-driver-20260124-123000.tar.gz
# Note: "frontend" path (not "backend") - web-driver is a Next.js frontend app
# Why: CI uploads this; we download it to deploy the exact same artifact everywhere
# What breaks: If this path is wrong, aws s3 cp will fail with "does not exist"
S3_KEY_TGZ="apps/frontend/${SERVICE_NAME}-${RELEASE_ID}.tar.gz"

# The S3 key to the SHA256 checksum file for the tarball
# Example: apps/frontend/web-driver-20260124-123000.sha256
# Why: Used to verify tarball wasn't corrupted during S3 upload/download (integrity check)
# What breaks: If checksum doesn't match, sha256sum -c will fail and deployment stops
S3_KEY_SHA="apps/frontend/${SERVICE_NAME}-${RELEASE_ID}.sha256"

# ==============================================================================
# SSM PARAMETER PATH: Where runtime config (env vars) is stored
# ==============================================================================

# The path in AWS Systems Manager Parameter Store where environment variables live
# Format: /ENVIRONMENT/PROJECT_NAME/SERVICE_NAME
# Example: /dev/d2-ride-booking/web-driver
# Why: All runtime config (NEXT_PUBLIC_API_URL, auth secrets, etc.) stored in SSM, not .env files
#      This follows AWS best practice: secrets in Parameter Store, not in code/Docker images
# What breaks: If path is wrong, SSM parameter loading will fail (no parameters found)
#              PROJECT_NAME must match exactly what Terraform used when creating parameters
PARAM_PATH="/${ENVIRONMENT}/${PROJECT_NAME}/${SERVICE_NAME}"

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
#   - > /tmp/ssm-commands-web-driver.json = redirect Python's stdout to this file
# Why: SSM send-command expects commands in JSON format; we generate it dynamically
python3 - <<'PY' > /tmp/ssm-commands-web-driver.json
# Import required Python modules
# json = serialize commands to JSON format
# os = read environment variables that bash passed to Python
import json
import os

# Read environment variables from bash (these were set earlier in the script)
# These variables define WHAT and WHERE we're deploying on the EC2 instance
AWS_REGION = os.environ["AWS_REGION"]
SERVICE_NAME = "web-driver"
PM2_APP_NAME = "web-driver"
APP_DIR = f"/opt/apps/{SERVICE_NAME}"
RELEASE_ID = os.environ["RELEASE_ID"]
S3_BUCKET = os.environ["S3_BUCKET_ARTIFACT"]

# Construct S3 keys for the tarball and checksum file
# These are the exact paths where CI uploaded the artifacts
# Note: "frontend" path because web-driver is a Next.js frontend app
S3_KEY_TGZ = f"apps/frontend/{SERVICE_NAME}-{RELEASE_ID}.tar.gz"
S3_KEY_SHA = f"apps/frontend/{SERVICE_NAME}-{RELEASE_ID}.sha256"

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
  
  # Export AWS_REGION so aws CLI commands on EC2 know which region to use
  # Why: EC2 instance might not have default region configured
  f"export AWS_REGION={AWS_REGION}",
  
  # Set shell variables for use in later commands
  # Why: Makes commands more readable and easier to maintain
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
  # CREATE DIRECTORY STRUCTURE
  # ==============================================================================
  # Standard deployment layout: /opt/apps/SERVICE_NAME/{releases, current -> release}
  # releases/ = keeps multiple versions so we can rollback
  # current = symlink pointing to the active release
  # Note: web-driver doesn't need shared/logs directory (logs go to CloudWatch via stdout)
  
  # install -d = create directory if it doesn't exist (like mkdir -p)
  # -m 0755 = set permissions (owner: rwx, group: rx, other: rx)
  # -o appuser -g appuser = set owner and group to appuser
  # Why: Create directories atomically with correct permissions in one command
  # What breaks: If these directories don't exist, later tar extraction will fail
  "install -d -m 0755 -o appuser -g appuser ${APP_DIR} ${APP_DIR}/releases",
  
  # ==============================================================================
  # DOWNLOAD ARTIFACT FROM S3
  # ==============================================================================
  # Download the tarball and checksum file that CI uploaded to S3
  
  # Change to /tmp directory (downloads go here, not in APP_DIR yet)
  # Why: Download to temp location first, verify integrity, THEN extract to APP_DIR
  #      This prevents partially-downloaded files from being deployed
  "cd /tmp",
  
  # Download tarball from S3
  # aws s3 cp = copy file from S3 to local filesystem
  # Why: This is the compiled Next.js application (.next/, public/, node_modules/, etc.)
  # What breaks: If EC2 IAM role doesn't have s3:GetObject permission on this bucket, download fails
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_TGZ} ${SERVICE_NAME}-${RELEASE_ID}.tar.gz",
  
  # Download checksum file from S3
  # Why: Used to verify tarball wasn't corrupted during upload/download
  "aws s3 cp s3://${S3_BUCKET}/${S3_KEY_SHA} ${SERVICE_NAME}-${RELEASE_ID}.sha256",
  
  # Verify checksum matches the downloaded tarball
  # sha256sum -c = read checksum from file and verify it matches the tarball
  # Why: CRITICAL security and reliability check - ensures we don't deploy corrupted/tampered code
  # What breaks: If checksum doesn't match, this command exits non-zero and deployment stops
  #              This is GOOD - better to fail than deploy broken code
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
  # Why: Extracts all application files (.next/, public/, ecosystem.config.js, etc.)
  "tar -xzf ${SERVICE_NAME}-${RELEASE_ID}.tar.gz -C ${APP_DIR}/releases/${RELEASE_ID}",
  
  # Fix ownership of extracted files (tar preserves original ownership from build machine)
  # chown -R = recursively change owner
  # appuser:appuser = owner:group
  # Why: appuser must own all files to be able to run the app and read config
  # What breaks: If files are owned by root, appuser can't read config or serve static files
  "chown -R appuser:appuser ${APP_DIR}/releases/${RELEASE_ID}",

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
  # Important for web-driver: Next.js needs NEXT_PUBLIC_* vars at build time, but runtime
  #      config (API URLs, auth secrets) still comes from SSM for security
  
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
  # What breaks: If SSM parameters don't exist, Python script continues with empty params
  #              (web-driver might work with defaults, unlike backend-api which needs DB creds)
  "python3 - <<'PY' > \"$ENV_EXPORT_FILE\"\nimport json, os, shlex, subprocess\npath=os.environ['PARAM_PATH']\nout=subprocess.check_output(['aws','ssm','get-parameters-by-path','--path',path,'--with-decryption','--recursive','--output','json'])\ndata=json.loads(out)\nfor p in data.get('Parameters',[]):\n    key=p['Name'].split('/')[-1]\n    val=p.get('Value','')\n    print(f'export {key}={shlex.quote(val)}')\nPY",
  
  # Set restrictive permissions on the env file (contains secrets)
  # chmod 0600 = only owner can read/write (rw-------)
  # Why: Env file contains secrets like auth client IDs, API keys
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
  # bash -lc = run bash as login shell (-l) with command (-c)
  #   -l = load ~/.bashrc and ~/.bash_profile (so nvm/node/pm2 are in PATH)
  #   -c = execute the string as a command
  # Why: PM2 was installed by appuser using npm, so it's in appuser's PATH, not root's PATH
  
  # Inside the bash command (runs as appuser):
  # set -euo pipefail = enable strict mode inside this subshell too
  # export HOME=/home/appuser = explicitly set HOME (runuser might not set it)
  # export PM2_HOME=/home/appuser/.pm2 = tell PM2 where to store process state
  # cd \"$APP_DIR/current\" = change to the current release directory
  # [ -s \"'$ENV_EXPORT_FILE'\" ] = check if env file exists and has size > 0
  # && source \"'$ENV_EXPORT_FILE'\" = if it exists, load all environment variables from SSM
  # || true = if env file is empty or doesn't exist, continue anyway (web-driver might work with defaults)
  #   Note: Different from backend-api which MUST have SSM params (database credentials)
  # pm2 delete \"$PM2_APP_NAME\" >/dev/null 2>&1 || true = stop and remove existing process
  #   || true = don't fail if process doesn't exist (first deployment)
  #   Why delete instead of reload: Ensures clean state, no risk of old code still running
  # pm2 start ecosystem.config.js --only \"$PM2_APP_NAME\" = start the Next.js app
  #   ecosystem.config.js = PM2 configuration file (defines app name, script, instances, etc.)
  #   --only = start only this specific app (in case ecosystem.config.js has multiple apps)
  #   --update-env = merge new environment variables with existing ones
  # pm2 save = persist PM2 process list to disk so it survives reboot
  #   Why: systemd unit file runs "pm2 resurrect" on boot to restore saved processes
  # Why this approach: Ensures PM2 is running with correct code, env vars, and configuration
  # What breaks: If PM2 isn't in PATH, this fails with "command not found"
  #              If ecosystem.config.js is invalid, PM2 won't start
  #              If app crashes immediately, PM2 will restart it (but deployment succeeds)
  "runuser -u appuser -- env APP_DIR=\"${APP_DIR}\" PM2_APP_NAME=\"${PM2_APP_NAME}\" bash -lc 'set -euo pipefail; export HOME=/home/appuser; export PM2_HOME=/home/appuser/.pm2; cd \"$APP_DIR/current\"; [ -s \"'$ENV_EXPORT_FILE'\" ] && source \"'$ENV_EXPORT_FILE'\" || true; pm2 delete \"$PM2_APP_NAME\" >/dev/null 2>&1 || true; pm2 start ecosystem.config.js --only \"$PM2_APP_NAME\" --update-env; pm2 save'",
  
  # Clean up the temporary env file (contains secrets)
  # rm -f = force remove (don't fail if file doesn't exist)
  # || true = don't fail if rm fails (deployment already succeeded)
  # Security: Important to remove this file after use (contains auth secrets, API keys, etc.)
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
  "# Health check",
  "PORT=$(python3 -c \"import os; print(os.getenv('PORT','3000'))\")",
  
  # Poll the health endpoint until it responds or we give up
  # for i in $(seq 1 30) = loop 30 times (30 * 2 seconds = 60 second timeout)
  # curl -fsS = fetch URL, fail on errors (-f), silent (-s), but show errors (-S)
  # http://127.0.0.1:${PORT}/health = local health check endpoint
  # >/dev/null = discard output (we only care if it succeeds)
  # && break = if curl succeeds, exit the loop early
  # sleep 2 = wait 2 seconds between attempts
  # Why: Next.js app takes time to start (server initialization, route compilation, etc.)
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
  # cd ${APP_DIR}/releases = change to releases directory
  # && = only continue if cd succeeds (defensive)
  # ls -1 = list directory entries, one per line
  # | sort -r = sort in reverse order (newest first, assuming timestamp-based names)
  # | tail -n +4 = skip first 3 lines (keep 3 newest), output rest
  # | xargs -r rm -rf = delete each directory
  #   -r = don't run rm if input is empty (prevents error if < 4 releases exist)
  #   rm -rf = recursively force delete
  # || true = don't fail if cleanup fails (deployment already succeeded)
  # Why: Each release is ~200MB+ (.next/ build output, node_modules/), disk space is finite
  #      Keep 3 releases for rollback capability (current, previous, previous-1)
  # What breaks: Nothing - this is just cleanup. If it fails, deployment still succeeded.
  "# Keep only last 3 releases",
  "cd ${APP_DIR}/releases && ls -1 | sort -r | tail -n +4 | xargs -r rm -rf || true",

  # Print success message
  # Why: Clear indicator in SSM/CloudWatch logs that deployment completed successfully
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
#   Key=tag:ServiceDriver,Values=${SERVICE_NAME} = match ServiceDriver tag (consolidated instance)
#   Key=tag:ManagedBy,Values=terraform = match ManagedBy tag
#   Why tags: Dynamic targeting - works even when instances change
#   DEV consolidation: Uses ServiceDriver tag to target the consolidated app-host instance
#   PROD: Will use separate instances with Service=web-driver tag
COMMAND_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy ${SERVICE_NAME} ${RELEASE_ID}" \
  --targets \
    "Key=tag:Environment,Values=${ENVIRONMENT}" \
    "Key=tag:ServiceDriver,Values=${SERVICE_NAME}" \
    "Key=tag:ManagedBy,Values=terraform" \
  --parameters file:///tmp/ssm-commands-web-driver.json \
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
# Why 15 minutes: Deployment includes download from S3, extraction, Next.js startup, etc.
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
  # "$STATUS" in = check if STATUS matches any of these patterns
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
    # Why: Shows errors from commands (bash errors, AWS CLI errors, Next.js errors, etc.)
    # What you'll see: "file not found", "permission denied", "command not found", "module not found", etc.
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
