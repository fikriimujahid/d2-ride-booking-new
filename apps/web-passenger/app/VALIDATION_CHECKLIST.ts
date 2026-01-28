/*
VALIDATION CHECKLIST (Phase 6 - DEV)

- Passenger UI accessible at passenger.d2.fikri.dev
- Next.js is configured for static export (no SSR, no server routes)
- Login works via Cognito username/password (NO Hosted UI)
- JWT attached to API calls (Authorization: Bearer <access token>)
- Role-based behavior works (requires custom:role in ID token = PASSENGER)
- 401 redirects back to login; 403 shows access denied
*/
