import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.string().optional(),
  PORT: z.coerce.number().int().positive().optional(),

  // Phase B: Prisma/MySQL
  DATABASE_URL: z.string().min(1).optional(),

  // Dual-mode DB auth
  DB_AUTH_MODE: z.enum(['static', 'iam']).optional(),
  DB_HOST: z.string().min(1).optional(),
  DB_PORT: z.coerce.number().int().positive().optional(),
  DB_USER: z.string().min(1).optional(),
  DB_NAME: z.string().min(1).optional(),
  DB_IAM_REGION: z.string().min(1).optional(),
  AWS_REGION: z.string().min(1).optional(),
  AWS_DEFAULT_REGION: z.string().min(1).optional(),
  DB_IAM_TOKEN_REFRESH_SECONDS: z.coerce.number().int().nonnegative().optional(),
  DB_IAM_REQUIRE_SSL: z.coerce.boolean().optional(),

  COGNITO_REGION: z.string().min(1),
  COGNITO_USER_POOL_ID: z.string().min(1),
  // New name (Phase A spec)
  COGNITO_APP_CLIENT_ID: z.string().min(1).optional(),
  // Backward-compatible fallback
  COGNITO_CLIENT_ID: z.string().min(1).optional()
});

export type AppEnv = z.infer<typeof envSchema>;

export function validateEnv(config: Record<string, unknown>): AppEnv {
  // zod provides runtime validation while keeping strict typing.
  // Fail fast with a clear, non-leaky message.
  try {
    const parsed = envSchema.parse(config);

    // Enforce at least one client id key.
    if (!parsed.COGNITO_APP_CLIENT_ID && !parsed.COGNITO_CLIENT_ID) {
      throw new Error('Invalid environment configuration. Missing/invalid: COGNITO_APP_CLIENT_ID.');
    }

    // IAM DB mode validation.
    if (parsed.DB_AUTH_MODE === 'iam') {
      const missing: string[] = [];
      if (!parsed.DB_HOST) missing.push('DB_HOST');
      if (!parsed.DB_USER) missing.push('DB_USER');
      if (!parsed.DB_NAME) missing.push('DB_NAME');

      const region = parsed.DB_IAM_REGION ?? parsed.AWS_REGION ?? parsed.AWS_DEFAULT_REGION ?? parsed.COGNITO_REGION;
      if (!region) missing.push('DB_IAM_REGION (or AWS_REGION)');

      if (missing.length > 0) {
        throw new Error(`Invalid environment configuration. Missing/invalid: ${missing.join(', ')}.`);
      }
    }

    // Phase B requires DB connectivity for RBAC-protected endpoints.
    // Keep optional to allow Phase A-only local runs.
    // (If you hit RBAC endpoints without DATABASE_URL, Prisma will error and be shaped by HttpErrorFilter.)

    return parsed;
  } catch (err: unknown) {
    if (err instanceof z.ZodError) {
      const keys = Array.from(
        new Set(
          err.issues
            .map((issue) => issue.path[0])
            .filter((k): k is string => typeof k === 'string' && k.length > 0)
        )
      );

      const keyList = keys.length > 0 ? keys.join(', ') : 'unknown keys';
      throw new Error(
        `Invalid environment configuration. Missing/invalid: ${keyList}. ` +
          `Create apps/backend-api-v2/.env.local from apps/backend-api-v2/.env.example.`
      );
    }
    throw err;
  }
}
