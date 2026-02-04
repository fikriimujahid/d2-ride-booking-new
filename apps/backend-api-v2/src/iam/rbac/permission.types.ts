export type PermissionKey = '*' | `${string}:${string}`;

export interface PermissionRequirement {
  readonly anyOf: readonly PermissionKey[];
}

export interface PermissionResolution {
  readonly adminUserId: string;
  readonly roleNames: readonly string[];
  readonly grantedPermissions: readonly PermissionKey[];
}
