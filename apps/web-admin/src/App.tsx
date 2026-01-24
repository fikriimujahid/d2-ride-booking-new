import React, { useMemo, useState } from 'react';
import { useAuth } from './auth/AuthProvider';
import { AuthDebugPanel } from './auth/AuthDebugPanel';
import { apiFetch } from './api/apiClient';
import { ProfilePanel } from './profile/ProfilePanel';

export function App() {
  const auth = useAuth();

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [apiResult, setApiResult] = useState<string | null>(null);

  const role = auth.getRole();

  const canUseAdmin = useMemo(() => role === 'ADMIN', [role]);

  if (auth.state.status === 'loading') {
    return (
      <main style={{ fontFamily: 'system-ui, sans-serif', padding: 24 }}>
        <h1>Admin Console</h1>
        <p>Loading session…</p>
      </main>
    );
  }

  if (auth.state.status === 'unauthenticated') {
    return (
      <main style={{ fontFamily: 'system-ui, sans-serif', padding: 24, maxWidth: 520 }}>
        <h1>Admin Console</h1>
        <p style={{ marginTop: 0 }}>
          Manual Cognito authentication (no Hosted UI). We sign in with email/password and receive JWTs.
        </p>

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

        {error ? (
          <p style={{ color: 'crimson', marginTop: 16 }}>{error}</p>
        ) : null}

        <p style={{ marginTop: 24, color: '#555' }}>
          JWT lifecycle (DEV): access token is sent to the API as Bearer; ID token is decoded client-side only to
          read <code>custom:role</code> for UI routing.
        </p>
      </main>
    );
  }

  // Authenticated
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: 24 }}>
      <header style={{ display: 'flex', alignItems: 'baseline', gap: 16 }}>
        <h1 style={{ margin: 0 }}>Admin Console</h1>
        <button onClick={() => auth.signOut()} style={{ padding: '6px 10px' }}>
          Sign out
        </button>
      </header>

      <p style={{ color: '#555' }}>
        Signed in as <strong>{auth.state.user.email ?? 'unknown'}</strong> (role: <strong>{role ?? 'none'}</strong>)
      </p>

      <AuthDebugPanel />

      {!canUseAdmin ? (
        <section style={{ border: '1px solid #f3c2c2', background: '#fff5f5', padding: 12 }}>
          <h2 style={{ marginTop: 0 }}>Access denied</h2>
          <p>This app requires the Cognito ID token claim <code>custom:role</code> = <code>ADMIN</code>.</p>
        </section>
      ) : (
        <>
          <section style={{ border: '1px solid #ddd', padding: 12 }}>
            <h2 style={{ marginTop: 0 }}>API connectivity</h2>
            <p>Calls the backend using <code>Authorization: Bearer &lt;accessToken&gt;</code>.</p>
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
            {error ? (
              <p style={{ color: 'crimson', marginTop: 12 }}>{error}</p>
            ) : null}
          </section>

          <ProfilePanel
            auth={auth}
            defaultEmail={auth.state.status === 'authenticated' ? auth.state.user.email : undefined}
          />
        </>
      )}
    </main>
  );
}

