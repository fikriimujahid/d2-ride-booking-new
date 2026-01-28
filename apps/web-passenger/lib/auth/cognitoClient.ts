import {
  AuthenticationDetails,
  CognitoUser,
  CognitoUserPool,
  CognitoUserSession
} from 'amazon-cognito-identity-js';
import { jwtDecode } from 'jwt-decode';
import { getSessionStorage } from './storage';
import type { AuthTokens, AuthUser, Role } from './types';

/**
 * WHY NO COGNITO HOSTED UI?
 * - We want a fully custom UX and a DEV-first, minimal-cost setup.
 * - Hosted UI would add redirects/OAuth callbacks and extra configuration.
 * - Here we authenticate directly against the User Pool and receive JWTs.
 */

type IdTokenClaims = {
  exp: number;
  sub?: string;
  email?: string;
  'custom:role'?: Role;
};

type AccessTokenClaims = { exp: number };
export function getCognitoConfig() {
  // IMPORTANT (Next.js): env var access must be static for client-side inlining.
  // `process.env[name]` will be undefined in the browser bundle.
  const userPoolId = process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID;
  const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID;
  if (!userPoolId) throw new Error('Missing NEXT_PUBLIC_COGNITO_USER_POOL_ID. See .env.example.');
  if (!clientId) throw new Error('Missing NEXT_PUBLIC_COGNITO_CLIENT_ID. See .env.example.');
  return {
    userPoolId,
    clientId
  };
}

let poolSingleton: CognitoUserPool | null = null;

function getUserPool() {
  if (poolSingleton) return poolSingleton;
  const { userPoolId, clientId } = getCognitoConfig();

  poolSingleton = new CognitoUserPool({
    UserPoolId: userPoolId,
    ClientId: clientId,
    Storage: getSessionStorage() as any
  });

  return poolSingleton;
}

function mapSession(session: CognitoUserSession): { tokens: AuthTokens; user: AuthUser } {
  const idToken = session.getIdToken().getJwtToken();
  const accessToken = session.getAccessToken().getJwtToken();

  // Decode is for client-side routing/UI only.
  // The backend must validate signatures/expiry using Cognito JWKS.
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
    Storage: getSessionStorage() as any
  });

  const authDetails = new AuthenticationDetails({ Username: username, Password: password });

  const session = await new Promise<CognitoUserSession>((resolve, reject) => {
    user.authenticateUser(authDetails, {
      onSuccess: resolve,
      onFailure: reject,
      newPasswordRequired: () => reject(new Error('New password required'))
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
  pool.getCurrentUser()?.signOut();
}
