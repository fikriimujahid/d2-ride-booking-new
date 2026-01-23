/**
 * PM2 process configuration for the Web Driver Next.js server.
 *
 * Why this exists:
 * - We deploy via SSM (no SSH) and manage the runtime with PM2.
 * - The app is intentionally NOT statically exported: driver UX often needs realtime/SSR
 *   patterns (e.g. live job updates, WebSockets, authenticated SSR, background refresh).
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
        // Keep consistent with ALB target group + Terraform defaults.
        PORT: '3000',
      },
    },
  ],
};
