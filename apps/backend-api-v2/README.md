# backend-api-v2 (Phase A)

This package contains **Phase A: Authorization Foundation** for a NestJS REST API.

## Goals
- Verify **AWS Cognito JWTs** via JWKS (signature, issuer, audience, expiry)
- Attach a strongly-typed `request.user`
- Enforce **system access** using Cognito groups: `admin`, `driver`, `passenger`
- Fail closed: explicit `401` (unauthenticated) vs `403` (authenticated, insufficient access)

## Required environment variables
- `PORT` (optional, default `3000`)
- `COGNITO_REGION` (e.g. `ap-southeast-1`)
- `COGNITO_USER_POOL_ID` (e.g. `ap-southeast-1_XXXXXXXXX`)
- `COGNITO_APP_CLIENT_ID` (Cognito App Client ID)

Backward-compatible (deprecated):
- `COGNITO_CLIENT_ID`

Create `apps/backend-api-v2/.env.local` from `apps/backend-api-v2/.env.example`.

## Run
- Install deps (repo root): `npm install`
- Dev: `npm run dev --workspace apps/backend-api-v2`

## Test strategy (structure only)
Unit tests should focus on:
- `CognitoJwtStrategy` (issuer/audience/client_id/exp validation, group claim parsing)
- `JwtAuthGuard` (header extraction and failure modes => 401)
- `SystemGroupGuard` (metadata resolution, 401 vs 403)

Mock strategy:
- Do NOT hit Cognito JWKS in unit tests. Mock `CognitoJwtVerifierService.verifyBearerToken()` and return a known `AuthenticatedUser`.
- Add a small set of integration-style tests later (Phase B) that run against a local JWKS server or recorded JWKS.

What not to test (unit level):
- Cryptographic correctness of `jose`
- AWS Cognito availability
