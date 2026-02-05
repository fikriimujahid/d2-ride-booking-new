// Import jose library's standard JWT payload interface
import type { JWTPayload } from 'jose';

/**
 * CognitoJwtPayload interface - Typed representation of AWS Cognito JWT claims
 * Extends jose's JWTPayload with Cognito-specific claims
 * 
 * Token types:
 * - ID tokens: typically contain 'aud' (audience) claim
 * - Access tokens: typically contain 'client_id' claim
 * 
 * Note: Only claims actually used by the application are strongly typed here.
 * JWT signature, issuer (iss), expiration (exp), and not-before (nbf) are
 * validated by the jose library during verification.
 */
export interface CognitoJwtPayload extends JWTPayload {
  /** Subject claim - unique identifier for the user (required) */
  readonly sub: string;
  
  /** Email address of the user (optional) */
  readonly email?: string;
  
  /** Issuer claim - Cognito user pool URL (validated during verification) */
  readonly iss?: string;

  /** Audience claim - typically present in ID tokens (can be string or array) */
  readonly aud?: string | string[];
  
  /** Client ID claim - typically present in access tokens */
  readonly client_id?: string;

  /** 
   * Cognito groups claim - array of group names the user belongs to
   * Used for system-level authorization (ADMIN, DRIVER, PASSENGER)
   */
  readonly 'cognito:groups'?: readonly string[];
}
