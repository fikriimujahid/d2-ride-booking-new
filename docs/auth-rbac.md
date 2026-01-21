# Authorization Model - Ride Booking Platform

**Phase 3: JWT-based Role-Based Access Control (RBAC)**

## Overview

The ride booking platform uses **AWS Cognito** for authentication and a custom **JWT-based authorization model** for role-based access control. This document explains how users authenticate, how roles are managed, and how the backend enforces authorization.

---

## Authentication Flow

### 1. User Registration
```
Frontend → Cognito: SignUp (email, password)
Cognito → User: Verification email
User → Cognito: Confirm email
Admin → Cognito: Set custom:role attribute (ADMIN, DRIVER, or PASSENGER)
```

**Key Points:**
- Users register with **email** and **password** (no username required)
- Email is **auto-verified** via Cognito verification email
- Custom attribute `role` is set **after** email verification (admin operation or self-service)
- No Hosted UI is used; frontend handles all auth UI

### 2. User Login
```
Frontend → Cognito: InitiateAuth (email, password)
Cognito → Frontend: JWT tokens (access_token, id_token, refresh_token)
Frontend → Backend API: HTTP requests with Authorization: Bearer <access_token>
Backend → Backend: Validate JWT + Extract custom:role claim
Backend → Backend: Enforce RBAC based on role
```

**Key Points:**
- Frontend uses `USER_PASSWORD_AUTH` flow (no OAuth, no Hosted UI)
- Cognito returns **three tokens**:
  - `access_token`: For API authorization (1 hour validity)
  - `id_token`: Contains user identity and custom claims (1 hour validity)
  - `refresh_token`: To obtain new access/id tokens (30 days validity)
- Frontend stores tokens securely (HTTP-only cookies recommended)

### 3. Token Refresh
```
Frontend → Cognito: InitiateAuth (REFRESH_TOKEN_AUTH, refresh_token)
Cognito → Frontend: New access_token + id_token
Frontend → Backend API: Requests continue with new tokens
```

**Key Points:**
- Refresh tokens allow seamless session extension without re-login
- Access tokens are short-lived (1 hour) to limit exposure
- Backend always validates token freshness and signature

---

## JWT Token Structure

### Access Token (for API authorization)
```json
{
  "sub": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "cognito:username": "user@example.com",
  "iss": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_XXXXX",
  "client_id": "abc123xyz",
  "origin_jti": "...",
  "event_id": "...",
  "token_use": "access",
  "scope": "aws.cognito.signin.user.admin",
  "auth_time": 1234567890,
  "exp": 1234571490,
  "iat": 1234567890,
  "jti": "...",
  "username": "user@example.com"
}
```

### ID Token (contains user claims and custom:role)
```json
{
  "sub": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "email_verified": true,
  "iss": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_XXXXX",
  "cognito:username": "user@example.com",
  "custom:role": "DRIVER",
  "origin_jti": "...",
  "aud": "abc123xyz",
  "event_id": "...",
  "token_use": "id",
  "auth_time": 1234567890,
  "exp": 1234571490,
  "iat": 1234567890,
  "email": "user@example.com"
}
```

**Important:** The `custom:role` claim is **only present in the ID token**, not the access token.

---

## Role Definitions

### ADMIN
**Capabilities:**
- Manage all users (view, create, update, delete)
- Manage all bookings (view, modify, cancel)
- Manage all drivers (approve, suspend)
- View analytics and reports
- System configuration

**Use Cases:**
- Platform administrators
- Customer support agents
- Operations managers

### DRIVER
**Capabilities:**
- View own profile
- Accept/reject ride requests
- Update ride status (en route, arrived, completed)
- View earnings and trip history
- Update availability status

**Use Cases:**
- Registered drivers on the platform

### PASSENGER
**Capabilities:**
- View own profile
- Book rides
- View ride history
- Rate drivers
- Cancel bookings (within policy)

**Use Cases:**
- End users booking rides

---

## Backend Authorization Implementation

### 1. JWT Validation Middleware (NestJS)

```typescript
// src/auth/jwt.strategy.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import * as jwksClient from 'jwks-rsa';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private configService: ConfigService) {
    super({
      jwtFromRequest: (req) => {
        // Extract JWT from Authorization header
        const authHeader = req.headers.authorization;
        if (!authHeader) return null;
        return authHeader.replace('Bearer ', '');
      },
      
      // Validate signature using Cognito public keys
      secretOrKeyProvider: jwksClient.passportJwtSecret({
        cache: true,
        rateLimit: true,
        jwksUri: configService.get('COGNITO_JWKS_URI'),
      }),
      
      // Validate issuer
      issuer: configService.get('COGNITO_ISSUER'),
      
      // Validate audience (app client ID)
      audience: configService.get('COGNITO_CLIENT_ID'),
      
      algorithms: ['RS256'],
    });
  }

  async validate(payload: any) {
    // Extract role from custom:role claim
    const role = payload['custom:role'];
    
    if (!role || !['ADMIN', 'DRIVER', 'PASSENGER'].includes(role)) {
      throw new UnauthorizedException('Invalid or missing role');
    }

    // Return user context (available in request.user)
    return {
      userId: payload.sub,
      email: payload.email,
      role: role,
    };
  }
}
```

