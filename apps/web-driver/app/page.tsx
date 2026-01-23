'use client';

import React, { useMemo, useState } from 'react';
import { useAuth } from '../lib/auth/AuthProvider';
import { apiFetch } from '../lib/api/apiClient';

/**
 * WHY DRIVER APP IS NOT STATIC (DEV / Phase 6):
 * - Driver experiences often need real-time features: WebSockets, live location updates,
 *   streaming ride state changes, and server-side sessions.
 * - Next.js running on EC2 keeps us ready for SSR + realtime endpoints without adding
 *   CloudFront/Lambda@Edge complexity.
 * - Cost control: single small EC2 instance + PM2, stoppable via dev-stop scripts.
 */

export default function Page() {
  const auth = useAuth();

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [apiResult, setApiResult] = useState<string | null>(null);

  const role = auth.getRole();
  const canUseDriver = useMemo(() => role === 'DRIVER', [role]);

  if (auth.state.status === 'loading') {
    return (
      <main style={{ padding: 24 }}>
        <h1>Driver App</h1>
        <p>Loading session…</p>
      </main>
    );
  }

  if (auth.state.status === 'unauthenticated') {
    return (
      <main style={{ padding: 24, maxWidth: 520 }}>
        <h1>Driver App</h1>
        <p style={{ marginTop: 0 }}>Manual Cognito auth (no Hosted UI). Runs on EC2 (SSR/realtime ready).</p>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setError(null);
            setApiResult(null);
            try {
              await auth.signIn(username.trim(), password);
            } catch (err: any) {
              setError(err?.message ?? 'Login failed');
            }
          }}
        >
          <label style={{ display: 'block', marginBottom: 12 }}>
            Email
            <input
              style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
            />
          </label>
          <label style={{ display: 'block', marginBottom: 12 }}>
            Password
            <input
              style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              autoComplete="current-password"
            />
          </label>
          <button type="submit" style={{ padding: '10px 14px' }}>
            Sign in
          </button>
        </form>
        {error ? <p style={{ color: 'crimson', marginTop: 16 }}>{error}</p> : null}
      </main>
    );
  }

  return (
    <main style={{ padding: 24 }}>
      <header style={{ display: 'flex', alignItems: 'baseline', gap: 16 }}>
        <h1 style={{ margin: 0 }}>Driver App</h1>
        <button onClick={() => auth.signOut()} style={{ padding: '6px 10px' }}>
          Sign out
        </button>
      </header>

      <p style={{ color: '#555' }}>
        Signed in as <strong>{auth.state.user.email ?? 'unknown'}</strong> (role: <strong>{role ?? 'none'}</strong>)
      </p>

      {!canUseDriver ? (
        <section style={{ border: '1px solid #f3c2c2', background: '#fff5f5', padding: 12 }}>
          <h2 style={{ marginTop: 0 }}>Access denied</h2>
          <p>This app expects <code>custom:role</code> = <code>DRIVER</code> in the Cognito ID token.</p>
        </section>
      ) : (
        <section style={{ border: '1px solid #ddd', padding: 12 }}>
          <h2 style={{ marginTop: 0 }}>API connectivity</h2>
          <p>Uses access token as Bearer for calls to the backend API.</p>
          <button
            style={{ padding: '8px 12px' }}
            onClick={async () => {
              setError(null);
              setApiResult(null);
              try {
                const res = await apiFetch('/health', { method: 'GET' }, auth);
                setApiResult(await res.text());
              } catch (err: any) {
                setError(err?.message ?? 'Request failed');
              }
            }}
          >
            GET /health
          </button>
          {apiResult ? (
            <pre style={{ marginTop: 12, background: '#111', color: '#eee', padding: 12, overflow: 'auto' }}>
              {apiResult}
            </pre>
          ) : null}
          {error ? <p style={{ color: 'crimson', marginTop: 12 }}>{error}</p> : null}
        </section>
      )}
    </main>
  );
}
