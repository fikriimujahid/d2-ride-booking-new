# Phase C — IAM Admin APIs (CRUD + Assignments)

## Why this design (architecture)

### Permissions are the only enforcement primitive
- The backend enforces access via `@RequirePermissions('<module>:<action>')` on **every** handler.
- Roles are purely data containers that group permissions. They have **no** special meaning in code.
- Access decisions are made by resolving effective permissions from the database (AdminUser → Roles → RolePermissions → Permissions).

### SUPER_ADMIN is data-only (not hardcoded)
- `SUPER_ADMIN` works only because seed data assigns **all** permission keys to that role.
- There is **no role-name check** in authorization.
- Removing a permission mapping from DB takes effect immediately on the next request (request-scoped cache only).

### Default deny
- `RbacGuard` fails closed if `@RequirePermissions()` is missing.
- Missing/disabled/unprovisioned admin users resolve to `403`.

## Modules and routes

All routes are **ADMIN system group only** and protected by:
- `JwtAuthGuard` (Cognito JWT)
- `SystemGroupGuard` (must include ADMIN)
- `RbacGuard` (permission enforcement)

### Admin Users
Base path: `/admin/admin-users`
- `GET /` → list (`admin-user:view`)
- `GET /:id` → detail (`admin-user:read`)
- `POST /` → create (`admin-user:create`)
- `PUT /:id` → update (`admin-user:update`)
- `DELETE /:id` → soft delete (`admin-user:delete`)
- `POST /:id/roles` → replace role assignments (`admin-user:assign-role`)

### Roles
Base path: `/admin/roles`
- `GET /` → list (`role:view`)
- `GET /:id` → detail (`role:read`)
- `POST /` → create (`role:create`)
- `PUT /:id` → update (`role:update`)
- `DELETE /:id` → soft delete (`role:delete`)
- `POST /:id/permissions` → replace permission assignments (`role:assign-permission`)

### Permissions
Base path: `/admin/permissions`
- `GET /` → list (`permission:view`)
- `GET /:id` → detail (`permission:read`)
- `POST /` → create (`permission:create`)
- `PUT /:id` → update (`permission:update`)
- `DELETE /:id` → soft delete (`permission:delete`)

## Assignment behavior (replace semantics)

- Admin user roles (`admin_user_roles`): `POST /admin/admin-users/:id/roles` deletes existing mappings then inserts the provided `roleIds` in a transaction.
- Role permissions (`role_permissions`): `POST /admin/roles/:id/permissions` deletes existing mappings then inserts the provided `permissionIds` in a transaction.

Both endpoints:
- Validate all IDs exist and are not soft-deleted.
- Are idempotent when called with the same set.

## Deletion safety strategy

Soft delete is implemented via `deletedAt`.
- Roles: deleting is blocked if assigned to any non-deleted admin user.
- Permissions: deleting is blocked if assigned to any non-deleted role.

## Audit logging

All mutations emit an audit row in `admin_audit_logs` via `AuditService.logRbacAction`.

Audit fields:
- `actorAdminUserId`
- `action`
- `targetType`
- `targetId`
- `before` / `after` (JSON)
- `createdAt`
- `ipAddress`, `userAgent`, `requestId`

## DEV seed

Seed file: `prisma/seed.ts`

Creates:
1) All required permissions
2) Role `SUPER_ADMIN`
3) Maps all permissions to `SUPER_ADMIN`
4) Admin user:
   - email: `superadmin@test.d2.fikri.dev`
   - cognitoSub: `SEED_SUPERADMIN_COGNITO_SUB` (default `local-superadmin-sub`)
   - role: `SUPER_ADMIN`

Run:
- `npm run db:seed`

## Curl examples

> Assumes API is on `http://localhost:3000` and you have a Cognito JWT in `$TOKEN`.

List roles:
```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:3000/admin/roles
```

Create permission:
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"key":"driver:read","description":"Read drivers"}' \
  http://localhost:3000/admin/permissions
```

Replace role permissions:
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"permissionIds":["<perm-uuid-1>","<perm-uuid-2>"]}' \
  http://localhost:3000/admin/roles/<role-uuid>/permissions
```

Replace admin user roles:
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"roleIds":["<role-uuid>"]}' \
  http://localhost:3000/admin/admin-users/<admin-uuid>/roles
```

## Manual test matrix (high value)

1) SUPER_ADMIN can CRUD
- With SUPER_ADMIN role assigned all permissions:
  - Can list/create/update/delete permissions
  - Can list/create/update/delete roles
  - Can list/create/update/delete admin users
  - Can assign permissions to role
  - Can assign roles to admin user

2) Remove permission → immediate denial
- Remove `role_permissions` mapping for e.g. `permission:delete`.
- Re-run `DELETE /admin/permissions/:id`.
- Expect `403 Forbidden` immediately.

3) Non-authorized admin → 403
- Create an admin user with **no roles**, or with a role that lacks required permission.
- Call any protected endpoint.
- Expect `403 Forbidden`.

## Acceptance checklist

- No role-name checks in access decisions
- Permissions resolved from DB and enforced server-side on every handler
- Missing permission metadata fails closed
- SUPER_ADMIN is data-only (works only via DB mappings)
- Assignments replace existing mappings in transactions
- Soft delete implemented for admin users/roles/permissions
- Deletes prevented when entity is in use (role assigned to admin / permission assigned to role)
- Audit logs created for all CRUD + assignment operations
