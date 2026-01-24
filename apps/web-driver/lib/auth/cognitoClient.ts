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
 * - We want a first-party login UI and to keep the architecture DEV-first.
 * - Hosted UI adds OAuth redirects and callback URL management.
 * - Here we authenticate directly to the User Pool and receive JWTs.
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
  const userPoolId = (process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID ?? '').trim();
  const clientId = (process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? '').trim();

  if (!userPoolId) {
    throw new Error('Missing NEXT_PUBLIC_COGNITO_USER_POOL_ID. See .env.example.');
  }
  if (!clientId) {
    throw new Error('Missing NEXT_PUBLIC_COGNITO_CLIENT_ID. See .env.example.');
  }

  // The Cognito SDK will throw a generic "Invalid UserPoolId format." later.
  // Validate here so misconfigured deployments fail with a useful message.
  if (userPoolId.includes('arn:') || userPoolId.includes('userpool/')) {
    throw new Error(
      'Invalid NEXT_PUBLIC_COGNITO_USER_POOL_ID: expected the raw pool id like "ap-southeast-1_XXXXXXXXX" (not an ARN).'
    );
  }
  if (userPoolId.length > 55 || !/^[\w-]+_[0-9a-zA-Z]+$/.test(userPoolId)) {
    throw new Error(
      'Invalid NEXT_PUBLIC_COGNITO_USER_POOL_ID format: expected "<region>_<id>" like "ap-southeast-1_XXXXXXXXX".'
    );
  }
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
