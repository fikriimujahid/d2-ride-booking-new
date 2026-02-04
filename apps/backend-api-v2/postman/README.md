# IAM Admin APIs - Postman Collection

## Import to Postman

1. Open Postman
2. Click **Import** (top-left)
3. Select `IAM-Admin-APIs.postman_collection.json`
4. Collection will appear in your sidebar

## Authentication Setup

### Get Cognito JWT Token

You need a valid Cognito JWT token with:
- `cognito:groups` claim containing `admin`
- Valid user in the Cognito User Pool configured in `.env`

**Option 1: AWS Cognito Hosted UI (easiest)**
1. Navigate to your Cognito Hosted UI login page
2. Sign in with admin credentials
3. Copy the `id_token` from the redirect URL or browser storage

**Option 2: AWS CLI (for testing)**
```bash
aws cognito-idp initiate-auth \
  --region ap-southeast-1 \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id YOUR_COGNITO_APP_CLIENT_ID \
  --auth-parameters USERNAME=admin@example.com,PASSWORD=YourPassword123!
```
Copy the `IdToken` from the response.

**Option 3: AWS SDK (programmatic)**
```javascript
import { CognitoIdentityProviderClient, InitiateAuthCommand } from '@aws-sdk/client-cognito-identity-provider';

const client = new CognitoIdentityProviderClient({ region: 'ap-southeast-1' });
const command = new InitiateAuthCommand({
  AuthFlow: 'USER_PASSWORD_AUTH',
  ClientId: 'YOUR_CLIENT_ID',
  AuthParameters: {
    USERNAME: 'admin@example.com',
    PASSWORD: 'YourPassword123!'
  }
});
const response = await client.send(command);
const token = response.AuthenticationResult.IdToken;
```

### Configure Collection Variables

1. In Postman, select the **IAM Admin APIs** collection
2. Click **Variables** tab
3. Set values:
   - `BASE_URL`: `http://localhost:3000` (or your API URL)
   - `COGNITO_JWT`: paste your JWT token here
4. Click **Save**

The collection inherits bearer token authentication from these variables.

## Test the Seed Data

After running `npm run db:seed`, you'll have:
- Admin user: `admin@demo.fikri.dev` (or `superadmin@test.d2.fikri.dev`)
- Role: `SUPER_ADMIN`
- All IAM admin permissions assigned

To test:
1. Get a Cognito JWT for the seeded admin user's `cognitoSub`
2. Set `COGNITO_JWT` in Postman
3. Try `GET /admin/me` first to verify authentication
4. Try any IAM endpoint (you should have all permissions)

## Example Workflow

### 1. Verify your access
```
GET /admin/me
```
Response shows your roles, permissions, and module access.

### 2. Create a new permission
```
POST /admin/permissions
{
  "key": "driver:read",
  "description": "Read driver data"
}
```

### 3. Create a new role
```
POST /admin/roles
{
  "name": "DRIVER_SUPPORT",
  "description": "Can view and manage drivers"
}
```

### 4. Assign permissions to the role
```
POST /admin/roles/:roleId/permissions
{
  "permissionIds": ["<permission-uuid-1>", "<permission-uuid-2>"]
}
```

### 5. Create an admin user
```
POST /admin/admin-users
{
  "cognitoSub": "cognito-user-sub-uuid",
  "email": "support@example.com",
  "status": "ACTIVE"
}
```

### 6. Assign roles to the admin user
```
POST /admin/admin-users/:userId/roles
{
  "roleIds": ["<role-uuid>"]
}
```

## Notes

- All endpoints require `Authorization: Bearer <JWT>` header (auto-configured)
- Replace UUID placeholders (`:id`, `roleIds`, `permissionIds`) with real values from your DB
- Soft delete endpoints set `deletedAt`; list endpoints filter `deletedAt: null`
- Assignment endpoints use **replace semantics** (transaction-safe)
- Delete operations are blocked when entities are in use (role assigned to user / permission assigned to role)

## Troubleshooting

**401 Unauthorized**
- Token expired (Cognito JWTs typically last 1 hour)
- Invalid token format
- Missing `cognito:groups` claim with `admin`

**403 Forbidden**
- Missing required permission for the endpoint
- Admin user not provisioned in DB (check `admin_user` table)
- Admin user status is `DISABLED` or `deletedAt` is set

**404 Not Found**
- Invalid UUID in path parameter
- Entity was soft-deleted

## Useful Queries

Get all role IDs:
```sql
SELECT id, name FROM Role WHERE deletedAt IS NULL;
```

Get all permission IDs:
```sql
SELECT id, key FROM Permission WHERE deletedAt IS NULL;
```

Get admin user's current roles:
```sql
SELECT r.id, r.name 
FROM AdminUserRole aur
JOIN Role r ON aur.roleId = r.id
WHERE aur.adminUserId = '<admin-uuid>' AND r.deletedAt IS NULL;
```
