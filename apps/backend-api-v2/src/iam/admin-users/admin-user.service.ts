import {
  ConflictException,
  Injectable,
  NotFoundException
} from '@nestjs/common';
import { AdminUserStatus } from '@prisma/client';
import type { Request } from 'express';
import { AuditService } from '../../audit/audit.service';
import { PrismaService } from '../../database/prisma.service';

function uniqueSorted(values: readonly string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

@Injectable()
export class AdminUserService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list() {
    return this.prisma.adminUser.findMany({
      where: { deletedAt: null },
      orderBy: { createdAt: 'desc' },
      include: {
        roles: {
          where: { role: { deletedAt: null } },
          select: { roleId: true, role: { select: { id: true, name: true } } }
        }
      }
    });
  }

  async getById(id: string) {
    const admin = await this.prisma.adminUser.findFirst({
      where: { id, deletedAt: null },
      include: {
        roles: {
          where: { role: { deletedAt: null } },
          select: { roleId: true, role: { select: { id: true, name: true } } }
        }
      }
    });
    if (!admin) throw new NotFoundException('Admin user not found');
    return admin;
  }

  async create(params: {
    cognitoSub: string;
    email: string;
    status?: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const existing = await this.prisma.adminUser.findUnique({ where: { cognitoSub: params.cognitoSub } });
    if (existing && existing.deletedAt === null) {
      throw new ConflictException('Admin user already exists for this Cognito sub');
    }

    const created = existing
      ? await this.prisma.adminUser.update({
          where: { id: existing.id },
          data: {
            email: params.email,
            status: params.status ?? AdminUserStatus.ACTIVE,
            deletedAt: null
          }
        })
      : await this.prisma.adminUser.create({
          data: {
            cognitoSub: params.cognitoSub,
            email: params.email,
            status: params.status ?? AdminUserStatus.ACTIVE
          }
        });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.create',
      targetType: 'admin_user',
      targetId: created.id,
      before: existing ? { id: existing.id, deletedAt: existing.deletedAt } : null,
      after: { cognitoSub: created.cognitoSub, email: created.email, status: created.status },
      request: params.request
    });

    return created;
  }

  async update(params: {
    id: string;
    email?: string;
    status?: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const before = await this.prisma.adminUser.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Admin user not found');

    const after = await this.prisma.adminUser.update({
      where: { id: params.id },
      data: {
        email: params.email ?? undefined,
        status: params.status ?? undefined
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.update',
      targetType: 'admin_user',
      targetId: after.id,
      before: { email: before.email, status: before.status },
      after: { email: after.email, status: after.status },
      request: params.request
    });

    return after;
  }

  async softDelete(params: { id: string; actorAdminUserId: string; request?: Request }) {
    const before = await this.prisma.adminUser.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Admin user not found');

    await this.prisma.adminUser.update({
      where: { id: params.id },
      data: { deletedAt: new Date() }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.delete',
      targetType: 'admin_user',
      targetId: params.id,
      before: { email: before.email, status: before.status },
      after: { deleted: true },
      request: params.request
    });
  }

  async replaceRoles(params: {
    adminUserId: string;
    roleIds: readonly string[];
    actorAdminUserId: string;
    request?: Request;
  }) {
    const admin = await this.prisma.adminUser.findFirst({ where: { id: params.adminUserId, deletedAt: null } });
    if (!admin) throw new NotFoundException('Admin user not found');

    const desired = uniqueSorted(params.roleIds);

    const existing = await this.prisma.adminUserRole.findMany({
      where: { adminUserId: params.adminUserId },
      select: { roleId: true }
    });
    const beforeRoleIds = uniqueSorted(existing.map((x) => x.roleId));

    if (desired.length > 0) {
      const found = await this.prisma.role.findMany({
        where: { id: { in: desired }, deletedAt: null },
        select: { id: true }
      });
      if (found.length !== desired.length) throw new NotFoundException('One or more roles not found');
    }

    await this.prisma.$transaction(async (tx: any) => {
      await tx.adminUserRole.deleteMany({ where: { adminUserId: params.adminUserId } });
      if (desired.length > 0) {
        await tx.adminUserRole.createMany({
          data: desired.map((roleId) => ({ adminUserId: params.adminUserId, roleId })),
          skipDuplicates: true
        });
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.assign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: { roleIds: beforeRoleIds },
      after: { roleIds: desired },
      request: params.request
    });
  }
}
