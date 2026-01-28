const path = require('path');

// DEV consolidation: backend-api runs on port 3000, web-driver on port 3001
// Logs go to /home/appuser/.pm2/logs/ and are shipped to CloudWatch by the agent
// Log group: /dev/backend-api

const defaultLogDir =
  process.platform === 'win32'
    ? path.join(__dirname, 'logs')
    : '/home/appuser/.pm2/logs';

const logDir = process.env.PM2_LOG_DIR || defaultLogDir;

module.exports = {
  apps: [
    {
      name: 'backend-api',
      script: 'dist/main.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '300M',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss.SSS Z',
      out_file: path.join(logDir, 'backend-api-out.log'),
      error_file: path.join(logDir, 'backend-api-error.log'),
      env: {
        NODE_ENV: 'dev',
        PORT: '3000'  // backend-api port (consolidated instance)
      },
      env_development: {
        NODE_ENV: 'dev',
        PORT: '3000'
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: '3000'
      }
    }
  ]
};
