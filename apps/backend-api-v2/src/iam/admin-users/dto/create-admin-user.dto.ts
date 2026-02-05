// Import class-validator decorators for validation
import { IsEmail, IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
// Import AdminUserStatus enum from Prisma
import { AdminUserStatus } from '@prisma/client';

/**
 * CreateAdminUserDto - Request body for creating admin users
 * Used by POST /admin/admin-users endpoint.
 * Creates link between Cognito user and RBAC admin user record.
 */
export class CreateAdminUserDto {
  /** Cognito sub (UUID) - unique identifier from AWS Cognito */
  @IsString()
  @MaxLength(64)
  cognitoSub!: string;

  /** Email address - must match Cognito email for consistency */
  @IsEmail()
  @MaxLength(320)
  email!: string;

  /** Admin user status - defaults to ACTIVE if not provided */
  @IsOptional()
  @IsEnum(AdminUserStatus)  // ACTIVE, DISABLED, PENDING
  status?: AdminUserStatus;
}
