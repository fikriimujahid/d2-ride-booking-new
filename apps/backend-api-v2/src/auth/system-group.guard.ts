// Import NestJS guards and exceptions for authorization
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
// Import Reflector to read metadata from decorators
import { Reflector } from '@nestjs/core';
// Import Express Request type
import type { Request } from 'express';
// Import the metadata key for system group requirements
import { SYSTEM_GROUPS_KEY } from './decorators/system-group.decorator';
// Import SystemGroup enum type
import type { SystemGroup } from './enums/system-group.enum';

/**
 * SystemGroupGuard - Authorization guard for Cognito system groups
 * Enforces coarse-grained access control based on user's Cognito groups (ADMIN, DRIVER, PASSENGER)
 * This is NOT fine-grained RBAC - use RBAC guards for role/permission-based access
 * Use with @SystemGroup(...) decorator to specify allowed groups
 */
@Injectable()
export class SystemGroupGuard implements CanActivate {
  // Inject Reflector to read decorator metadata
  constructor(private readonly reflector: Reflector) {}

  /**
   * Guard activation method - checks if user belongs to required system groups
   * @param context - Execution context containing request and metadata
   * @returns true if user has required group, throws exception otherwise
   */
  canActivate(context: ExecutionContext): boolean {
    // Get the HTTP request object
    const request = context.switchToHttp().getRequest<Request>();
    // Get the authenticated user from request (set by JwtAuthGuard)
    const user = request.user;

    // Ensure user is authenticated (JwtAuthGuard should run first)
    if (!user) {
      // Authentication is required before checking authorization
      throw new UnauthorizedException('Unauthorized');
    }

    // Read required system groups from @SystemGroup() decorator metadata
    // Checks both the handler (method) and class level decorators
    const required = this.reflector.getAllAndOverride<readonly SystemGroup[] | undefined>(SYSTEM_GROUPS_KEY, [
      context.getHandler(),  // Method-level decorator
      context.getClass()     // Class-level decorator
    ]);

    // Default deny if group requirement is missing (fail-safe)
    if (!required || required.length === 0) {
      throw new ForbiddenException('Forbidden');
    }

    // Create a set of user's groups for efficient lookup
    const userGroups = new Set(user.systemGroups);
    // Check if user has at least one of the required groups
    const allowed = required.some((g) => userGroups.has(g));

    // Deny access if user doesn't have any required group
    if (!allowed) {
      throw new ForbiddenException('Forbidden');
    }

    // Allow request to proceed
    return true;
  }
}
