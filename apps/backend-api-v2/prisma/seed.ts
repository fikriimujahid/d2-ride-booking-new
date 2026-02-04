/// <reference types="node" />

import 'dotenv/config';
import { Prisma, PrismaClient } from '@prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import { Signer } from '@aws-sdk/rds-signer';

type DbAuthMode = 'static' | 'iam';

type SeedRoleName = 'SUPER_ADMIN';

type SeedPermissionKey = `${string}:${string}`;

const DATABASE_URL_FALLBACK = 'mysql://root:password@localhost:3306/d2_rbac_dev';

const PERMISSIONS: readonly SeedPermissionKey[] = [
  // ADMIN USER
  'admin-user:view',
  'admin-user:read',
  'admin-user:create',
  'admin-user:update',
  'admin-user:delete',
  'admin-user:assign-role',

  // ROLE
  'role:view',
  'role:read',
  'role:create',
  'role:update',
  'role:delete',
  'role:assign-permission',

  // PERMISSION
  'permission:view',
  'permission:read',
  'permission:create',
  'permission:update',
  'permission:delete'
] as const;

const ROLE_PERMISSIONS: Readonly<Record<SeedRoleName, readonly SeedPermissionKey[]>> = {
  SUPER_ADMIN: PERMISSIONS
} as const;

function mustGetEnv(key: string): string {
  const value = process.env[key];
  if (!value || value.trim().length === 0) throw new Error(`Missing env var: ${key}`);
  return value.trim();
}

function getAuthMode(): DbAuthMode {
  const mode = process.env.DB_AUTH_MODE?.trim().toLowerCase();
  return mode === 'iam' ? 'iam' : 'static';
}

function getRegion(): string {
  return (
    process.env.DB_IAM_REGION?.trim() ||
    process.env.AWS_REGION?.trim() ||
    process.env.AWS_DEFAULT_REGION?.trim() ||
    process.env.COGNITO_REGION?.trim() ||
    ''
  );
}

function parsePort(value: string | undefined, defaultPort: number): number {
  const port = value ? Number(value) : defaultPort;
  return Number.isFinite(port) && port > 0 ? port : defaultPort;
}

function parseBoolean(value: unknown, defaultValue: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'string') return defaultValue;

  const normalized = value.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return defaultValue;
}

async function createPrismaClient(): Promise<PrismaClient> {
  const mode = getAuthMode();
  if (mode === 'static') {
    const url = process.env.DATABASE_URL?.trim() || DATABASE_URL_FALLBACK;
    return new PrismaClient({ adapter: new PrismaMariaDb(url) });
  }

  const host = mustGetEnv('DB_HOST');
  const dbName = mustGetEnv('DB_NAME');
  const username = mustGetEnv('DB_USER');
  const port = parsePort(process.env.DB_PORT, 3306);

  const region = getRegion();
  if (!region) throw new Error('Missing region for IAM DB auth. Set DB_IAM_REGION or AWS_REGION.');

  const signer = new Signer({ hostname: host, port, username, region });
  const token = await signer.getAuthToken();

  const requireSsl = parseBoolean(process.env.DB_IAM_REQUIRE_SSL, true);
  const query = requireSsl ? '?ssl=true' : '';

  const url = `mysql://${encodeURIComponent(username)}:${encodeURIComponent(token)}@${host}:${port}/${dbName}${query}`;
  return new PrismaClient({ adapter: new PrismaMariaDb(url) });
}

async function main() {
  const prisma = await createPrismaClient();
  const seedAdminCognitoSub = process.env.SEED_ADMIN_COGNITO_SUB?.trim();
  const seedAdminEmail = 'superadmin@test.d2.fikri.dev';
  const seedAdminRole: SeedRoleName = 'SUPER_ADMIN';

  await prisma.$transaction(async (tx: any) => {
    // 1) Upsert permissions
    const permissionRows = await Promise.all(
      PERMISSIONS.map((key) =>
        tx.permission.upsert({
          where: { key },
          update: { deletedAt: null },
          create: { key }
        })
      )
    );

    // 2) Upsert roles
    const roleRows = await Promise.all(
      (Object.keys(ROLE_PERMISSIONS) as SeedRoleName[]).map((name) =>
        tx.role.upsert({
          where: { name },
          update: { deletedAt: null },
          create: { name }
        })
      )
    );

    const permissionByKey = new Map(permissionRows.map((p) => [p.key, p] as const));
    const roleByName = new Map(roleRows.map((r) => [r.name as SeedRoleName, r] as const));

    // 3) Ensure role-permission mappings (replace-style: ensure all required exist)
    for (const roleName of Object.keys(ROLE_PERMISSIONS) as SeedRoleName[]) {
      const role = roleByName.get(roleName);
      if (!role) throw new Error(`Role missing after upsert: ${roleName}`);

      const keys = ROLE_PERMISSIONS[roleName];
      for (const key of keys) {
        const permRow = permissionByKey.get(key);
        if (!permRow) throw new Error(`Permission missing after upsert: ${key}`);

        await tx.rolePermission.upsert({
          where: { roleId_permissionId: { roleId: role.id, permissionId: permRow.id } },
          update: {},
          create: { roleId: role.id, permissionId: permRow.id }
        });
      }
    }

    // 4) Upsert admin user (mapped to Cognito sub)
    const admin = await tx.adminUser.upsert({
      where: { cognitoSub: seedAdminCognitoSub },
      update: { email: seedAdminEmail, status: 'ACTIVE', deletedAt: null },
      create: { cognitoSub: seedAdminCognitoSub, email: seedAdminEmail, status: 'ACTIVE' }
    });

    // 5) Ensure role assignment
    const assignedRole = roleByName.get(seedAdminRole);
    if (!assignedRole) throw new Error(`Invalid SEED_ADMIN_ROLE: ${seedAdminRole}`);

    await tx.adminUserRole.upsert({
      where: { adminUserId_roleId: { adminUserId: admin.id, roleId: assignedRole.id } },
      update: {},
      create: { adminUserId: admin.id, roleId: assignedRole.id }
    });

    // 6) Audit log (seed action)
    await tx.adminAuditLog.create({
      data: {
        actorAdminUserId: admin.id,
        action: 'rbac.seed',
        targetType: 'rbac',
        targetId: admin.id,
        before: null,
        after: { roleAssigned: seedAdminRole, permissions: PERMISSIONS }
      }
    });
  });

  // eslint-disable-next-line no-console
  console.log('RBAC seed complete');

  await prisma.$disconnect();
}

main()
  .catch(async (err) => {
    // eslint-disable-next-line no-console
    console.error(err);
    process.exitCode = 1;
  });
