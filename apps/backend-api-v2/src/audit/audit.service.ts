import { Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../database/prisma.service';

export type RbacAuditAction =
  | 'admin.create'
  | 'admin.status_change'
  | 'admin.update'
  | 'admin.delete'
  | 'role.create'
  | 'role.update'
  | 'role.delete'
  | 'role.assign'
  | 'role.unassign'
  | 'permission.create'
  | 'permission.update'
  | 'permission.delete'
  | 'permission.assign'
  | 'permission.unassign'
  | 'rbac.seed';

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async logRbacAction(params: {
    actorAdminUserId: string;
    action: RbacAuditAction;
    targetType: string;
    targetId?: string;
    before?: unknown;
    after?: unknown;
    request?: Request;
  }): Promise<void> {
    const { actorAdminUserId, action, targetType, targetId, before, after, request } = params;

    const beforeJson =
      before === undefined ? undefined : before === null ? Prisma.JsonNull : (before as Prisma.InputJsonValue);
    const afterJson =
      after === undefined ? undefined : after === null ? Prisma.JsonNull : (after as Prisma.InputJsonValue);

    await this.prisma.adminAuditLog.create({
      data: {
        actorAdminUserId,
        action,
        targetType,
        targetId,
        before: beforeJson,
        after: afterJson,
        ipAddress: request?.ip,
        userAgent: typeof request?.headers?.['user-agent'] === 'string' ? request.headers['user-agent'] : undefined,
        requestId: request?.requestId
      }
    });
  }
}
