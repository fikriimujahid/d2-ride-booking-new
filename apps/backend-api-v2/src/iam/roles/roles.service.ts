import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../audit/audit.service';

@Injectable()
export class RolesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async createRole(params: { name: string; description?: string; actorAdminUserId: string }) {
    const role = await this.prisma.role.create({
      data: {
        name: params.name,
        description: params.description
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.create',
      targetType: 'role',
      targetId: role.id,
      before: null,
      after: { created: true, name: role.name }
    });

    return role;
  }

  async assignPermission(params: { roleId: string; permissionId: string; actorAdminUserId: string }) {
    const mapping = await this.prisma.rolePermission.upsert({
      where: {
        roleId_permissionId: {
          roleId: params.roleId,
          permissionId: params.permissionId
        }
      },
      create: {
        roleId: params.roleId,
        permissionId: params.permissionId
      },
      update: {}
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.assign',
      targetType: 'role',
      targetId: params.roleId,
      before: null,
      after: { permissionId: params.permissionId }
    });

    return mapping;
  }

  async unassignPermission(params: { roleId: string; permissionId: string; actorAdminUserId: string }) {
    await this.prisma.rolePermission.delete({
      where: {
        roleId_permissionId: {
          roleId: params.roleId,
          permissionId: params.permissionId
        }
      }
    });

    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.unassign',
      targetType: 'role',
      targetId: params.roleId,
      before: null,
      after: { permissionId: params.permissionId }
    });
  }
}
