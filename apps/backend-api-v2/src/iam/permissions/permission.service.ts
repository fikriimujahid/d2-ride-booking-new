import {
  ConflictException,
  Injectable,
  NotFoundException
} from '@nestjs/common';
import type { Request } from 'express';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../audit/audit.service';

@Injectable()
export class AdminPermissionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list(): Promise<any[]> {
    return this.prisma.permission.findMany({
      where: { deletedAt: null },
      orderBy: { key: 'asc' }
    });
  }

  async getById(id: string): Promise<any> {
    const row = await this.prisma.permission.findFirst({
      where: { id, deletedAt: null }
    });
    if (!row) throw new NotFoundException('Permission not found');
    return row;
  }

  async create(params: {
    key: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<any> {
    const existing = await this.prisma.permission.findUnique({ where: { key: params.key } });

    if (existing && existing.deletedAt === null) {
      throw new ConflictException('Permission key already exists');
    }

    const created = existing
      ? await this.prisma.permission.update({
          where: { id: existing.id },
          data: { key: params.key, description: params.description, deletedAt: null }
        })
      : await this.prisma.permission.create({
          data: { key: params.key, description: params.description }
        });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.create',
      targetType: 'permission',
      targetId: created.id,
      before: existing ? { id: existing.id, key: existing.key, deletedAt: existing.deletedAt } : null,
      after: { id: created.id, key: created.key, description: created.description },
      request: params.request
    });

    return created;
  }

  async update(params: {
    id: string;
    key?: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<any> {
    const before = await this.prisma.permission.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Permission not found');

    const after = await this.prisma.permission.update({
      where: { id: params.id },
      data: {
        key: params.key ?? undefined,
        description: params.description ?? undefined
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.update',
      targetType: 'permission',
      targetId: after.id,
      before: { key: before.key, description: before.description },
      after: { key: after.key, description: after.description },
      request: params.request
    });

    return after;
  }

  async softDelete(params: {
    id: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<void> {
    const before = await this.prisma.permission.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Permission not found');

    const inUse = await this.prisma.rolePermission.findFirst({
      where: {
        permissionId: params.id,
        role: { deletedAt: null }
      },
      select: { roleId: true }
    });
    if (inUse) throw new ConflictException('Permission is assigned to a role');

    await this.prisma.permission.update({
      where: { id: params.id },
      data: { deletedAt: new Date() }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.delete',
      targetType: 'permission',
      targetId: params.id,
      before: { key: before.key, description: before.description },
      after: { deleted: true },
      request: params.request
    });
  }
}
