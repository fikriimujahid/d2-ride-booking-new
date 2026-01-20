/**
 * Minimal env validation to keep configuration explicit.
 * IAM DB auth and Cognito JWT checks rely on these values being present at runtime.
 */
export const validateEnv = (config: Record<string, unknown>) => {
  const requiredKeys = [
    'AWS_REGION',
    'COGNITO_USER_POOL_ID',
    'COGNITO_CLIENT_ID',
    'DB_HOST',
    'DB_NAME',
    'DB_USER'
    // DB_PASSWORD is optional (used for local dev; production uses IAM auth)
  ];

  for (const key of requiredKeys) {
    if (!config[key]) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
  }

  return {
    NODE_ENV: config.NODE_ENV ?? 'dev',
    PORT: config.PORT ?? 3000,
    ...config
  } as unknown as Record<string, string>;
};
