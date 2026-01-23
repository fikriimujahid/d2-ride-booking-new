import {
  AuthenticationDetails,
  CognitoUser,
  CognitoUserPool,
  CognitoUserSession
} from 'amazon-cognito-identity-js';
import { jwtDecode } from 'jwt-decode';
import { getSessionStorage } from './authStorage';
import type { AuthTokens, AuthUser, Role } from './authTypes';

/**
 * WHY NO COGNITO HOSTED UI?
 * - This demo intentionally avoids Hosted UI to keep the UX fully custom and to
 *   demonstrate the "manual" username/password flow.
 * - Hosted UI is great for production, but it adds redirect/OAuth complexity.
 * - Here we authenticate directly against the User Pool and receive JWTs.
 */

type IdTokenClaims = {
  exp: number;
  sub?: string;
  email?: string;
  'custom:role'?: Role;
};

type AccessTokenClaims = {
  exp: number;
};

function requireEnv(name: string): string {
  // Vite exposes env vars to the browser ONLY if prefixed with VITE_.
  const env = import.meta.env as unknown as Record<string, string | undefined>;
  const value = env[name];
  if (!value) {
    throw new Error(
      `Missing ${name}. Create a .env file (see .env.example) and restart dev server.`
    );
  }
  return value;
}

export type CognitoConfig = {
  userPoolId: string;
  clientId: string;
};

export function getCognitoConfig(): CognitoConfig {
  return {
    userPoolId: requireEnv('VITE_COGNITO_USER_POOL_ID'),
    clientId: requireEnv('VITE_COGNITO_CLIENT_ID')
  };
}

let userPoolSingleton: CognitoUserPool | null = null;

function getUserPool(): CognitoUserPool {
  if (userPoolSingleton) return userPoolSingleton;

  const { userPoolId, clientId } = getCognitoConfig();

  // IMPORTANT: Configure Cognito Identity JS to use sessionStorage.
  // This keeps refresh tokens out of localStorage (short-lived storage = less risk).
  userPoolSingleton = new CognitoUserPool({
    UserPoolId: userPoolId,
    ClientId: clientId,
    Storage: getSessionStorage()
  });

  return userPoolSingleton;
}

function mapSession(session: CognitoUserSession): { tokens: AuthTokens; user: AuthUser } {
  const idToken = session.getIdToken().getJwtToken();
  const accessToken = session.getAccessToken().getJwtToken();

  // NOTE: Frontend decoding is for UI decisions only.
  // Trust boundary: Backend MUST validate signature + expiry server-side.
  const idClaims = jwtDecode<IdTokenClaims>(idToken);
  const accessClaims = jwtDecode<AccessTokenClaims>(accessToken);

  return {
    tokens: {
      idToken,
      accessToken,
      idTokenExp: idClaims.exp,
      accessTokenExp: accessClaims.exp
    },
    user: {
      email: idClaims.email,
      role: idClaims['custom:role'],
      sub: idClaims.sub
    }
  };
}

export async function signIn(username: string, password: string) {
  const pool = getUserPool();

  const user = new CognitoUser({
    Username: username,
    Pool: pool,
    Storage: getSessionStorage()
  });

  const authDetails = new AuthenticationDetails({
    Username: username,
    Password: password
  });

  const session = await new Promise<CognitoUserSession>((resolve, reject) => {
    user.authenticateUser(authDetails, {
      onSuccess: resolve,
      onFailure: reject,
      newPasswordRequired: () => reject(new Error('New password required')),
      mfaRequired: () => reject(new Error('MFA not supported in this demo')),
      totpRequired: () => reject(new Error('TOTP not supported in this demo'))
    });
  });

  return mapSession(session);
}

export async function getCurrentSession() {
  const pool = getUserPool();
  const current = pool.getCurrentUser();
  if (!current) return null;

  const session = await new Promise<CognitoUserSession>((resolve, reject) => {
    current.getSession((err: Error | null, s: CognitoUserSession | null) => {
      if (err || !s) return reject(err ?? new Error('No session'));
      resolve(s);
    });
  });

  return mapSession(session);
}

export function signOut() {
  const pool = getUserPool();
  const current = pool.getCurrentUser();
  current?.signOut();
}
