import type { AuthenticatedUser } from '../auth/interfaces/authenticated-user';
import type { PermissionResolution } from '../iam/rbac/permission.types';

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

      /** Cached RBAC resolution for this request (Phase B). */
      rbac?: PermissionResolution;
    }
  }
}

export {};
