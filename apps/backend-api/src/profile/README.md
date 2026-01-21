# Profile Module

Authenticated CRUD endpoints for user profiles with dual persistence: MySQL (authoritative) + Cognito (sync).

## Endpoints

All endpoints require JWT authentication (Authorization: Bearer <token>).

### POST /profile
Create profile for authenticated user.

**Request Body:**
```json
{
  "email": "user@example.com",
  "phone_number": "+1234567890",
  "full_name": "John Doe",
  "role": "PASSENGER"
}
```

**Response:** Profile object

### GET /profile
Get current user's profile.

**Response:**
```json
{
  "id": "uuid",
  "user_id": "cognito-sub",
  "email": "user@example.com",
  "phone_number": "+1234567890",
  "full_name": "John Doe",
  "role": "PASSENGER",
  "created_at": "2026-01-19T00:00:00.000Z",
  "updated_at": "2026-01-19T00:00:00.000Z"
}
```

### PUT /profile
Update current user's profile (all fields optional).

**Request Body:**
```json
{
  "email": "newemail@example.com",
  "phone_number": "+0987654321",
  "full_name": "Jane Doe",
  "role": "DRIVER"
}
```

**Response:** Updated profile object

### DELETE /profile
Delete current user's profile.

**Response:** 204 No Content

## Database Migration

Run the migration to create the profiles table:

```bash
# Connect to RDS using IAM auth or master credentials
mysql -h <rds-endpoint> -u admin -p < migrations/001_create_profiles_table.sql
```

## Cognito Sync

Profile updates automatically sync to Cognito user attributes:
- `email` → Cognito email
- `phone_number` → Cognito phone_number
- `full_name` → Cognito name
- `role` → Cognito custom:role

Sync failures are logged but don't block operations (database is source of truth).
