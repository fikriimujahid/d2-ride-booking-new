import type { AuthContextValue } from '../types-internal';

/**
 * Simple API client wrapper.
 * - Reads base URL from env (never hardcode api.d2.fikri.dev)
 * - Attaches Authorization header when token exists
 * - Normalizes 401/403 for UX
 */

function requireEnv(name: string): string {
  const env = import.meta.env as unknown as Record<string, string | undefined>;
  const value = env[name];
  if (!value) {
    throw new Error(`Missing ${name}. See .env.example.`);
  }
  return value;
}

export function getApiBaseUrl(): string {
  return requireEnv('VITE_API_BASE_URL');
}

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly bodyText?: string
  ) {
    super(message);
  }
}

export async function apiFetch(
  path: string,
  options: RequestInit,
  auth: Pick<AuthContextValue, 'getAccessToken' | 'signOut'>
) {
  const baseUrl = getApiBaseUrl().replace(/\/$/, '');
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const url = `${baseUrl}${normalizedPath}`;

  const token = auth.getAccessToken();

  const res = await fetch(url, {
    ...options,
    headers: {
      ...(options.headers ?? {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    }
  });

  if (res.status === 401) {
    // Token missing/expired/invalid -> force user to login again.
    auth.signOut();
    throw new ApiError('Unauthorized', 401, await res.text().catch(() => undefined));
  }

  if (res.status === 403) {
    throw new ApiError('Access denied', 403, await res.text().catch(() => undefined));
  }

  if (!res.ok) {
    throw new ApiError('Request failed', res.status, await res.text().catch(() => undefined));
  }

  return res;
}
