// Import SetMetadata to attach custom metadata to routes
import { SetMetadata } from '@nestjs/common';
// Import permission type definitions
import type { PermissionKey, PermissionRequirement } from './permission.types';

// Metadata key for storing permission requirements on routes
export const PERMISSIONS_KEY = 'iam:requiredPermissions';

/**
 * @RequirePermissions() decorator - Declares required permission(s) for a route handler
 * 
 * Semantics: OR (any-of) - user needs at least one of the listed permissions
 * 
 * Examples:
 *   @RequirePermissions('dashboard:view')
 *   - Requires dashboard:view permission
 * 
 *   @RequirePermissions('dashboard:view', 'report:generate')
 *   - Requires EITHER dashboard:view OR report:generate (any-of)
 * 
 * Permission format: 'resource:action' (e.g., 'user:create', 'report:delete')
 * Wildcards supported: 'resource:*' grants all actions on resource
 * 
 * @param permissions - One or more permission keys required to access the route
 * @returns NestJS decorator function that attaches permission requirements
 */
export function RequirePermissions(...permissions: readonly PermissionKey[]) {
  // Create permission requirement with anyOf semantics
  const requirement: PermissionRequirement = { anyOf: permissions };
  // Attach as metadata for RbacGuard to read
  return SetMetadata(PERMISSIONS_KEY, requirement);
}
