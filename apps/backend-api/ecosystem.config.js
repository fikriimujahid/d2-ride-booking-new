const path = require('path');

const defaultLogDir =
  process.platform === 'win32'
    ? path.join(__dirname, 'logs')
    : '/opt/apps/backend-api/shared/logs';

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
        NODE_ENV: 'dev'
      },
      env_development: {
        NODE_ENV: 'dev'
      },
      env_production: {
        NODE_ENV: 'production'
      }
    }
  ]
};
