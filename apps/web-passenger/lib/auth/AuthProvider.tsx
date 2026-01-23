'use client';

import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { AuthTokens, AuthUser, Role } from './types';
import * as cognito from './cognitoClient';

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
