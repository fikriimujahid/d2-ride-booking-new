// Import SetMetadata to attach custom metadata to controllers/routes
import { SetMetadata } from '@nestjs/common';
// Import SystemGroup enum type
import type { SystemGroup as SystemGroupEnum } from '../enums/system-group.enum';

// Metadata key used to store system group requirements on routes
export const SYSTEM_GROUPS_KEY = 'auth:systemGroups';

/**
 * @SystemGroup() decorator - Declares which Cognito system group(s) may access a handler
 * 
 * This provides coarse-grained system-level access control based on Cognito groups.
 * This is NOT RBAC (no fine-grained roles/permissions).
 * For role-based access control, use the RBAC module guards instead.
 * 
 * Usage:
 *   @SystemGroup(SystemGroup.ADMIN)
 *   @SystemGroup(SystemGroup.ADMIN, SystemGroup.DRIVER)
 * 
 * @param groups - One or more SystemGroup enum values (ADMIN, DRIVER, PASSENGER)
 * @returns NestJS decorator function that attaches group requirements to the route
 */
export function SystemGroup(...groups: readonly SystemGroupEnum[]) {
  // Attach group requirements as metadata using the defined key
  return SetMetadata(SYSTEM_GROUPS_KEY, groups);
}
