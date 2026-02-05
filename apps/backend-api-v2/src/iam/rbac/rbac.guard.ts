// Import NestJS guards and exceptions
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
// Import Reflector to read decorator metadata
import { Reflector } from '@nestjs/core';
// Import Express Request type
import type { Request } from 'express';
// Import SystemGroup enum
import { SystemGroup } from '../../auth/enums/system-group.enum';
// Import permission decorator metadata key
import { PERMISSIONS_KEY } from './permission.decorator';
// Import permission types
import type { PermissionRequirement } from './permission.types';
// Import permission resolution service
import { PermissionService } from './permission.service';

/**
 * RbacGuard - Authorization guard for fine-grained Role-Based Access Control
 * 
 * Phase B feature: Provides permission-level authorization for admin users
 * Should be used AFTER JwtAuthGuard and SystemGroupGuard
 * 
 * Flow:
 * 1. Verify user is authenticated (from JwtAuthGuard)
 * 2. Verify user is in ADMIN system group (RBAC is admin-only in Phase B)
 * 3. Read required permissions from @RequirePermissions() decorator
 * 4. Resolve user's permissions from database (cached per request)
 * 5. Check if user has at least one required permission
 * 
 * Usage: @UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)
 */
@Injectable()
export class RbacGuard implements CanActivate {
  /**
   * Constructor - injects dependencies
   * @param reflector - To read decorator metadata
   * @param permissionService - To resolve and check permissions
   */
  constructor(
    private readonly reflector: Reflector,
    private readonly permissionService: PermissionService
  ) {}

  /**
   * Guard activation method - checks if user has required permissions
   * @param context - Execution context containing request and metadata
   * @returns true if authorized, throws exception otherwise
   */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Get HTTP request object
    const request = context.switchToHttp().getRequest<Request>();

    // Ensure user is authenticated (should be set by JwtAuthGuard)
    const user = request.user;
    if (!user) throw new UnauthorizedException('Unauthorized');

    // Phase B RBAC is ADMIN-only; assumes SystemGroupGuard already ran
    // Future: could extend to other system groups
    if (!user.systemGroups.includes(SystemGroup.ADMIN)) {
      throw new ForbiddenException('Forbidden');
    }

    // Read required permissions from @RequirePermissions() decorator metadata
    // Checks both method-level and class-level decorators
    const requirement = this.reflector.getAllAndOverride<PermissionRequirement | undefined>(PERMISSIONS_KEY, [
      context.getHandler(),  // Method-level decorator
      context.getClass()     // Class-level decorator
    ]);

    // Fail closed if permissions were not declared (security: explicit is better than implicit)
    if (!requirement || requirement.anyOf.length === 0) {
      throw new ForbiddenException('Forbidden');
    }

    // Cache permission resolution per request to avoid redundant DB queries
    if (!request.rbac) {
      // Resolve user's permissions from database (roles -> permissions)
      const resolved = await this.permissionService.resolveForAdminCognitoSub(user.userId);
      if (!resolved) throw new ForbiddenException('Forbidden');  // User not found or inactive
      request.rbac = resolved;  // Cache for subsequent guards in this request
    }

    // Check if user has at least one of the required permissions
    const allowed = this.permissionService.isAllowed(requirement.anyOf, request.rbac);
    if (!allowed) throw new ForbiddenException('Forbidden');

    // Authorization successful
    return true;
  }
}
