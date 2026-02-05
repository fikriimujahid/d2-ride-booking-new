// Import validation decorators from class-validator
import { IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * UpdatePermissionDto - Data Transfer Object for updating existing permissions
 * All fields are optional (partial update)
 * Validated automatically by NestJS ValidationPipe
 */
export class UpdatePermissionDto {
  /** 
   * Updated permission key in format 'resource:action'
   * Optional, max 128 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(128)
  key?: string;

  /** 
   * Updated human-readable description
   * Optional, max 255 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;
}
