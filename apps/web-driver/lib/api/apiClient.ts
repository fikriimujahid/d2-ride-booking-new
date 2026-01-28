import type { AuthContextValue } from '../auth/AuthProvider';

export function getApiBaseUrl() {
  // IMPORTANT (Next.js): env var access must be static for client-side inlining.
  const v = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!v) throw new Error('Missing NEXT_PUBLIC_API_BASE_URL. See .env.example.');
  return v;
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
