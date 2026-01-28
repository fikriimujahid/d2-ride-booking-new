import type { AuthContextValue } from '../auth/AuthProvider';
import { apiFetch, ApiError } from './apiClient';

export type ProfileRole = 'ADMIN' | 'DRIVER' | 'PASSENGER';

export type ProfileResponse = {
  id: string;
  user_id: string;
  email: string;
  phone_number: string | null;
  full_name: string | null;
  role: ProfileRole;
  created_at: string;
  updated_at: string;
};

export type CreateProfileInput = {
  email: string;
  phone_number?: string;
  full_name?: string;
  role?: ProfileRole;
};

export type UpdateProfileInput = Partial<CreateProfileInput>;

type AuthForApi = Pick<AuthContextValue, 'getAccessToken' | 'signOut'>;

export async function getMyProfile(auth: AuthForApi): Promise<ProfileResponse> {
  const res = await apiFetch('/profile', { method: 'GET' }, auth);
  return (await res.json()) as ProfileResponse;
}

export async function createMyProfile(auth: AuthForApi, input: CreateProfileInput): Promise<ProfileResponse> {
  const res = await apiFetch(
    '/profile',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input)
    },
    auth
  );
  return (await res.json()) as ProfileResponse;
}

export async function updateMyProfile(auth: AuthForApi, input: UpdateProfileInput): Promise<ProfileResponse> {
  const res = await apiFetch(
    '/profile',
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input)
    },
    auth
  );
  return (await res.json()) as ProfileResponse;
}

export async function deleteMyProfile(auth: AuthForApi): Promise<void> {
  await apiFetch('/profile', { method: 'DELETE' }, auth);
}

export function isNotFound(err: unknown): boolean {
  return err instanceof ApiError && err.status === 404;
}

export function formatApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const extra = err.bodyText ? `: ${err.bodyText}` : '';
    return `${err.message} (HTTP ${err.status})${extra}`;
  }
  if (err instanceof Error) return err.message;
  return 'Unknown error';
}
