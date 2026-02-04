import { NotFoundException } from '@nestjs/common';
import { AdminUserService } from '../../../src/iam/admin-users/admin-user.service';

describe('AdminUserService.replaceRoles', () => {
  it('throws when admin user not found', async () => {
    const prismaMock = {
      adminUser: { findFirst: jest.fn().mockResolvedValue(null) }
    } as any;

    const auditMock = { logRbacAction: jest.fn() } as any;
    const service = new AdminUserService(prismaMock, auditMock);

    await expect(
      service.replaceRoles({
        adminUserId: 'a1',
        roleIds: ['00000000-0000-4000-8000-000000000001'],
        actorAdminUserId: 'actor'
      })
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('replaces mappings in a transaction and audits', async () => {
    const tx = {
      adminUserRole: {
        deleteMany: jest.fn().mockResolvedValue(undefined),
        createMany: jest.fn().mockResolvedValue({ count: 2 })
      }
    };

    const prismaMock = {
      adminUser: { findFirst: jest.fn().mockResolvedValue({ id: 'a1' }) },
      adminUserRole: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce([{ roleId: 'r-old' }])
      },
      role: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ id: 'r1' }, { id: 'r2' }])
      },
      $transaction: jest.fn(async (fn: any) => fn(tx))
    } as any;

    const auditMock = { logRbacAction: jest.fn().mockResolvedValue(undefined) } as any;
    const service = new AdminUserService(prismaMock, auditMock);

    await service.replaceRoles({
      adminUserId: 'a1',
      roleIds: ['r1', 'r2'],
      actorAdminUserId: 'actor'
    });

    expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.adminUserRole.deleteMany).toHaveBeenCalledWith({ where: { adminUserId: 'a1' } });
    expect(tx.adminUserRole.createMany).toHaveBeenCalledWith({
      data: [{ adminUserId: 'a1', roleId: 'r1' }, { adminUserId: 'a1', roleId: 'r2' }],
      skipDuplicates: true
    });

    expect(auditMock.logRbacAction).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'role.assign',
        targetType: 'admin_user',
        targetId: 'a1',
        before: { roleIds: ['r-old'] },
        after: { roleIds: ['r1', 'r2'] }
      })
    );
  });
});
