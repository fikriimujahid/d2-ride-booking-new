import { SetMetadata } from '@nestjs/common';
import type { PermissionKey, PermissionRequirement } from './permission.types';

export const PERMISSIONS_KEY = 'iam:requiredPermissions';

/**
 * Declares required permission(s) for a handler.
 *
 * Semantics: OR (any-of). Example:
 * - `@RequirePermissions('dashboard:view', 'report:generate')` => allow if user has either.
 */
export function RequirePermissions(...permissions: readonly PermissionKey[]) {
  const requirement: PermissionRequirement = { anyOf: permissions };
  return SetMetadata(PERMISSIONS_KEY, requirement);
}
