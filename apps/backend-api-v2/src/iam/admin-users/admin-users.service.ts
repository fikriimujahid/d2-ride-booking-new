import { ForbiddenException, Injectable } from '@nestjs/common';
import { AdminUserStatus } from '@prisma/client';
import type { Request } from 'express';
import { AuditService } from '../../audit/audit.service';
import { PrismaService } from '../../database/prisma.service';

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async ensureAdminUser(params: {
    cognitoSub: string;
    email: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const existing = await this.prisma.adminUser.findUnique({
      where: { cognitoSub: params.cognitoSub }
    });

    const admin = await this.prisma.adminUser.upsert({
      where: { cognitoSub: params.cognitoSub },
      update: { email: params.email, deletedAt: null },
      create: {
        cognitoSub: params.cognitoSub,
        email: params.email,
        status: AdminUserStatus.ACTIVE
      }
    });

    if (!existing) {
      await this.audit.logRbacAction({
        actorAdminUserId: params.actorAdminUserId,
        action: 'admin.create',
        targetType: 'admin_user',
        targetId: admin.id,
        before: null,
        after: { cognitoSub: admin.cognitoSub, email: admin.email, status: admin.status },
        request: params.request
      });
    }

    return admin;
  }

  async setAdminStatus(params: {
    adminUserId: string;
    status: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const before = await this.prisma.adminUser.findUnique({ where: { id: params.adminUserId } });
    if (!before || before.deletedAt) throw new ForbiddenException('Forbidden');

    const after = await this.prisma.adminUser.update({
      where: { id: params.adminUserId },
      data: { status: params.status }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.status_change',
      targetType: 'admin_user',
      targetId: after.id,
      before: { status: before.status },
      after: { status: after.status },
      request: params.request
    });

    return after;
  }

  async assignRole(params: {
    adminUserId: string;
    roleId: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    const mapping = await this.prisma.adminUserRole.upsert({
      where: { adminUserId_roleId: { adminUserId: params.adminUserId, roleId: params.roleId } },
      update: {},
      create: { adminUserId: params.adminUserId, roleId: params.roleId }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.assign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: null,
      after: { roleId: params.roleId },
      request: params.request
    });

    return mapping;
  }

  async unassignRole(params: {
    adminUserId: string;
    roleId: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    await this.prisma.adminUserRole.delete({
      where: { adminUserId_roleId: { adminUserId: params.adminUserId, roleId: params.roleId } }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.unassign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: null,
      after: { roleId: params.roleId },
      request: params.request
    });
  }
}
