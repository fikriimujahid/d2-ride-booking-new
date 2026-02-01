import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import type { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { SystemGroupGuard } from '../../../src/auth/system-group.guard';
import { SystemGroup } from '../../../src/auth/enums/system-group.enum';
import type { AuthenticatedUser } from '../../../src/auth/interfaces/authenticated-user';

function makeContext(request: Request): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request
    }),
    getHandler: () => ({}),
    getClass: () => (class Test {})
  } as unknown as ExecutionContext;
}

describe('SystemGroupGuard', () => {
  it('fails closed with 401 when request.user missing', () => {
    const reflector = { getAllAndOverride: jest.fn() } as unknown as Reflector;
    const guard = new SystemGroupGuard(reflector);

    const req = {} as Request;
    expect(() => guard.canActivate(makeContext(req))).toThrow(UnauthorizedException);
  });

  it('denies by default when metadata missing (403)', () => {
    const reflector = { getAllAndOverride: jest.fn(() => undefined) } as unknown as Reflector;
    const guard = new SystemGroupGuard(reflector);

    const user: AuthenticatedUser = {
      userId: 'sub-123',
      email: 'x',
      systemGroups: [SystemGroup.ADMIN],
      claims: { sub: 'sub-123' }
    };

    const req = { user } as unknown as Request;
    expect(() => guard.canActivate(makeContext(req))).toThrow(ForbiddenException);
  });

  it('allows matching group', () => {
    const reflector = { getAllAndOverride: jest.fn(() => [SystemGroup.ADMIN]) } as unknown as Reflector;
    const guard = new SystemGroupGuard(reflector);

    const user: AuthenticatedUser = {
      userId: 'sub-123',
      email: 'x',
      systemGroups: [SystemGroup.ADMIN],
      claims: { sub: 'sub-123' }
    };

    const req = { user } as unknown as Request;
    expect(guard.canActivate(makeContext(req))).toBe(true);
  });

  it('forbids wrong group (403)', () => {
    const reflector = { getAllAndOverride: jest.fn(() => [SystemGroup.ADMIN]) } as unknown as Reflector;
    const guard = new SystemGroupGuard(reflector);

    const user: AuthenticatedUser = {
      userId: 'sub-123',
      email: 'x',
      systemGroups: [SystemGroup.DRIVER],
      claims: { sub: 'sub-123' }
    };

    const req = { user } as unknown as Request;
    expect(() => guard.canActivate(makeContext(req))).toThrow(ForbiddenException);
  });

  it('supports multiple allowed groups (any-of)', () => {
    const reflector = {
      getAllAndOverride: jest.fn(() => [SystemGroup.ADMIN, SystemGroup.DRIVER])
    } as unknown as Reflector;

    const guard = new SystemGroupGuard(reflector);

    const user: AuthenticatedUser = {
      userId: 'sub-123',
      email: 'x',
      systemGroups: [SystemGroup.DRIVER],
      claims: { sub: 'sub-123' }
    };

    const req = { user } as unknown as Request;
    expect(guard.canActivate(makeContext(req))).toBe(true);
  });
});
