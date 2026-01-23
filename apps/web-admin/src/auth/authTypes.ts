export type Role = 'ADMIN' | 'DRIVER' | 'PASSENGER';

export type AuthTokens = {
  /**
   * Cognito access token (token_use=access)
   * - Use this for calling backend APIs: Authorization: Bearer <accessToken>
   */
  accessToken: string;

  /**
   * Cognito ID token (token_use=id)
   * - Contains user claims and our custom RBAC claim: custom:role
   * - We use this on the frontend only to decide what UI/routes to show.
   */
  idToken: string;

  /**
   * Epoch seconds from the access token exp claim.
   * Used to proactively detect expiry and force re-login/refresh.
   */
  accessTokenExp: number;

  /**
   * Epoch seconds from the ID token exp claim.
   */
  idTokenExp: number;
};

export type AuthUser = {
  email?: string;
  role?: Role;
  sub?: string;
};
