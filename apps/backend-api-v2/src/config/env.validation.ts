// Import zod for runtime type validation and schema definition
import { z } from 'zod';

/**
 * Environment variable schema using Zod for validation
 * Defines expected types, constraints, and optionality for all env vars
 * Provides runtime validation at application startup
 */
const envSchema = z.object({
  // Node environment (development, production, test)
  NODE_ENV: z.string().optional(),
  // HTTP server port (must be positive integer)
  PORT: z.coerce.number().int().positive().optional(),

  // Phase B: Prisma/MySQL database configuration
  DATABASE_URL: z.string().min(1).optional(),

  // Dual-mode database authentication: static connection string vs IAM token-based
  DB_AUTH_MODE: z.enum(['static', 'iam']).optional(),
  DB_HOST: z.string().min(1).optional(),       // Database host for IAM mode
  DB_PORT: z.coerce.number().int().positive().optional(),  // Database port
  DB_USER: z.string().min(1).optional(),       // Database username
  DB_NAME: z.string().min(1).optional(),       // Database name
  DB_IAM_REGION: z.string().min(1).optional(), // AWS region for IAM auth
  AWS_REGION: z.string().min(1).optional(),    // Alternative region variable
  AWS_DEFAULT_REGION: z.string().min(1).optional(), // Another region fallback
  DB_IAM_TOKEN_REFRESH_SECONDS: z.coerce.number().int().nonnegative().optional(), // Token refresh interval
  DB_IAM_REQUIRE_SSL: z.coerce.boolean().optional(), // Require SSL for database connection

  // AWS Cognito configuration (required)
  COGNITO_REGION: z.string().min(1),           // AWS region where Cognito user pool exists
  COGNITO_USER_POOL_ID: z.string().min(1),    // Cognito user pool ID
  // New name (Phase A spec) - preferred
  COGNITO_APP_CLIENT_ID: z.string().min(1).optional(),
  // Backward-compatible fallback for legacy configurations
  COGNITO_CLIENT_ID: z.string().min(1).optional()
});

// Export inferred TypeScript type from the schema
export type AppEnv = z.infer<typeof envSchema>;

/**
 * Validate environment variables at application startup
 * Ensures all required configuration is present and valid before the app runs
 * @param config - Raw environment variable object from process.env
 * @returns Validated and typed environment configuration
 * @throws Error with descriptive message if validation fails
 */
export function validateEnv(config: Record<string, unknown>): AppEnv {
  // zod provides runtime validation while keeping strict typing
  // Fail fast with a clear, non-leaky message for security
  try {
    // Parse and validate configuration against schema
    const parsed = envSchema.parse(config);

    // Enforce at least one Cognito client ID key is present
    if (!parsed.COGNITO_APP_CLIENT_ID && !parsed.COGNITO_CLIENT_ID) {
      throw new Error('Invalid environment configuration. Missing/invalid: COGNITO_APP_CLIENT_ID.');
    }

    // IAM DB mode validation - ensure all required fields are present
    if (parsed.DB_AUTH_MODE === 'iam') {
      const missing: string[] = [];
      // Check for required IAM mode fields
      if (!parsed.DB_HOST) missing.push('DB_HOST');
      if (!parsed.DB_USER) missing.push('DB_USER');
      if (!parsed.DB_NAME) missing.push('DB_NAME');

      // Region can come from multiple sources with fallback chain
      const region = parsed.DB_IAM_REGION ?? parsed.AWS_REGION ?? parsed.AWS_DEFAULT_REGION ?? parsed.COGNITO_REGION;
      if (!region) missing.push('DB_IAM_REGION (or AWS_REGION)');

      // If any required fields are missing, throw descriptive error
      if (missing.length > 0) {
        throw new Error(`Invalid environment configuration. Missing/invalid: ${missing.join(', ')}.`);
      }
    }

    // Phase B requires DB connectivity for RBAC-protected endpoints
    // Keep optional to allow Phase A-only local runs (auth without database)
    // If RBAC endpoints are hit without DATABASE_URL, Prisma will error and be shaped by HttpErrorFilter

    return parsed;
  } catch (err: unknown) {
    // Handle Zod validation errors with user-friendly messages
    if (err instanceof z.ZodError) {
      // Extract field names from validation errors
      const keys = Array.from(
        new Set(
          err.issues
            .map((issue) => issue.path[0])  // Get top-level field name
            .filter((k): k is string => typeof k === 'string' && k.length > 0)
        )
      );

      const keyList = keys.length > 0 ? keys.join(', ') : 'unknown keys';
      throw new Error(
        `Invalid environment configuration. Missing/invalid: ${keyList}. ` +
          `Create apps/backend-api-v2/.env.local from apps/backend-api-v2/.env.example.`
      );
    }
    // Re-throw non-Zod errors
    throw err;
  }
}
