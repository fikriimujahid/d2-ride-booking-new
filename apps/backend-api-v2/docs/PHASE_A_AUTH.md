# Phase A — Authentication & System-Group Authorization (Cognito)

Scope: **JWT verification + system-group authorization only**.

Non-goals (Phase B+): RBAC, roles, permissions, DB authorization, business rules.

---

## 1) Architecture

### 1.1 Cognito JWT verification flow (JWKS)

1. Client calls your API with `Authorization: Bearer <JWT>`.
2. `JwtAuthGuard` extracts the bearer token.
3. `CognitoJwtStrategy.verifyJwt()` verifies the token using:
   - **Signature** via Cognito **JWKS** (`/.well-known/jwks.json`)
   - **Issuer** (`iss`) must match your Cognito User Pool issuer
   - **Expiration** (`exp`) and optional `nbf` are enforced by `jose`
   - **Audience / Client ID** must match your configured app client id
     - Accepts either `aud` (ID token) or `client_id` (access token)
4. On success, the guard attaches a strongly typed `request.user`.
5. `SystemGroupGuard` reads required groups declared with `@SystemGroup(...)`.
6. Default deny:
   - No token / invalid token => **401**
   - Token valid but missing/incorrect groups => **403**

### 1.2 Why system groups ≠ RBAC

Cognito groups (ADMIN/DRIVER/PASSENGER) are **coarse system access**. They answer:
- “Which app surface is this user allowed to use?”

RBAC answers **fine-grained authorization** questions:
- “Can this driver cancel this specific ride?”
- “Can this admin refund a payment?”

In Phase A we **only** gate by system group. RBAC (roles/permissions/resources) comes later.

---

## 2) Configuration

Required env vars:
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_APP_CLIENT_ID`

Backward-compatible (deprecated):
- `COGNITO_CLIENT_ID`

File: apps/backend-api-v2/.env.example

---

## 3) Cognito Data Seed (DEV ONLY)

Assumptions:
- You have an existing User Pool and App Client.
- You have AWS credentials configured (`aws configure`) and permission to administer Cognito.

Set these once in your shell:

```powershell
$env:AWS_REGION = "ap-southeast-1"
$env:USER_POOL_ID = "ap-southeast-1_XXXXXXXXX"
```

### 3.1 Create groups

```bash
aws cognito-idp create-group --user-pool-id "$USER_POOL_ID" --group-name "ADMIN"
aws cognito-idp create-group --user-pool-id "$USER_POOL_ID" --group-name "DRIVER"
aws cognito-idp create-group --user-pool-id "$USER_POOL_ID" --group-name "PASSENGER"
```

### 3.2 Create users (one per group)

ADMIN

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "admin@demo.fikri.dev" \
  --user-attributes Name=email,Value=admin@demo.fikri.dev Name=email_verified,Value=true \
  --temporary-password "Admin123!" \
  --message-action SUPPRESS
```

```powershell
aws cognito-idp admin-create-user `
  --user-pool-id "$env:USER_POOL_ID" `
  --username "admin@demo.fikri.dev" `
  --user-attributes Name=email,Value=admin@demo.fikri.dev Name=email_verified,Value=true `
  --temporary-password "Admin123!" `
  --message-action SUPPRESS
```

DRIVER

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "driver@demo.fikri.dev" \
  --user-attributes Name=email,Value=driver@demo.fikri.dev Name=email_verified,Value=true \
  --temporary-password "Driver123!" \
  --message-action SUPPRESS
```

```powershell
aws cognito-idp admin-create-user `
  --user-pool-id "$env:USER_POOL_ID" `
  --username "driver@demo.fikri.dev" `
  --user-attributes Name=email,Value=driver@demo.fikri.dev Name=email_verified,Value=true `
  --temporary-password "Driver123!" `
  --message-action SUPPRESS
```

PASSENGER

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "passenger@demo.fikri.dev" \
  --user-attributes Name=email,Value=passenger@demo.fikri.dev Name=email_verified,Value=true \
  --temporary-password "Passenger123!" \
  --message-action SUPPRESS
```

