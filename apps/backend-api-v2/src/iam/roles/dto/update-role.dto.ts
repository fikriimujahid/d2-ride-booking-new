// Import validation decorators
import { IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * UpdateRoleDto - Data Transfer Object for updating existing roles
 * All fields are optional (partial update)
 */
export class UpdateRoleDto {
  /** 
   * Updated role name
   * Optional, max 64 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  name?: string;

  /** 
   * Updated human-readable description
   * Optional, max 255 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;
}
