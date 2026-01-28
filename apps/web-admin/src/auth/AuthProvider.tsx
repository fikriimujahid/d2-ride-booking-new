import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { AuthTokens, AuthUser, Role } from './authTypes';
import * as cognito from './cognitoClient';

export type AuthState =
  | { status: 'loading' }
  | {
      status: 'authenticated';
      user: AuthUser;
      tokens: AuthTokens;
    }
  | { status: 'unauthenticated' };

type AuthContextValue = {
  state: AuthState;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
  /** Access token for API calls (Bearer token). */
  getAccessToken: () => string | null;
  /** Role is derived from ID token (custom:role). */
  getRole: () => Role | null;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  useEffect(() => {
    // JWT lifecycle (DEV, no Hosted UI):
    // - On page load we try to restore the Cognito session from sessionStorage.
    // - Cognito refresh token (if present) can transparently refresh access/id tokens.
    // - If refresh fails or tokens are expired, we force re-login.
    cognito
      .getCurrentSession()
      .then((session) => {
        if (!session) return setState({ status: 'unauthenticated' });
        setState({ status: 'authenticated', ...session });
      })
      .catch(() => setState({ status: 'unauthenticated' }));
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      signIn: async (username, password) => {
        setState({ status: 'loading' });
        const session = await cognito.signIn(username, password);
        setState({ status: 'authenticated', ...session });
      },
      signOut: () => {
        cognito.signOut();
        setState({ status: 'unauthenticated' });
      },
      getAccessToken: () =>
        state.status === 'authenticated' ? state.tokens.accessToken : null,
      getRole: () =>
        state.status === 'authenticated' ? state.user.role ?? null : null
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
