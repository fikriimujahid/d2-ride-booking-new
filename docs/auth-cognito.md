
# Auth model (Phase 1)

Phase 1 documents the intended authentication model without provisioning AWS Cognito.

## Approach: JWT-based auth

- Backend API issues and validates JWTs.
- Frontends store tokens in a secure manner appropriate to their deployment model.
- No hosted UI (login UI handled by the web apps).

## Roles

- `Admin`: manages drivers, pricing rules, ops dashboards
- `Driver`: accepts rides, updates trip status, location updates
- `Passenger`: requests rides, sees ETAs, pays

## Frontend → API auth flow (high-level)

1. User signs in via app UI.
2. App sends credentials to API (or a dedicated auth endpoint).
3. API returns JWTs:
	- Access token (short-lived)
	- Refresh token (long-lived)
4. App calls API endpoints with `Authorization: Bearer <access_token>`.
5. API enforces RBAC based on JWT claims.

## Notes for Cognito alignment (future)

- Cognito User Pools can issue JWTs compatible with this model.
- Role/claims mapping should be explicit (`custom:role` or group claims).
- Keep the API as the policy enforcement point.

