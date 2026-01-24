'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import type { AuthContextValue } from '../auth/AuthProvider';
import {
  createMyProfile,
  deleteMyProfile,
  formatApiError,
  getMyProfile,
  isNotFound,
  type ProfileResponse,
  type ProfileRole,
  updateMyProfile
} from '../api/profileApi';

function coerceOptionalString(value: string): string | undefined {
  const v = value.trim();
  return v.length ? v : undefined;
}

function dateToDisplay(value: string | undefined): string {
  if (!value) return '';
  const d = new Date(value);
  return Number.isNaN(d.valueOf()) ? value : d.toLocaleString();
}

type Props = {
  auth: Pick<AuthContextValue, 'getAccessToken' | 'signOut'>;
  defaultEmail?: string;
};

export function ProfilePanel({ auth, defaultEmail }: Props) {
  const [profile, setProfile] = useState<ProfileResponse | null>(null);
  const [notCreatedYet, setNotCreatedYet] = useState(false);

  const [email, setEmail] = useState(defaultEmail ?? '');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [fullName, setFullName] = useState('');
  const [role, setRole] = useState<ProfileRole>('PASSENGER');

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const canCreate = useMemo(() => !profile && notCreatedYet, [profile, notCreatedYet]);
  const canUpdate = useMemo(() => !!profile, [profile]);

  const hydrateForm = useCallback((p: ProfileResponse | null) => {
    if (!p) return;
    setEmail(p.email ?? '');
    setPhoneNumber(p.phone_number ?? '');
    setFullName(p.full_name ?? '');
    setRole(p.role);
  }, []);

  const refresh = useCallback(async () => {
    setBusy(true);
    setError(null);
    setSuccess(null);

    try {
      const p = await getMyProfile(auth);
      setProfile(p);
      setNotCreatedYet(false);
      hydrateForm(p);
    } catch (err) {
      if (isNotFound(err)) {
        setProfile(null);
        setNotCreatedYet(true);
        setSuccess('No profile yet for this user. Fill the form and click Create.');
        return;
      }
      setError(formatApiError(err));
    } finally {
      setBusy(false);
    }
  }, [auth, hydrateForm]);

  useEffect(() => {
    refresh().catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <section style={{ border: '1px solid #ddd', padding: 12, marginTop: 16 }}>
      <header style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 }}>
        <div>
          <h2 style={{ marginTop: 0, marginBottom: 4 }}>Profile</h2>
          <p style={{ marginTop: 0, color: '#555' }}>CRUD against backend `GET/POST/PUT/DELETE /profile`.</p>
        </div>
        <button style={{ padding: '8px 12px' }} onClick={() => refresh()} disabled={busy}>
          Refresh
        </button>
      </header>

      {profile ? (
        <div style={{ fontSize: 13, color: '#555', marginBottom: 12 }}>
          <div>
            <strong>Profile ID:</strong> {profile.id}
          </div>
          <div>
            <strong>User ID:</strong> {profile.user_id}
          </div>
          <div>
            <strong>Created:</strong> {dateToDisplay(profile.created_at)}
          </div>
          <div>
            <strong>Updated:</strong> {dateToDisplay(profile.updated_at)}
          </div>
        </div>
      ) : null}

      <form onSubmit={(e) => e.preventDefault()} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        <label style={{ display: 'block' }}>
          Email
          <input
            style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            placeholder="john.doe@example.com"
          />
        </label>

        <label style={{ display: 'block' }}>
          Phone number
          <input
            style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
            value={phoneNumber}
            onChange={(e) => setPhoneNumber(e.target.value)}
            autoComplete="tel"
            placeholder="+6281234567890"
          />
        </label>

        <label style={{ display: 'block' }}>
          Full name
          <input
            style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            placeholder="John Doe"
          />
        </label>

        <label style={{ display: 'block' }}>
          Role
          <select
            style={{ display: 'block', width: '100%', padding: 10, marginTop: 6 }}
            value={role}
            onChange={(e) => setRole(e.target.value as ProfileRole)}
          >
            <option value="ADMIN">ADMIN</option>
            <option value="DRIVER">DRIVER</option>
            <option value="PASSENGER">PASSENGER</option>
          </select>
        </label>

        <div style={{ gridColumn: '1 / -1', display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
          <button
            style={{ padding: '10px 14px' }}
            disabled={busy || !canCreate || !email.trim()}
            onClick={async () => {
              setBusy(true);
              setError(null);
              setSuccess(null);
              try {
                const p = await createMyProfile(auth, {
                  email: email.trim(),
                  phone_number: coerceOptionalString(phoneNumber),
                  full_name: coerceOptionalString(fullName),
                  role
                });
                setProfile(p);
                setNotCreatedYet(false);
                hydrateForm(p);
                setSuccess('Profile created.');
              } catch (err) {
                setError(formatApiError(err));
              } finally {
                setBusy(false);
              }
            }}
            type="button"
          >
            Create
          </button>

          <button
            style={{ padding: '10px 14px' }}
            disabled={busy || !canUpdate}
            onClick={async () => {
              setBusy(true);
              setError(null);
              setSuccess(null);
              try {
                const p = await updateMyProfile(auth, {
                  email: email.trim() || undefined,
                  phone_number: coerceOptionalString(phoneNumber),
                  full_name: coerceOptionalString(fullName),
                  role
                });
                setProfile(p);
                hydrateForm(p);
                setSuccess('Profile updated.');
              } catch (err) {
                setError(formatApiError(err));
              } finally {
                setBusy(false);
              }
            }}
            type="button"
          >
            Update
          </button>

          <button
            style={{ padding: '10px 14px' }}
            disabled={busy}
            onClick={async () => {
              if (!confirm('Delete your profile? This only deletes from the database.')) return;
              setBusy(true);
              setError(null);
              setSuccess(null);
              try {
                await deleteMyProfile(auth);
                setProfile(null);
                setNotCreatedYet(true);
                setSuccess('Profile deleted.');
              } catch (err) {
                setError(formatApiError(err));
              } finally {
                setBusy(false);
              }
            }}
            type="button"
          >
            Delete
          </button>

          {busy ? <span style={{ color: '#555' }}>Working…</span> : null}
        </div>
      </form>

      {success ? <p style={{ color: '#0a7a2f', marginTop: 12 }}>{success}</p> : null}
      {error ? <p style={{ color: 'crimson', marginTop: 12, whiteSpace: 'pre-wrap' }}>{error}</p> : null}

      {canCreate ? (
        <p style={{ marginTop: 12, color: '#555' }}>
          Note: backend requires email on create. Update accepts partial fields.
        </p>
      ) : null}
    </section>
  );
}
