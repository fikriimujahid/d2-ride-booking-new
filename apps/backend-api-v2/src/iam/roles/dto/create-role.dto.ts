// Import validation decorators
import { IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * CreateRoleDto - Data Transfer Object for creating new roles
 * Roles are named collections of permissions
 */
export class CreateRoleDto {
  /** 
   * Role name (e.g., 'SUPER_ADMIN', 'ANALYST', 'OPERATION_MANAGER')
   * Required, max 64 characters
   */
  @IsString()
  @MaxLength(64)
  name!: string;

  /** 
   * Human-readable description of the role's purpose
   * Optional, max 255 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;
}
