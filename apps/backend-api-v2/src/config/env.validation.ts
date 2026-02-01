import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.string().optional(),
  PORT: z.coerce.number().int().positive().optional(),
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
