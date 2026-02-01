import { UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import { JwtAuthGuard } from '../../../src/auth/jwt-auth.guard';
import type { CognitoJwtStrategy } from '../../../src/auth/cognito-jwt.strategy';
import type { AuthenticatedUser } from '../../../src/auth/interfaces/authenticated-user';
import { SystemGroup } from '../../../src/auth/enums/system-group.enum';

function makeContext(request: Request): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request
    })
  } as unknown as ExecutionContext;
}

describe('JwtAuthGuard', () => {
  it('rejects when Authorization header missing (401)', async () => {
    const strategy = { verifyJwt: jest.fn() } as unknown as CognitoJwtStrategy;
    const guard = new JwtAuthGuard(strategy);

    const req = {
      header: () => undefined
    } as unknown as Request;
    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects when scheme is not Bearer (401)', async () => {
    const strategy = { verifyJwt: jest.fn() } as unknown as CognitoJwtStrategy;
    const guard = new JwtAuthGuard(strategy);

    const req = {
      header: (name: string) => (name.toLowerCase() === 'authorization' ? 'Basic abc' : undefined)
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('attaches request.user on success', async () => {
    const user: AuthenticatedUser = {
      userId: 'sub-123',
      email: 'admin@test.d2.fikri.dev',
      systemGroups: [SystemGroup.ADMIN],
      claims: { sub: 'sub-123' }
    };

    const strategy = {
      verifyJwt: jest.fn(async () => user)
    } as unknown as CognitoJwtStrategy;

    const guard = new JwtAuthGuard(strategy);

    const req = {
      header: (name: string) => (name.toLowerCase() === 'authorization' ? 'Bearer token' : undefined)
    } as unknown as Request;

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user).toEqual(user);
  });
});
