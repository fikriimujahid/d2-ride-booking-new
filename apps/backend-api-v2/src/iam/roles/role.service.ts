// Import NestJS exception classes
import {
  ConflictException,
  Injectable,
  NotFoundException
} from '@nestjs/common';
// Import Express Request type
import type { Request } from 'express';
// Import audit service for logging changes
import { AuditService } from '../../audit/audit.service';
// Import Prisma service for database operations
import { PrismaService } from '../../database/prisma.service';

/**
 * Sort and deduplicate string array
 * @param values - Array of strings
 * @returns Sorted array with duplicates removed
 */
function uniqueSorted(values: readonly string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

/**
 * RoleService - Business logic for role CRUD operations
 * Handles role management with audit logging, permission assignment, and referential integrity
 */
@Injectable()
export class RoleService {
  /**
   * Constructor - injects dependencies
   * @param prisma - Database service
   * @param audit - Audit logging service
   */
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list() {
    return this.prisma.role.findMany({
      where: { deletedAt: null },
      orderBy: { name: 'asc' }
    });
  }

  async getById(id: string) {
    const role = await this.prisma.role.findFirst({
      where: { id, deletedAt: null },
      include: {
        permissions: {
          where: { permission: { deletedAt: null } },
          select: { permissionId: true, permission: { select: { id: true, key: true } } }
        }
      }
    });
    if (!role) throw new NotFoundException('Role not found');
    return role;
  }

  async create(params: {
    name: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const role = await this.prisma.role.create({
      data: { name: params.name, description: params.description }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.create',
      targetType: 'role',
      targetId: role.id,
      before: null,
      after: { id: role.id, name: role.name, description: role.description },
      request: params.request
    });

    return role;
  }

  async update(params: {
    id: string;
    name?: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const before = await this.prisma.role.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Role not found');

    const after = await this.prisma.role.update({
      where: { id: params.id },
      data: {
        name: params.name ?? undefined,
        description: params.description ?? undefined
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.update',
      targetType: 'role',
      targetId: after.id,
      before: { name: before.name, description: before.description },
      after: { name: after.name, description: after.description },
      request: params.request
    });

    return after;
  }

  async softDelete(params: { id: string; actorAdminUserId: string; request?: Request }) {
    const before = await this.prisma.role.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Role not found');

    const inUse = await this.prisma.adminUserRole.findFirst({
      where: {
        roleId: params.id,
        adminUser: { deletedAt: null }
      },
      select: { adminUserId: true }
    });
    if (inUse) throw new ConflictException('Role is assigned to an admin user');

    await this.prisma.role.update({
      where: { id: params.id },
      data: { deletedAt: new Date() }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.delete',
      targetType: 'role',
      targetId: params.id,
      before: { name: before.name, description: before.description },
      after: { deleted: true },
      request: params.request
    });
  }

  async replacePermissions(params: {
    roleId: string;
    permissionIds: readonly string[];
    actorAdminUserId: string;
    request?: Request;
  }) {
    const role = await this.prisma.role.findFirst({ where: { id: params.roleId, deletedAt: null } });
    if (!role) throw new NotFoundException('Role not found');

    const desired = uniqueSorted(params.permissionIds);

    const existing = await this.prisma.rolePermission.findMany({
      where: { roleId: params.roleId },
      select: { permissionId: true }
    });
    const beforePermissionIds = uniqueSorted(existing.map((x) => x.permissionId));

    if (desired.length > 0) {
      const found = await this.prisma.permission.findMany({
        where: { id: { in: desired }, deletedAt: null },
        select: { id: true }
      });
      if (found.length !== desired.length) throw new NotFoundException('One or more permissions not found');
    }

    await this.prisma.$transaction(async (tx: any) => {
      await tx.rolePermission.deleteMany({ where: { roleId: params.roleId } });
      if (desired.length > 0) {
        await tx.rolePermission.createMany({
          data: desired.map((permissionId) => ({ roleId: params.roleId, permissionId })),
          skipDuplicates: true
        });
      }
    });

    if (beforePermissionIds.join(',') === desired.join(',')) {
      // No-op replacement still OK; audit as idempotent update.
    }

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.assign',
      targetType: 'role',
      targetId: params.roleId,
      before: { permissionIds: beforePermissionIds },
      after: { permissionIds: desired },
      request: params.request
    });
  }
}