### 2. Role-Based Authorization Guards

```typescript
// src/auth/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const Roles = (...roles: string[]) => SetMetadata('roles', roles);
```

```typescript
// src/auth/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.get<string[]>('roles', context.getHandler());
    if (!requiredRoles) {
      return true; // No role restriction
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user; // Set by JwtStrategy

    return requiredRoles.includes(user.role);
  }
}
```

### 3. Controller Example

```typescript
// src/bookings/bookings.controller.ts
import { Controller, Get, Post, Body, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { CurrentUser } from '../auth/current-user.decorator';

@Controller('bookings')
@UseGuards(AuthGuard('jwt'), RolesGuard)
export class BookingsController {
  
  // PASSENGER can create bookings
  @Post()
  @Roles('PASSENGER')
  createBooking(@Body() createBookingDto: CreateBookingDto, @CurrentUser() user) {
    return this.bookingsService.create(createBookingDto, user.userId);
  }

  // DRIVER can view assigned bookings
  @Get('assigned')
  @Roles('DRIVER')
  getAssignedBookings(@CurrentUser() user) {
    return this.bookingsService.findByDriver(user.userId);
  }

  // ADMIN can view all bookings
  @Get('all')
  @Roles('ADMIN')
  getAllBookings() {
    return this.bookingsService.findAll();
  }
}
```

---

## Environment Configuration

### Backend API (NestJS) - `.env`

```bash
# Cognito Configuration
COGNITO_USER_POOL_ID=ap-southeast-1_XXXXX
COGNITO_CLIENT_ID=abc123xyz
COGNITO_REGION=ap-southeast-1
COGNITO_JWKS_URI=https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_XXXXX/.well-known/jwks.json
COGNITO_ISSUER=https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_XXXXX

# Database (RDS MySQL)
# In AWS, prefer IAM DB Authentication (no static DB password).
DB_HOST=<rds-endpoint>
DB_PORT=3306
DB_NAME=ridebooking
DB_USER=app_user

# Recommended on AWS
DB_IAM_AUTH=true
DB_SSL=true
DB_SSL_REJECT_UNAUTHORIZED=true
# Optional (if your instance/Node trust store doesn't validate the RDS cert chain)
# DB_SSL_CA_PATH=/opt/d2/shared/aws-rds-global-bundle.pem
```

**Note:** With IAM DB authentication, the backend generates short-lived auth tokens using the EC2 instance role.

### Frontend (React/Next.js) - `.env.local`

```bash
# Cognito Configuration (PUBLIC - not sensitive)
NEXT_PUBLIC_COGNITO_USER_POOL_ID=ap-southeast-1_XXXXX
NEXT_PUBLIC_COGNITO_CLIENT_ID=abc123xyz
NEXT_PUBLIC_COGNITO_REGION=ap-southeast-1

# API Endpoint
NEXT_PUBLIC_API_URL=https://api.d2.fikri.dev
```

---

## Security Best Practices

### ✅ DO
- **Validate JWT signature** using Cognito public keys (JWKS)
- **Validate issuer** (`iss` claim) to prevent token reuse from other Cognito pools
- **Validate audience** (`aud` claim) to ensure token is for your app client
- **Check token expiration** (`exp` claim) on every request
- **Extract role from `custom:role`** claim in ID token
- **Use HTTPS** for all API requests
- **Store tokens securely** (HTTP-only cookies or secure storage)
- **Implement token refresh** before expiration
- **Log authorization failures** for security monitoring

### ❌ DON'T
- **Don't trust the `role` claim without validating JWT signature**
- **Don't use Cognito Groups** (we use `custom:role` instead for simplicity)
- **Don't store tokens in localStorage** (vulnerable to XSS)
- **Don't expose sensitive user data** in frontend code
- **Don't allow role changes without admin approval**
- **Don't use long-lived tokens** in production (current: 1 hour)

---

## Role Assignment Strategy

### Initial User Registration
1. User signs up via frontend (email + password)
2. Cognito creates user account
3. Cognito sends verification email
4. User confirms email
5. **Admin manually assigns role** via Cognito Console or AWS CLI