```powershell
aws cognito-idp admin-create-user `
  --user-pool-id "$env:USER_POOL_ID" `
  --username "passenger@demo.fikri.dev" `
  --user-attributes Name=email,Value=passenger@demo.fikri.dev Name=email_verified,Value=true `
  --temporary-password "Passenger123!" `
  --message-action SUPPRESS
```

### 3.3 Set permanent passwords

```bash
aws cognito-idp admin-set-user-password --user-pool-id "$USER_POOL_ID" --username "admin@demo.fikri.dev" --password "Password123!" --permanent
aws cognito-idp admin-set-user-password --user-pool-id "$USER_POOL_ID" --username "driver@demo.fikri.dev" --password "Password123!" --permanent
aws cognito-idp admin-set-user-password --user-pool-id "$USER_POOL_ID" --username "passenger@demo.fikri.dev" --password "Password123!" --permanent
```

```powershell
aws cognito-idp admin-set-user-password --user-pool-id "$env:USER_POOL_ID" --username "admin@demo.fikri.dev" --password "Password123!" --permanent
aws cognito-idp admin-set-user-password --user-pool-id "$env:USER_POOL_ID" --username "driver@demo.fikri.dev" --password "Password123!" --permanent
aws cognito-idp admin-set-user-password --user-pool-id "$env:USER_POOL_ID" --username "passenger@demo.fikri.dev" --password "Password123!" --permanent
```

### 3.4 Add users to groups

```bash
aws cognito-idp admin-add-user-to-group --user-pool-id "$USER_POOL_ID" --username "admin@demo.fikri.dev" --group-name "ADMIN"
aws cognito-idp admin-add-user-to-group --user-pool-id "$USER_POOL_ID" --username "driver@demo.fikri.dev" --group-name "DRIVER"
aws cognito-idp admin-add-user-to-group --user-pool-id "$USER_POOL_ID" --username "passenger@demo.fikri.dev" --group-name "PASSENGER"
```

```powershell
aws cognito-idp admin-add-user-to-group --user-pool-id "$env:USER_POOL_ID" --username "admin@demo.fikri.dev" --group-name "ADMIN"
aws cognito-idp admin-add-user-to-group --user-pool-id "$env:USER_POOL_ID" --username "driver@demo.fikri.dev" --group-name "DRIVER"
aws cognito-idp admin-add-user-to-group --user-pool-id "$env:USER_POOL_ID" --username "passenger@demo.fikri.dev" --group-name "PASSENGER"
```

---

## 4) Token retrieval (USER_PASSWORD_AUTH)

You need the **App Client ID** (NOT the client secret).

```bash
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "<COGNITO_APP_CLIENT_ID>" \
  --auth-parameters USERNAME="admin@demo.fikri.dev",PASSWORD="Password123!"
```

```powershell
aws cognito-idp initiate-auth `
  --auth-flow USER_PASSWORD_AUTH `
  --client-id "1ak3tj1bn3neor7hgsjr1ml5h3" `
  --auth-parameters USERNAME="admin@demo.fikri.dev",PASSWORD="Password123!"
```

Expected response fields:
- `AuthenticationResult.AccessToken`
- `AuthenticationResult.IdToken`
- `AuthenticationResult.RefreshToken` (if enabled)
- `AuthenticationResult.ExpiresIn`
- `AuthenticationResult.TokenType` (Bearer)

Use either **AccessToken** or **IdToken**; the API validates `aud` or `client_id` against the configured client id.

---

## 5) Testing & verification

### 5.1 Step-by-step flow

1. Start API:
   - `npm run dev --workspace apps/backend-api-v2`
2. Get tokens via `initiate-auth` for each user.
3. Call endpoints with curl:

```bash
curl -i http://localhost:3000/admin/health -H "Authorization: Bearer <TOKEN>"
curl -i http://localhost:3000/driver/health -H "Authorization: Bearer <TOKEN>"
curl -i http://localhost:3000/passenger/health -H "Authorization: Bearer <TOKEN>"
```

