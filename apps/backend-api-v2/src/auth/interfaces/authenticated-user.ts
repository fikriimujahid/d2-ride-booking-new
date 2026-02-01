import type { SystemGroup } from '../enums/system-group.enum';
import type { CognitoJwtPayload } from './cognito-jwt-payload';

export interface AuthenticatedUser {
  /** Cognito subject (user id). */
  userId: string;

  /** Best-effort email claim. */
  email: string;

  /** Cognito groups used for system-level access only. */
  systemGroups: readonly SystemGroup[];

  /** Verified JWT claims (signature/exp/iss/aud validated). */
  claims: CognitoJwtPayload;
}
