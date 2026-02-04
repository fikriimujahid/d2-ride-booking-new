import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import type { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { SystemGroup } from '../../../src/auth/enums/system-group.enum';
import { RbacGuard } from '../../../src/iam/rbac/rbac.guard';
import { PERMISSIONS_KEY } from '../../../src/iam/rbac/permission.decorator';
import type { PermissionService } from '../../../src/iam/rbac/permission.service';

function makeContext(request: Request): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request
    }),
    getHandler: () => ({}),
    getClass: () => (class Test {})
  } as unknown as ExecutionContext;
}

describe('RbacGuard', () => {
  it('401 when unauthenticated', async () => {
    const reflector = { getAllAndOverride: jest.fn() } as unknown as Reflector;
    const permissionService = {} as unknown as PermissionService;

    const guard = new RbacGuard(reflector, permissionService);
    const req = {} as Request;

    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('403 when not ADMIN system group', async () => {
    const reflector = {
      getAllAndOverride: jest.fn(() => ({ anyOf: ['dashboard:view'] }))
    } as unknown as Reflector;

    const permissionService = {
      resolveForAdminCognitoSub: jest.fn(),
      isAllowed: jest.fn()
    } as unknown as PermissionService;

    const guard = new RbacGuard(reflector, permissionService);

    const req = {
      user: { userId: 'sub', email: 'x', systemGroups: [SystemGroup.DRIVER], claims: { sub: 'sub' } }
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('403 when permission metadata missing (fail closed)', async () => {
    const reflector = { getAllAndOverride: jest.fn(() => undefined) } as unknown as Reflector;

    const permissionService = {
      resolveForAdminCognitoSub: jest.fn(),
      isAllowed: jest.fn()
    } as unknown as PermissionService;

    const guard = new RbacGuard(reflector, permissionService);

    const req = {
      user: { userId: 'sub', email: 'x', systemGroups: [SystemGroup.ADMIN], claims: { sub: 'sub' } }
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows when required permission is granted', async () => {
    const reflector = {
      getAllAndOverride: jest.fn((key: string) => (key === PERMISSIONS_KEY ? { anyOf: ['analytics:view'] } : undefined))
    } as unknown as Reflector;

    const permissionService = {
      resolveForAdminCognitoSub: jest.fn(async () => ({
        adminUserId: 'a1',
        roleNames: ['anything'],
        grantedPermissions: ['analytics:view']
      })),
      isAllowed: jest.fn(() => true)
    } as unknown as PermissionService;

    const guard = new RbacGuard(reflector, permissionService);

    const req = {
      user: { userId: 'sub', email: 'x', systemGroups: [SystemGroup.ADMIN], claims: { sub: 'sub' } }
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
  });

  it('403 when permission service resolves null (admin not provisioned/disabled)', async () => {
    const reflector = {
      getAllAndOverride: jest.fn(() => ({ anyOf: ['dashboard:view'] }))
    } as unknown as Reflector;

    const permissionService = {
      resolveForAdminCognitoSub: jest.fn(async () => null),
      isAllowed: jest.fn()
    } as unknown as PermissionService;

    const guard = new RbacGuard(reflector, permissionService);

    const req = {
      user: { userId: 'sub', email: 'x', systemGroups: [SystemGroup.ADMIN], claims: { sub: 'sub' } }
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(ForbiddenException);
  });
});
