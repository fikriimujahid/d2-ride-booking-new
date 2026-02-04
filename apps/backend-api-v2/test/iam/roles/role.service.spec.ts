import { NotFoundException } from '@nestjs/common';
import { RoleService } from '../../../src/iam/roles/role.service';

describe('RoleService.replacePermissions', () => {
  it('throws when role not found', async () => {
    const prismaMock = {
      role: { findFirst: jest.fn().mockResolvedValue(null) }
    } as any;

    const auditMock = { logRbacAction: jest.fn() } as any;
    const service = new RoleService(prismaMock, auditMock);

    await expect(
      service.replacePermissions({
        roleId: 'role-1',
        permissionIds: ['p1'],
        actorAdminUserId: 'actor'
      })
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('replaces mappings in a transaction and audits', async () => {
    const tx = {
      rolePermission: {
        deleteMany: jest.fn().mockResolvedValue(undefined),
        createMany: jest.fn().mockResolvedValue({ count: 2 })
      }
    };

    const prismaMock = {
      role: { findFirst: jest.fn().mockResolvedValue({ id: 'role-1' }) },
      rolePermission: {
        findMany: jest.fn().mockResolvedValue([{ permissionId: 'p-old' }])
      },
      permission: {
        findMany: jest.fn().mockResolvedValue([{ id: 'p1' }, { id: 'p2' }])
      },
      $transaction: jest.fn(async (fn: any) => fn(tx))
    } as any;

    const auditMock = { logRbacAction: jest.fn().mockResolvedValue(undefined) } as any;
    const service = new RoleService(prismaMock, auditMock);

    await service.replacePermissions({
      roleId: 'role-1',
      permissionIds: ['p1', 'p2'],
      actorAdminUserId: 'actor'
    });

    expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.rolePermission.deleteMany).toHaveBeenCalledWith({ where: { roleId: 'role-1' } });
    expect(tx.rolePermission.createMany).toHaveBeenCalledWith({
      data: [{ roleId: 'role-1', permissionId: 'p1' }, { roleId: 'role-1', permissionId: 'p2' }],
      skipDuplicates: true
    });

    expect(auditMock.logRbacAction).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'permission.assign',
        targetType: 'role',
        targetId: 'role-1',
        before: { permissionIds: ['p-old'] },
        after: { permissionIds: ['p1', 'p2'] }
      })
    );
  });
});
