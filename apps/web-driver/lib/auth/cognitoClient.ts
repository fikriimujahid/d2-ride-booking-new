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

type CognitoConfig = {
  userPoolId: string;
  clientId: string;
};

function validateCognitoConfig(config: CognitoConfig) {
  const userPoolId = config.userPoolId.trim();
  const clientId = config.clientId.trim();

  if (!userPoolId) {
    throw new Error('Missing Cognito userPoolId. See .env.example.');
  }
  if (!clientId) {
    throw new Error('Missing Cognito clientId. See .env.example.');
  }

  // The Cognito SDK will throw a generic "Invalid UserPoolId format." later.
  // Validate here so misconfigured deployments fail with a useful message.
  if (userPoolId.includes('arn:') || userPoolId.includes('userpool/')) {
    throw new Error(
      'Invalid Cognito userPoolId: expected the raw pool id like "ap-southeast-1_XXXXXXXXX" (not an ARN).'
    );
  }
  if (userPoolId.length > 55 || !/^[\w-]+_[0-9a-zA-Z]+$/.test(userPoolId)) {
    throw new Error(
      'Invalid Cognito userPoolId format: expected "<region>_<id>" like "ap-southeast-1_XXXXXXXXX".'
    );
  }
}

let configSingleton: CognitoConfig | null = null;
let configPromise: Promise<CognitoConfig> | null = null;

async function loadCognitoConfig(): Promise<CognitoConfig> {
  if (configSingleton) return configSingleton;
  if (configPromise) return configPromise;

  configPromise = (async () => {
    // Runtime config fetch prevents stale compile-time inlining of NEXT_PUBLIC_*.
    // This endpoint is served by the same Next.js app.
    const res = await fetch('/api/public-config', { cache: 'no-store' });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(
        `Failed to load Cognito config from /api/public-config (${res.status}). ${text}`.trim()
      );
    }

    const data = (await res.json().catch(() => null)) as null | Partial<CognitoConfig>;
    const config: CognitoConfig = {
      userPoolId: (data?.userPoolId ?? '').trim(),
      clientId: (data?.clientId ?? '').trim()
    };

    validateCognitoConfig(config);
    configSingleton = config;
    return config;
  })();

  try {
    return await configPromise;
  } finally {
    configPromise = null;
  }
}

let poolSingleton: CognitoUserPool | null = null;
let poolConfigKey: string | null = null;

function clearCognitoIdentitySessionStorage() {
  // Cognito Identity JS stores tokens under keys like:
  // CognitoIdentityServiceProvider.<clientId>.<username>.*
  const storage = getSessionStorage();
  const keysToRemove: string[] = [];
  for (let i = 0; i < storage.length; i++) {
    const key = storage.key(i);
    if (!key) continue;
    if (key.startsWith('CognitoIdentityServiceProvider.')) keysToRemove.push(key);
  }
  for (const key of keysToRemove) storage.removeItem(key);
}

async function getUserPool() {
  const { userPoolId, clientId } = await loadCognitoConfig();
  const nextKey = `${userPoolId}:${clientId}`;

  if (poolSingleton && poolConfigKey === nextKey) return poolSingleton;

  // Config changed (or first init). Reset so we don't hold onto a stale pool.
  poolSingleton = new CognitoUserPool({
    UserPoolId: userPoolId,
    ClientId: clientId,
    Storage: getSessionStorage() as any
  });
  poolConfigKey = nextKey;

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
  const pool = await getUserPool();

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
  const pool = await getUserPool();
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
  // Keep signOut safe even if config hasn't loaded yet.
  poolSingleton?.getCurrentUser()?.signOut();
  clearCognitoIdentitySessionStorage();
}
