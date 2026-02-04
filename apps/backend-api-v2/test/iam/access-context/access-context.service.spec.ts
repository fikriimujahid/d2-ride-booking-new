import { ForbiddenException } from '@nestjs/common';
import type { AuthenticatedUser } from '../../../src/auth/interfaces/authenticated-user';
import { AccessContextService } from '../../../src/iam/access-context/access-context.service';
import type { PrismaService } from '../../../src/database/prisma.service';

type MockPrismaService = {
  adminUser: {
    findFirst: jest.Mock;
  };
  adminUserRole: {
    findMany: jest.Mock;
  };
  rolePermission: {
    findMany: jest.Mock;
  };
  permission: {
    findMany: jest.Mock;
  };
};

function makeAuthUser(overrides?: Partial<AuthenticatedUser>): AuthenticatedUser {
  return {
    userId: 'cognito-sub-123',
    email: 'admin@test.d2.fikri.dev',
    systemGroups: ['ADMIN'],
    claims: { sub: 'cognito-sub-123', email: 'admin@test.d2.fikri.dev' },
    ...overrides
  } as AuthenticatedUser;
}

describe('AccessContextService', () => {
  it('fails closed when admin user is not found', async () => {
    const prismaMock: MockPrismaService = {
      adminUser: { findFirst: jest.fn().mockResolvedValue(null) },
      adminUserRole: { findMany: jest.fn() },
      rolePermission: { findMany: jest.fn() },
      permission: { findMany: jest.fn().mockResolvedValue([]) }
    };

    const service = new AccessContextService(prismaMock as unknown as PrismaService);

    await expect(service.getAdminMe(makeAuthUser())).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('returns empty roles/permissions when admin has no roles', async () => {
    const prismaMock: MockPrismaService = {
      adminUser: { findFirst: jest.fn().mockResolvedValue({ id: 'uuid-1', email: 'admin@test.d2.fikri.dev' }) },
      adminUserRole: { findMany: jest.fn().mockResolvedValue([]) },
      rolePermission: { findMany: jest.fn() },
      permission: { findMany: jest.fn().mockResolvedValue([{ key: 'dashboard:view' }, { key: 'driver:view' }]) }
    };

    const service = new AccessContextService(prismaMock as unknown as PrismaService);
    const result = await service.getAdminMe(
      makeAuthUser({
        claims: ({ sub: 'cognito-sub-123', name: 'Admin Test' } as unknown) as AuthenticatedUser['claims']
      })
    );

    expect(result.user.id).toBe('uuid-1');
    expect(result.roles).toEqual([]);
    expect(result.permissions).toEqual([]);
    expect(result.modules.dashboard.view).toBe(false);
  });

  it('builds modules map from permission catalog + granted permissions', async () => {
    const prismaMock: MockPrismaService = {
      adminUser: { findFirst: jest.fn().mockResolvedValue({ id: 'uuid-1', email: 'admin@test.d2.fikri.dev' }) },
      adminUserRole: {
        findMany: jest.fn().mockResolvedValue([
          { role: { id: 'role-1', name: 'OPERATION_MANAGER' } }
        ])
      },
      rolePermission: {
        findMany: jest.fn().mockResolvedValue([
          { permission: { key: 'dashboard:view' } },
          { permission: { key: 'driver:update' } }
        ])
      },
      permission: {
        findMany: jest.fn().mockResolvedValue([
          { key: 'dashboard:view' },
          { key: 'dashboard:read' },
          { key: 'driver:view' },
          { key: 'driver:read' },
          { key: 'driver:update' }
        ])
      }
    };

    const service = new AccessContextService(prismaMock as unknown as PrismaService);
    const result = await service.getAdminMe(makeAuthUser());

    expect(result.roles).toEqual(['OPERATION_MANAGER']);
    expect(result.permissions).toEqual(['dashboard:view', 'driver:update']);
    expect(result.modules.dashboard.view).toBe(true);
    expect(result.modules.dashboard.read).toBe(false);
    expect(result.modules.driver.view).toBe(false);
    expect(result.modules.driver.update).toBe(true);
  });
});
