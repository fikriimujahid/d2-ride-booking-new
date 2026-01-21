# Backend API (EC2/PM2) Debugging Runbook

This runbook is for when the Backend API deploy succeeds/fails but the service isn’t reachable, or when `pm2 show backend-api` says it doesn’t exist.

## Key concept: PM2 “home” (why `pm2 show backend-api` can be empty)

PM2 stores its process list and logs under a “PM2 home” directory (`PM2_HOME`). If PM2 is started under one user/home (or with a different `PM2_HOME`) and you later run `pm2` under another user/home, you’ll see a different process list.

That’s the most common reason you’ll see:

- `pm2 show backend-api` → `backend-api doesn't exist`

### Quick fix (check the same PM2 home used by deploy)

On the EC2 instance:

```bash
export PM2_HOME=/root/.pm2
pm2 list
pm2 show backend-api
```

If you still see nothing, the app likely never started (or crashed immediately). Continue below.

## 0) Confirm what *should* be running

In this repo, the PM2 app name is defined in `apps/backend-api/ecosystem.config.js`:

- `name: "backend-api"`
- `script: "dist/main.js"`

So a healthy state is:

```bash
pm2 list
# should include: backend-api
```

## 1) Quick triage checklist (EC2)

Run these on the instance:

```bash
# A) Is there a Node process?
ps aux | grep -E "node|dist/main" | grep -v grep

# B) Is port 3000 listening?
ss -lntp | grep 3000 || true

# C) Does the app respond locally?
curl -sS -D- http://127.0.0.1:3000/health || true
```

If there’s no listening port and no node process, PM2 likely didn’t start or it crashed.

## 2) Verify the deployed files (release + current)

Assuming app root is `/opt/apps/backend-api`:

```bash
APP_ROOT=/opt/apps/backend-api
ls -la $APP_ROOT
ls -la $APP_ROOT/current

# Verify important files exist in the *current* release
cd $APP_ROOT/current
ls -la ecosystem.config.js dist/main.js .env
```

If `ecosystem.config.js` is missing, the artifact packaging is wrong.

## 3) Check PM2 status and logs

### List and describe

```bash
export PM2_HOME=/root/.pm2
pm2 list
pm2 describe backend-api || true
```

### Tail logs

```bash
export PM2_HOME=/root/.pm2
pm2 logs backend-api --lines 200
```

If the process restarts repeatedly, you’ll see stack traces or config errors here.

### Where logs live on disk

```bash
export PM2_HOME=/root/.pm2
ls -la $PM2_HOME
ls -la $PM2_HOME/logs || true
```

## 4) Common failure modes + what to do

### A) Wrong PM2 home / wrong user

Symptoms:
- `pm2 show backend-api` says it doesn’t exist, but the app is actually running.

Fix:
- Use the same PM2 home that the deploy uses:

```bash
export PM2_HOME=/root/.pm2
pm2 list
```

If you prefer running PM2 under a non-root user, standardize on that user and set up systemd startup for it (see “Hardening” below).

### B) Process crashes immediately (bad env)

Symptoms:
- `pm2 list` shows `errored` or restarts.
- `pm2 logs` shows configuration validation errors, DB connection errors, missing env vars.

Checks:

```bash
cd /opt/apps/backend-api/current
# WARNING: don’t paste secrets into tickets
sed -n '1,120p' .env

node -v
node dist/main.js   # run once in foreground to see immediate error
```

### C) `dist/main.js` missing

Symptoms:
- PM2 errors like “script not found”

Check:

```bash
cd /opt/apps/backend-api/current
ls -la dist/main.js
```

If missing: the CI build/artifact is incomplete.

### D) App runs but not reachable externally

Symptoms:
- local curl works (`127.0.0.1:3000`) but ALB/SG/target group health fails

Checks:
- Security groups / ALB target group / Nginx (if any)
- Bind address inside NestJS (should listen on `0.0.0.0`, not only localhost)

### E) `EADDRINUSE: address already in use :::3000`

Symptoms:
- PM2 logs show: `Error: listen EADDRINUSE: address already in use :::3000`

What it means:
- Something is already listening on port `3000` (often a previous Node process or a second PM2 “home” starting another copy).

Steps (EC2):

1) Find which process owns port 3000:

```bash
ss -lntp | grep ':3000' || true
```

2) Check PM2 under the *deploy* PM2 home:

```bash
export PM2_HOME=/root/.pm2
pm2 list
pm2 describe backend-api || true
```

3) Also check if another PM2 home exists (common when earlier deploys used `/etc/.pm2`):

```bash
export PM2_HOME=/etc/.pm2
pm2 list
```

4) Fix: stop/delete the duplicate (pick the PM2 home that actually owns the running process):

```bash
# For the correct PM2_HOME (either /root/.pm2 or /etc/.pm2)
pm2 delete backend-api || true
pm2 save || true
```

5) If the listener is *not* managed by PM2 (still showing in `ss`), kill that PID:

```bash
# Replace <PID> from the ss output
kill <PID>
sleep 1
ss -lntp | grep ':3000' || true
```

After the port is free, redeploy (or start via PM2) again.

## 5) Debugging from GitHub Actions / SSM

If a deploy step fails in Actions, the most useful output is the SSM invocation stdout/stderr.

From your workstation:

```bash
aws ssm get-command-invocation \
  --command-id <COMMAND_ID> \
  --instance-id <INSTANCE_ID> \
  --output json
```

Look at:
- `StandardOutputContent`
- `StandardErrorContent`

## 6) “Hardening” (optional, recommended)

To avoid PM2 state confusion and ensure the service comes up after reboot:

- Run PM2 under a dedicated user (e.g. `backend`) with a fixed home directory.
- Set up systemd startup:

```bash
# As the target user (example)
pm2 startup systemd -u backend --hp /home/backend
pm2 save
```

Then always debug as that same user:

```bash
sudo -u backend -H pm2 list
sudo -u backend -H pm2 logs backend-api
```
