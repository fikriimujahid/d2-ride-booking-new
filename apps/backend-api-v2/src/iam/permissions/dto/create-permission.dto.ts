// Import validation decorators from class-validator
import { IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * CreatePermissionDto - Data Transfer Object for creating new permissions
 * Validated automatically by NestJS ValidationPipe
 */
export class CreatePermissionDto {
  /** 
   * Permission key in format 'resource:action' (e.g., 'user:create', 'dashboard:view')
   * Required, max 128 characters
   */
  @IsString()
  @MaxLength(128)
  key!: string;

  /** 
   * Human-readable description of what this permission grants
   * Optional, max 255 characters
   */
  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;
}
