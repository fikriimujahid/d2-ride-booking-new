import { Injectable } from '@nestjs/common';
import { AdminUserStatus } from '@prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { PermissionKey, PermissionResolution } from './permission.types';

function uniq<T>(items: readonly T[]): T[] {
  return Array.from(new Set(items));
}

export function permissionMatches(required: PermissionKey, granted: PermissionKey): boolean {
  if (granted === '*') return true;
  // A required wildcard is not used by our decorators; treat it as non-match.
  if (required === '*') return false;

  // Segment wildcard support: "resource:*" matches "resource:action"
  const [reqRes, reqAct] = required.split(':');
  const [grRes, grAct] = granted.split(':');

  if (!reqRes || !reqAct || !grRes || !grAct) return false;

  const resOk = grRes === '*' || grRes === reqRes;
  const actOk = grAct === '*' || grAct === reqAct;

  return resOk && actOk;
}

@Injectable()
export class PermissionService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveForAdminCognitoSub(cognitoSub: string): Promise<PermissionResolution | null> {
    const admin = await this.prisma.adminUser.findFirst({
      where: {
        cognitoSub,
        deletedAt: null
      },
      select: {
        id: true,
        status: true
      }
    });

    if (!admin) return null;
    if (admin.status !== AdminUserStatus.ACTIVE) return null;

    const roles = await this.prisma.adminUserRole.findMany({
      where: { adminUserId: admin.id },
      select: { role: { select: { id: true, name: true, deletedAt: true } } }
    });

    const roleNames = roles
      .map((r) => r.role)
      .filter((r) => r.deletedAt === null)
      .map((r) => r.name);

    const roleIds = roles
      .map((r) => r.role)
      .filter((r) => r.deletedAt === null)
      .map((r) => r.id);

    if (roleIds.length === 0) {
      return {
        adminUserId: admin.id,
        roleNames: [],
        grantedPermissions: []
      };
    }

    const perms = await this.prisma.rolePermission.findMany({
      where: { roleId: { in: roleIds } },
      select: { permission: { select: { key: true, deletedAt: true } } }
    });

    const grantedPermissions = uniq(
      perms
        .map((p) => p.permission)
        .filter((p) => p.deletedAt === null)
        .map((p) => p.key as PermissionKey)
    );

    return {
      adminUserId: admin.id,
      roleNames: uniq(roleNames),
      grantedPermissions
    };
  }

  isAllowed(requiredAnyOf: readonly PermissionKey[], resolution: PermissionResolution): boolean {
    if (requiredAnyOf.length === 0) return false;

    for (const required of requiredAnyOf) {
      for (const granted of resolution.grantedPermissions) {
        if (permissionMatches(required, granted)) return true;
      }
    }

    return false;
  }
}
