/**
 * PermissionKey - Type representing a permission identifier
 * Format: 'resource:action' (e.g., 'user:create', 'dashboard:view')
 * Special case: '*' grants all permissions (superuser)
 * Wildcards: 'resource:*' grants all actions on a resource
 */
export type PermissionKey = '*' | `${string}:${string}`;

/**
 * PermissionRequirement - Specifies permission requirements for a route
 * anyOf: Array of permissions, user needs at least one (OR semantics)
 */
export interface PermissionRequirement {
  readonly anyOf: readonly PermissionKey[];
}

/**
 * PermissionResolution - Result of resolving a user's effective permissions
 * Contains user ID, assigned roles, and computed permission set
 */
export interface PermissionResolution {
  /** Database ID of the admin user */
  readonly adminUserId: string;
  
  /** Names of roles assigned to this admin user */
  readonly roleNames: readonly string[];
  
  /** Flattened set of all permissions granted via assigned roles */
  readonly grantedPermissions: readonly PermissionKey[];
}