**Example: Assign DRIVER role**
```bash
aws cognito-idp admin-update-user-attributes \
  --user-pool-id ap-southeast-1_XXXXX \
  --username user@example.com \
  --user-attributes Name=custom:role,Value=DRIVER
```

### Future Enhancement (Phase 4+)
- **Self-service role selection** during signup (with approval workflow)
- **Driver onboarding flow** (document verification + admin approval)
- **Role upgrade** (PASSENGER → DRIVER after verification)

---

## Authorization Matrix

| Endpoint                  | ADMIN | DRIVER | PASSENGER | Notes                          |
|---------------------------|-------|--------|-----------|--------------------------------|
| POST /auth/signup         | ✓     | ✓      | ✓         | Public endpoint                |
| POST /auth/login          | ✓     | ✓      | ✓         | Public endpoint                |
| GET /users                | ✓     | ✗      | ✗         | View all users                 |
| GET /users/:id            | ✓     | ✓*     | ✓*        | * Own profile only             |
| POST /bookings            | ✓     | ✗      | ✓         | Create booking                 |
| GET /bookings             | ✓     | ✗      | ✓*        | * Own bookings only            |
| GET /bookings/assigned    | ✓     | ✓      | ✗         | Assigned to driver             |
| PATCH /bookings/:id/status| ✓     | ✓      | ✗         | Update ride status             |
| POST /rides/accept        | ✓     | ✓      | ✗         | Accept ride request            |
| GET /analytics            | ✓     | ✗      | ✗         | System analytics               |

**Legend:**
- ✓ = Allowed
- ✗ = Forbidden
- ✓* = Allowed with restrictions (e.g., own resources only)

---

## Testing Authorization

### 1. Create Test Users

**Admin User:**
```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-southeast-1_XXXXX \
  --username admin@fikri.dev \
  --user-attributes Name=email,Value=admin@fikri.dev Name=custom:role,Value=ADMIN \
  --temporary-password TempPass123!
```

**Driver User:**
```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-southeast-1_XXXXX \
  --username driver@fikri.dev \
  --user-attributes Name=email,Value=driver@fikri.dev Name=custom:role,Value=DRIVER \
  --temporary-password TempPass123!
```

**Passenger User:**
```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-southeast-1_XXXXX \
  --username passenger@fikri.dev \
  --user-attributes Name=email,Value=passenger@fikri.dev Name=custom:role,Value=PASSENGER \
  --temporary-password TempPass123!
```

### 2. Test Login Flow

```bash
# Login as DRIVER
curl -X POST https://cognito-idp.ap-southeast-1.amazonaws.com/ \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  -d '{
    "ClientId": "abc123xyz",
    "AuthFlow": "USER_PASSWORD_AUTH",
    "AuthParameters": {
      "USERNAME": "driver@fikri.dev",
      "PASSWORD": "YourPassword123!"
    }
  }'
```

Response contains `IdToken`, `AccessToken`, and `RefreshToken`.

### 3. Test API Authorization

```bash
# Test DRIVER accessing driver-only endpoint (should succeed)
curl -X GET https://api.d2.fikri.dev/bookings/assigned \
  -H "Authorization: Bearer <ID_TOKEN>"

# Test DRIVER accessing admin endpoint (should fail with 403)
curl -X GET https://api.d2.fikri.dev/users \
  -H "Authorization: Bearer <ID_TOKEN>"
```

---

## Troubleshooting

### "Invalid or missing role" error
**Cause:** `custom:role` attribute not set or invalid value.

**Solution:**
```bash
aws cognito-idp admin-update-user-attributes \
  --user-pool-id ap-southeast-1_XXXXX \
  --username user@example.com \
  --user-attributes Name=custom:role,Value=DRIVER
```

### "Token signature verification failed"
**Cause:** Incorrect JWKS URI or expired token.

**Solution:**
1. Verify `COGNITO_JWKS_URI` matches your User Pool
2. Ensure token is not expired (`exp` claim)
3. Check system clock synchronization

### "Forbidden" (403) error
**Cause:** User role doesn't have permission for the endpoint.

**Solution:**
1. Verify user has correct role (`custom:role` claim)
2. Check endpoint's `@Roles()` decorator
3. Ensure `RolesGuard` is applied to the controller

---

## References

- [AWS Cognito User Pools Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
- [JWT.io - Decode and verify JWTs](https://jwt.io/)
- [NestJS Authentication](https://docs.nestjs.com/security/authentication)
- [Passport JWT Strategy](http://www.passportjs.org/packages/passport-jwt/)

---

**Document Version:** 1.0  
**Last Updated:** Phase 3 - January 2026  
**Next Review:** Phase 4 (Backend API Implementation)
