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
      script: 'npm',
      args: 'start',
      env: {
        // Next.js requires a production build for `next start`.
        NODE_ENV: 'production',
        // Port 3001 for consolidated instance (backend-api uses 3000)
        PORT: '3001',
      },
    },
  ],
};
