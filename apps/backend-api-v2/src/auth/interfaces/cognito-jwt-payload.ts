import type { JWTPayload } from 'jose';

/**
 * Verified Cognito JWT payload.
 *
 * Notes:
 * - ID tokens typically have `aud`
 * - Access tokens typically have `client_id`
 * - Groups come from `cognito:groups` (if present)
 */
export interface CognitoJwtPayload extends JWTPayload {
  readonly sub: string;
  readonly email?: string;
  readonly iss?: string;

  readonly aud?: string | string[];
  readonly client_id?: string;

  readonly 'cognito:groups'?: readonly string[];
}
