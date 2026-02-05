// Import class-validator decorators for validation
import { ArrayUnique, IsArray, IsUUID } from 'class-validator';

/**
 * ReplaceAdminUserRolesDto - Request body for replacing admin user's roles
 * Used by POST /admin/admin-users/:id/roles endpoint.
 * Replaces entire role assignment (not additive).
 * 
 * Behavior:
 * - Removes all existing role assignments
 * - Assigns new roles specified in array
 * - Empty array removes all roles
 * - Duplicate UUIDs are rejected
 */
export class ReplaceAdminUserRolesDto {
  /** Array of role UUIDs to assign - replaces all existing assignments */
  @IsArray()
  @ArrayUnique()  // No duplicate role IDs allowed
  @IsUUID('4', { each: true })  // Each element must be valid UUID v4
  roleIds!: string[];
}
