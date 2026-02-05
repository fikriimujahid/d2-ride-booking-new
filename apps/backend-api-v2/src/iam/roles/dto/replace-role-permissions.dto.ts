// Import validation decorators
import { ArrayUnique, IsArray, IsUUID } from 'class-validator';

/**
 * ReplaceRolePermissionsDto - DTO for replacing all permissions assigned to a role
 * This is a full replacement operation, not an additive update
 */
export class ReplaceRolePermissionsDto {
  /** 
   * Array of permission UUIDs to assign to the role
   * Replaces all existing assignments
   * Must be unique UUIDs (no duplicates)
   */
  @IsArray()
  @ArrayUnique()  // Ensure no duplicate permission IDs
  @IsUUID('4', { each: true })  // Validate each item is a UUID v4
  permissionIds!: string[];
}
