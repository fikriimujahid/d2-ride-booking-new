// Import SystemGroup enum for type safety
import type { SystemGroup } from '../enums/system-group.enum';
// Import Cognito JWT payload interface
import type { CognitoJwtPayload } from './cognito-jwt-payload';

/**
 * AuthenticatedUser interface - Represents a verified user from a Cognito JWT
 * This object is attached to the Express request by JwtAuthGuard
 * after successful authentication
 */
export interface AuthenticatedUser {
  /** Cognito subject claim (sub) - unique user identifier */
  userId: string;

  /** User's email address from JWT claims (best-effort, may be empty) */
  email: string;

  /** 
   * Cognito groups the user belongs to (ADMIN, DRIVER, PASSENGER)
   * Used for system-level access control only (not fine-grained RBAC)
   */
  systemGroups: readonly SystemGroup[];

  /** 
   * Complete verified JWT payload with all claims
   * Includes signature validation, expiration, issuer, and audience checks
   */
  claims: CognitoJwtPayload;
}
