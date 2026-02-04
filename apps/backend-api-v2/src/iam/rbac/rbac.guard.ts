import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { SystemGroup } from '../../auth/enums/system-group.enum';
import { PERMISSIONS_KEY } from './permission.decorator';
import type { PermissionRequirement } from './permission.types';
import { PermissionService } from './permission.service';

@Injectable()
export class RbacGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly permissionService: PermissionService
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();

    const user = request.user;
    if (!user) throw new UnauthorizedException('Unauthorized');

    // Phase B is ADMIN-only and assumes SystemGroupGuard already ran.
    if (!user.systemGroups.includes(SystemGroup.ADMIN)) {
      throw new ForbiddenException('Forbidden');
    }

    const requirement = this.reflector.getAllAndOverride<PermissionRequirement | undefined>(PERMISSIONS_KEY, [
      context.getHandler(),
      context.getClass()
    ]);

    // Fail closed if permissions were not declared.
    if (!requirement || requirement.anyOf.length === 0) {
      throw new ForbiddenException('Forbidden');
    }

    // Cache per request.
    if (!request.rbac) {
      const resolved = await this.permissionService.resolveForAdminCognitoSub(user.userId);
      if (!resolved) throw new ForbiddenException('Forbidden');
      request.rbac = resolved;
    }

    const allowed = this.permissionService.isAllowed(requirement.anyOf, request.rbac);
    if (!allowed) throw new ForbiddenException('Forbidden');

    return true;
  }
}
