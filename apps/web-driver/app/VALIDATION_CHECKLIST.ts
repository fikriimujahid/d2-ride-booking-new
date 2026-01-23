/*
VALIDATION CHECKLIST (Phase 6 - DEV)

- Driver UI accessible at driver.d2.fikri.dev
- App is deployed to EC2 and runs via PM2 (not static)
- Login works via Cognito username/password (NO Hosted UI)
- JWT attached to API calls (Authorization: Bearer <access token>)
- Role-based behavior works (requires custom:role in ID token = DRIVER)
- 401 redirects back to login; 403 shows access denied
- EC2 is accessible via SSM (no SSH)
- infra/scripts/dev-stop.* stops driver EC2 instance
*/
