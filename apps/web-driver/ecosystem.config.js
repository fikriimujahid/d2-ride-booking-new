/**
 * PM2 process configuration for the Web Driver Next.js server.
 *
 * Why this exists:
 * - We deploy via SSM (no SSH) and manage the runtime with PM2.
 * - The app is intentionally NOT statically exported: driver UX often needs realtime/SSR
 *   patterns (e.g. live job updates, WebSockets, authenticated SSR, background refresh).
 *
 * DEV consolidation:
 * - web-driver runs on port 3001 (backend-api uses 3000)
 * - Logs go to /home/appuser/.pm2/logs/ and are shipped to CloudWatch
 * - Log group: /dev/web-driver
 * - Separate PM2 process ensures isolation from backend-api
 */

module.exports = {
  apps: [
    {
      name: 'web-driver',
      cwd: __dirname,
      // Run through bash so we can source runtime env vars (SSM-derived) before starting Next.
      // This avoids relying on PM2 daemon env inheritance.
      script: 'bash',
      args: "-lc 'set -euo pipefail; ENV_FILE=\"${APP_DIR:-/opt/apps/web-driver}/shared/env.sh\"; if [ -f \"$ENV_FILE\" ]; then source \"$ENV_FILE\"; fi; npm start -- -H 0.0.0.0 -p 3001'",
      env: {
        // Next.js requires a production build for `next start`.
        NODE_ENV: 'production',
        // Port is also set via args; keep for clarity/compat.
        PORT: '3001',
        // Used by the bash wrapper to find shared env file.
        APP_DIR: process.env.APP_DIR || '/opt/apps/web-driver',
      },
    },
  ],
};
