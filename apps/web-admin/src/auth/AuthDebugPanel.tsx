import React, { useMemo, useState } from 'react';
import { useAuth } from './AuthProvider';
import { decodeJwtUnsafe, deriveRoleFromClaims, maskToken } from './authDebug';
import { getSessionStorage } from './authStorage';

function isAuthDebugEnabled(): boolean {
  const env = import.meta.env as unknown as Record<string, string | undefined>;
  return String(env.VITE_AUTH_DEBUG ?? '').toLowerCase() === 'true';
}

function Json({ value }: { value: unknown }) {
  return (
    <pre style={{ margin: 0, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
      {JSON.stringify(value, null, 2)}
    </pre>
  );
}

export function AuthDebugPanel() {
  const auth = useAuth();
  const [showTokens, setShowTokens] = useState(false);
  const [showStorageValues, setShowStorageValues] = useState(false);

  const enabled = isAuthDebugEnabled();
  const authedState = auth.state.status === 'authenticated' ? auth.state : null;
  const isAuthed = authedState !== null;

  const decoded = useMemo(() => {
    if (!authedState) return null;
    return {
      id: decodeJwtUnsafe(authedState.tokens.idToken),
      access: decodeJwtUnsafe(authedState.tokens.accessToken)
    };
  }, [authedState]);

  const derivedFromIdClaims = useMemo(() => {
    if (!decoded || !decoded.id.ok) return { role: null as any, source: null as any };
    return deriveRoleFromClaims(decoded.id.payload);
  }, [decoded]);

  const storageDump = useMemo(() => {
    try {
      const s = getSessionStorage();
      const keys: string[] = [];
      for (let i = 0; i < s.length; i++) {
        const k = s.key(i);
        if (!k) continue;
        if (k.startsWith('CognitoIdentityServiceProvider') || k.startsWith('amplify')) {
          keys.push(k);
        }
      }
      keys.sort();
      return keys.map((k) => ({ key: k, value: s.getItem(k) }));
    } catch (e: any) {
      return [{ key: 'storage_error', value: e?.message ?? String(e) }];
    }
  }, []);

  if (!enabled) return null;

  return (
    <section style={{ border: '1px solid #ddd', padding: 12, marginTop: 12, background: '#fafafa' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
        <h2 style={{ margin: 0 }}>Auth Debug</h2>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <input
              type="checkbox"
              checked={showTokens}
              onChange={(e) => setShowTokens(e.target.checked)}
            />
            Show raw tokens
          </label>
          <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <input
              type="checkbox"
              checked={showStorageValues}
              onChange={(e) => setShowStorageValues(e.target.checked)}
            />
            Show sessionStorage values
          </label>
        </div>
      </header>

      <p style={{ marginTop: 8, marginBottom: 8, color: '#555' }}>
        Enabled by <code>VITE_AUTH_DEBUG=true</code>. JWT decoding here is <em>unsigned</em> and for debugging only.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 12 }}>
        <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
          <h3 style={{ marginTop: 0 }}>Auth state</h3>
          <Json value={auth.state} />
        </div>

        {authedState ? (
          <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
            <h3 style={{ marginTop: 0 }}>Role inspection</h3>
            <Json
              value={{
                uiRole: auth.getRole(),
                userRoleField: authedState.user.role ?? null,
                derivedFromIdToken: derivedFromIdClaims
              }}
            />
          </div>
        ) : null}

        {authedState ? (
          <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
            <h3 style={{ marginTop: 0 }}>Tokens</h3>
            <Json
              value={{
                accessToken: showTokens
                  ? authedState.tokens.accessToken
                  : maskToken(authedState.tokens.accessToken),
                idToken: showTokens
                  ? authedState.tokens.idToken
                  : maskToken(authedState.tokens.idToken),
                accessTokenExp: authedState.tokens.accessTokenExp,
                idTokenExp: authedState.tokens.idTokenExp
              }}
            />
          </div>
        ) : null}

        {authedState ? (
          <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
            <h3 style={{ marginTop: 0 }}>Decoded ID token</h3>
            <Json value={decoded?.id ?? null} />
          </div>
        ) : null}

        {authedState ? (
          <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
            <h3 style={{ marginTop: 0 }}>Decoded Access token</h3>
            <Json value={decoded?.access ?? null} />
          </div>
        ) : null}

        <div style={{ border: '1px solid #eee', background: '#fff', padding: 10 }}>
          <h3 style={{ marginTop: 0 }}>Session storage (Cognito)</h3>
          <Json
            value={
              showStorageValues
                ? storageDump
                : storageDump.map((x) => ({ key: x.key, value: x.value ? '(hidden)' : null }))
            }
          />
        </div>
      </div>
    </section>
  );
}
