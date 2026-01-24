export type JwtDecodeResult =
  | {
      ok: true;
      header: Record<string, unknown>;
      payload: Record<string, unknown>;
    }
  | { ok: false; error: string };

function base64UrlToString(input: string): string {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const padLen = (4 - (normalized.length % 4)) % 4;
  const padded = normalized + '='.repeat(padLen);

  // atob is available in browsers; this is a Vite web app.
  const binary = globalThis.atob(padded);

  // Convert binary string to UTF-8 string.
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function parseJwtPart(part: string): Record<string, unknown> {
  const json = base64UrlToString(part);
  const parsed = JSON.parse(json);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { value: parsed };
  }
  return parsed as Record<string, unknown>;
}

export function decodeJwtUnsafe(token: string): JwtDecodeResult {
  try {
    const parts = token.split('.');
    if (parts.length < 2) return { ok: false, error: 'Not a JWT (expected 3 parts)' };
    const [headerB64, payloadB64] = parts;
    if (!headerB64 || !payloadB64) return { ok: false, error: 'Invalid JWT parts' };
    return {
      ok: true,
      header: parseJwtPart(headerB64),
      payload: parseJwtPart(payloadB64)
    };
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : undefined;
    return { ok: false, error: message ?? 'Failed to decode JWT' };
  }
}

export function maskToken(token: string, opts?: { head?: number; tail?: number }): string {
  const head = opts?.head ?? 18;
  const tail = opts?.tail ?? 10;
  if (!token) return '';
  if (token.length <= head + tail + 3) return token;
  return `${token.slice(0, head)}…${token.slice(-tail)}`;
}

export type RoleString = 'ADMIN' | 'DRIVER' | 'PASSENGER';

export function deriveRoleFromClaims(payload: Record<string, unknown>): {
  role: RoleString | null;
  source: string | null;
} {
  const customRole = payload['custom:role'];
  if (customRole === 'ADMIN' || customRole === 'DRIVER' || customRole === 'PASSENGER') {
    return { role: customRole, source: 'custom:role' };
  }

  const groups = payload['cognito:groups'];
  const groupList: string[] =
    typeof groups === 'string'
      ? [groups]
      : Array.isArray(groups)
        ? groups.filter((g): g is string => typeof g === 'string')
        : [];

  for (const candidate of ['ADMIN', 'DRIVER', 'PASSENGER'] as const) {
    if (groupList.includes(candidate)) return { role: candidate, source: 'cognito:groups' };
  }

  return { role: null, source: null };
}
