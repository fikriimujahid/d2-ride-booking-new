import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { AdminUserStatus } from '@prisma/client';
import type { AuthenticatedUser } from '../../auth/interfaces/authenticated-user';
import { PrismaService } from '../../database/prisma.service';
import { buildModuleAccessMap, parsePermissionKey } from './permission.parser';
import type { AdminAccessContext } from './types';

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function getDisplayName(user: AuthenticatedUser): string {
  const claims = user.claims as Record<string, unknown>;

  const name = claims.name;
  if (isNonEmptyString(name)) return name.trim();

  const given = claims.given_name;
  const family = claims.family_name;
  if (isNonEmptyString(given) && isNonEmptyString(family)) return `${given.trim()} ${family.trim()}`;
  if (isNonEmptyString(given)) return given.trim();

  return user.email;
}

function uniqueSorted(values: readonly string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

@Injectable()
export class AccessContextService {
  constructor(private readonly prisma: PrismaService) {}

  async getAdminMe(authUser: AuthenticatedUser): Promise<AdminAccessContext> {
    if (!authUser?.userId) throw new UnauthorizedException('Unauthorized');

    const admin = await this.prisma.adminUser.findFirst({
      where: {
        cognitoSub: authUser.userId,
        deletedAt: null,
        status: AdminUserStatus.ACTIVE
      },
      select: { id: true, email: true }
    });

    if (!admin) {
      // Authenticated as ADMIN group, but not provisioned for admin RBAC.
      throw new ForbiddenException('Forbidden');
    }

    const assignments = await this.prisma.adminUserRole.findMany({
      where: {
        adminUserId: admin.id,
        role: { deletedAt: null }
      },
      select: {
        role: { select: { id: true, name: true } }
      }
    });

    const roleNames = uniqueSorted(assignments.map((x) => x.role.name));

    const roleIds = uniqueSorted(assignments.map((x) => x.role.id));

    // Resolve effective permissions from DB role assignments (no role-name logic).
    let grantedPermissionKeys: string[] = [];
    if (roleIds.length > 0) {
      const rows = await this.prisma.rolePermission.findMany({
        where: {
          roleId: { in: roleIds },
          permission: { deletedAt: null }
        },
        select: {
          permission: { select: { key: true } }
        }
      });

      // Keep raw keys (including wildcard '*') so the UI snapshot matches RBAC enforcement.
      grantedPermissionKeys = uniqueSorted(rows.map((r) => r.permission.key));
    }

    // Universe of modules/actions comes from DB permission catalog.
    const catalog = await this.prisma.permission.findMany({
      where: { deletedAt: null },
      select: { key: true }
    });

    const allPermissionKeys = catalog.map((p) => p.key);
    const modules = buildModuleAccessMap({
      allPermissionKeys,
      grantedPermissionKeys
    });

    return {
      user: {
        id: admin.id,
        email: admin.email,
        name: getDisplayName(authUser)
      },
      roles: roleNames,
      permissions: grantedPermissionKeys,
      modules
    };
  }
}
