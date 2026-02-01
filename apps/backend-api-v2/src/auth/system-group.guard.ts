import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { SYSTEM_GROUPS_KEY } from './decorators/system-group.decorator';
import type { SystemGroup } from './enums/system-group.enum';

@Injectable()
export class SystemGroupGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const user = request.user;

    if (!user) {
      // Authentication is required.
      throw new UnauthorizedException('Unauthorized');
    }

    const required = this.reflector.getAllAndOverride<readonly SystemGroup[] | undefined>(SYSTEM_GROUPS_KEY, [
      context.getHandler(),
      context.getClass()
    ]);

    // Default deny if group requirement is missing.
    if (!required || required.length === 0) {
      throw new ForbiddenException('Forbidden');
    }

    const userGroups = new Set(user.systemGroups);
    const allowed = required.some((g) => userGroups.has(g));

    if (!allowed) {
      throw new ForbiddenException('Forbidden');
    }

    return true;
  }
}
