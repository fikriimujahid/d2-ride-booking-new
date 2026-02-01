import type { AuthenticatedUser } from '../auth/interfaces/authenticated-user';

declare global {
  namespace Express {
    interface Request {
      /**
       * Populated by `JwtAuthGuard` after successful verification.
       * Undefined means unauthenticated.
       */
      user?: AuthenticatedUser;

      /** Correlation ID generated per request. */
      requestId?: string;
    }
  }
}

export {};
