import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export function GET() {
  // IMPORTANT (Next.js): Avoid build-time env inlining in server bundles by using
  // bracket access. This endpoint must reflect runtime env (SSM/PM2) changes.
  const userPoolId = (
    process.env['NEXT_PUBLIC_COGNITO_USER_POOL_ID'] ?? process.env['COGNITO_USER_POOL_ID'] ?? ''
  ).trim();
  const clientId = (
    process.env['NEXT_PUBLIC_COGNITO_CLIENT_ID'] ?? process.env['COGNITO_CLIENT_ID'] ?? ''
  ).trim();

  if (!userPoolId || !clientId) {
    return NextResponse.json(
      {
        error:
          'Missing Cognito configuration. Set NEXT_PUBLIC_COGNITO_USER_POOL_ID/NEXT_PUBLIC_COGNITO_CLIENT_ID (or COGNITO_USER_POOL_ID/COGNITO_CLIENT_ID).'
      },
      {
        status: 500,
        headers: {
          'Cache-Control': 'no-store, max-age=0'
        }
      }
    );
  }

  return NextResponse.json(
    {
      userPoolId,
      clientId
    },
    {
      headers: {
        // Avoid stale config if env changes and the service restarts.
        'Cache-Control': 'no-store, max-age=0'
      }
    }
  );
}
