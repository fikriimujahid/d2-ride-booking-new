'use client';

import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { AuthTokens, AuthUser, Role } from './types';
import * as cognito from './cognitoClient';

function getApiBaseUrl() {
  // IMPORTANT (Next.js): env var access must be static for client-side inlining.
  const v = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!v) throw new Error('Missing NEXT_PUBLIC_API_BASE_URL. See .env.example.');
  return v;
}

async function tryHydrateRoleFromProfile(tokens: AuthTokens): Promise<Role | null> {
  const baseUrl = getApiBaseUrl().replace(/\/$/, '');
  const res = await fetch(`${baseUrl}/profile`, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${tokens.accessToken}`
    }
  });

  if (res.status === 404) return null;
  if (!res.ok) return null;

  const data = (await res.json().catch(() => null)) as null | { role?: unknown };
  const role = data?.role;
  if (role === 'ADMIN' || role === 'DRIVER' || role === 'PASSENGER') return role;
  return null;
}

export type AuthState =
  | { status: 'loading' }
  | { status: 'unauthenticated' }
  | { status: 'authenticated'; user: AuthUser; tokens: AuthTokens };

type AuthContextValue = {
  state: AuthState;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
  getAccessToken: () => string | null;
  getRole: () => Role | null;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  useEffect(() => {
    cognito
      .getCurrentSession()
      .then((s) => {
        if (!s) return setState({ status: 'unauthenticated' });
        setState({ status: 'authenticated', ...s });

        if (!s.user.role) {
          tryHydrateRoleFromProfile(s.tokens)
            .then((role) => {
              if (!role) return;
              setState((prev) =>
                prev.status === 'authenticated'
                  ? { ...prev, user: { ...prev.user, role } }
                  : prev
              );
            })
            .catch(() => undefined);
        }
      })
      .catch(() => setState({ status: 'unauthenticated' }));
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      signIn: async (username, password) => {
        setState({ status: 'loading' });
        try {
          const s = await cognito.signIn(username, password);
          setState({ status: 'authenticated', ...s });

          if (!s.user.role) {
            const role = await tryHydrateRoleFromProfile(s.tokens).catch(() => null);
            if (role) {
              setState((prev) =>
                prev.status === 'authenticated'
                  ? { ...prev, user: { ...prev.user, role } }
                  : prev
              );
            }
          }
        } catch (err) {
          setState({ status: 'unauthenticated' });
          throw err;
        }
      },
      signOut: () => {
        cognito.signOut();
        setState({ status: 'unauthenticated' });
      },
      getAccessToken: () => (state.status === 'authenticated' ? state.tokens.accessToken : null),
      getRole: () => (state.status === 'authenticated' ? state.user.role ?? null : null)
    }),
    [state]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export type { AuthContextValue };
