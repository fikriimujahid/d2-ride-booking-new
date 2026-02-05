// Import class-validator decorators for validation
import { IsEmail, IsEnum, IsOptional, MaxLength } from 'class-validator';
// Import AdminUserStatus enum from Prisma
import { AdminUserStatus } from '@prisma/client';

/**
 * UpdateAdminUserDto - Request body for updating admin users
 * Used by PUT /admin/admin-users/:id endpoint.
 * All fields are optional - only provided fields are updated.
 */
export class UpdateAdminUserDto {
  /** Email address - optional update */
  @IsOptional()
  @IsEmail()
  @MaxLength(320)
  email?: string;

  /** Admin user status - change between ACTIVE/DISABLED/PENDING */
  @IsOptional()
  @IsEnum(AdminUserStatus)  // ACTIVE, DISABLED, PENDING
  status?: AdminUserStatus;
}
