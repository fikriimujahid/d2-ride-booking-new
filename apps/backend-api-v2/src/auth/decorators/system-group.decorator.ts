import { SetMetadata } from '@nestjs/common';
import type { SystemGroup as SystemGroupEnum } from '../enums/system-group.enum';

export const SYSTEM_GROUPS_KEY = 'auth:systemGroups';

/**
 * Declares which Cognito system group(s) may access a handler.
 *
 * This is NOT RBAC (no roles/permissions). It is coarse system access only.
 */
export function SystemGroup(...groups: readonly SystemGroupEnum[]) {
  return SetMetadata(SYSTEM_GROUPS_KEY, groups);
}