```powershell
$token = "eyJraWQiOiJFeHBXa0pqZ1RTR1lZMHVnaVBcLzFjU0FUXC9xMEVYT2ZNQW9vWWFDUVwvQW9zPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiJjOWZhOTUyYy0xMDIxLTcwZjUtMWJmNi1mZTYzNDdhOWJjYzEiLCJjb2duaXRvOmdyb3VwcyI6WyJBRE1JTiJdLCJpc3MiOiJodHRwczpcL1wvY29nbml0by1pZHAuYXAtc291dGhlYXN0LTEuYW1hem9uYXdzLmNvbVwvYXAtc291dGhlYXN0LTFfSm5wQXhBTERGIiwiY2xpZW50X2lkIjoiMWFrM3RqMWJuM25lb3I3aGdzanIxbWw1aDMiLCJvcmlnaW5fanRpIjoiNDFkNGNlZmYtMDI1Ny00N2FiLWFlMmItOTQ2OWNlYmNhYzM1IiwiZXZlbnRfaWQiOiIyYzFlZGE4Ny02OTczLTQ3MjktYjBmNS1jNmEyMjMxM2RlZDIiLCJ0b2tlbl91c2UiOiJhY2Nlc3MiLCJzY29wZSI6ImF3cy5jb2duaXRvLnNpZ25pbi51c2VyLmFkbWluIiwiYXV0aF90aW1lIjoxNzY5OTQwNDg3LCJleHAiOjE3Njk5NDQwODcsImlhdCI6MTc2OTk0MDQ4NywianRpIjoiYzAwNGI5MTYtOGY4Ny00MTZhLWFhMGMtMDU4ODZhY2JjZGU4IiwidXNlcm5hbWUiOiJjOWZhOTUyYy0xMDIxLTcwZjUtMWJmNi1mZTYzNDdhOWJjYzEifQ.BtnN6u2Ynd8BwGH30SYkWJzNNje2u4EW4HtpNNkYTzWXe1RbeKFpIC5-S6zF36m68AZQIRHkNeRdRlCDmTTGzduHlxdOxtThK36ZNtB4YE8wLjSdGF7GwdjtJMJwGZFyI0vtzllqjZn_5l6hxlig3tyqxLPYZwO_bClLP1JU32KxMzV7ne2tJ9jgyOD0r4MnHXWmNZUn8oEIlS3uMNMSBpMZv6Mk3e5D7r0OrMAW960HByjiB8vvF8jE0qs-Yv0rjEKJmnTaAnwnrUHYgjXP2W6YiAVf5pdVaWZK9rIO6D244cov5nCqjQ45fAKUNQ3bsOIvYh03W--o5-YWsZuyrg"
Invoke-WebRequest -Uri "http://localhost:3000/admin/health" -Headers @{ Authorization = "Bearer $token" } -Method GET
Invoke-WebRequest -Uri "http://localhost:3000/driver/health" -Headers @{ Authorization = "Bearer $token" } -Method GET
Invoke-WebRequest -Uri "http://localhost:3000/passenger/health" -Headers @{ Authorization = "Bearer $token" } -Method GET
```

### 5.2 Test matrix

- ADMIN token → `/admin/health` → 200
- DRIVER token → `/admin/health` → 403
- PASSENGER token → `/driver/health` → 403
- No token → any protected endpoint → 401
- Expired token → any protected endpoint → 401

### 5.3 Postman

- Header: `Authorization: Bearer <token>`

---

## 6) Security notes (common mistakes)

- Do not accept unsigned JWTs (alg=none). Use `jwtVerify` with JWKS.
- Always validate `iss` and `aud`/`client_id`.
- Never trust frontend-provided “role/group” fields; only trust **verified JWT claims**.
- Do not leak JWT validation errors to clients (kid not found, signature mismatch, etc.).
- Be explicit about which endpoints require which system group; default deny when metadata is missing.

---

## 7) Acceptance checklist (Phase A complete)

- API rejects missing/invalid/expired JWTs with 401.
- API rejects valid JWTs with wrong system group with 403.
- Controllers use `@SystemGroup(...)` and `UseGuards(JwtAuthGuard, SystemGroupGuard)`.
- Env vars are validated at startup.
- Dev Cognito seed commands are documented and reproducible.
